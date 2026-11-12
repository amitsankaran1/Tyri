import Combine
import DeviceActivity
import FamilyControls
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Contains native value inputs only; no shared-store or actor access during IPC.
nonisolated private struct RecoveryJob: @unchecked Sendable {
    let ticket: MonitorReservation
    let schedule: DeviceActivitySchedule
    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    var fallback: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    func execute() -> (succeeded: Bool, reportsProgress: Bool, error: String?) {
        precondition(!Thread.isMainThread)
        let center = DeviceActivityCenter()
        let name = DeviceActivityName(rawValue: ticket.name)
        do {
            guard EnforcementTransaction.effectsAreEnabled else { throw CancellationError() }
            do { try center.startMonitoring(name, during: schedule, events: events) } catch {
                guard !fallback.isEmpty, EnforcementTransaction.effectsAreEnabled else { throw error }
                try center.startMonitoring(name, during: schedule, events: fallback)
                return (true, false, nil)
            }
            return (true, !events.isEmpty, nil)
        } catch { return (false, false, error.localizedDescription) }
    }
}

@MainActor
final class ForegroundRecovery: ObservableObject {
    static let shared = ForegroundRecovery()
    @Published private(set) var isChecking = true
    @Published private(set) var registeredUsageIDs: Set<UUID> = []
    @Published private(set) var hasChecked = false
    private var active = true
    // Explicit user mutations own a bounded completion window. Routine refresh
    // does not: it stops on resignation. Expiration revokes both kinds of work.
    private var acceptedWork = false
    private var commands: Set<UUID> = []
    private var endAcceptedWork: (() -> Void)?
    private var canRun: Bool { active || acceptedWork || !commands.isEmpty }

    /// App mutations finish their short state lease immediately. Native effects
    /// run off MainActor with a finite suspension assertion, including Save,
    /// NFC, cooldown release, deletion and Emergency Access.
    func finish(_ lease: EnforcementTransaction.Lease) {
        let effects = lease.finish(deferEffects: true)
        guard !effects.isEmpty else { return }
        let commandID = UUID()
        commands.insert(commandID)
        let end = beginBackgroundWork()
        Task {
            await Task.detached {
                for effect in effects where EnforcementTransaction.effectsAreEnabled { effect() }
            }.value
            commands.remove(commandID)
            end()
            if active { request() }
            else if !canRun {
                BlockingActuator.setEffectsEnabled(false)
                EnforcementTransaction.setEffectsEnabled(false)
            }
        }
    }

    func command<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let commandID = UUID()
        commands.insert(commandID)
        let end = beginBackgroundWork()
        defer {
            commands.remove(commandID)
            end()
            if active { request() }
            else if !canRun {
                BlockingActuator.setEffectsEnabled(false)
                EnforcementTransaction.setEffectsEnabled(false)
            }
        }
        return try await Task.detached {
            guard EnforcementTransaction.effectsAreEnabled else { throw CancellationError() }
            return try operation()
        }.value
    }

    func requestAccepted() {
        if !acceptedWork {
            acceptedWork = true
            endAcceptedWork = beginBackgroundWork()
        }
        // An explicit Save can arrive while the scene is inactive (e.g. a
        // system sheet). Its bounded assertion owns admission just like a command.
        BlockingActuator.setEffectsEnabled(true)
        EnforcementTransaction.setEffectsEnabled(true)
        Task { @MainActor in self.request() }
    }

    private func finishAcceptedWork() {
        acceptedWork = false
        endAcceptedWork?()
        endAcceptedWork = nil
        BlockingActuator.setEffectsEnabled(active || !commands.isEmpty)
        EnforcementTransaction.setEffectsEnabled(active || !commands.isEmpty)
    }
    private var worker: Task<Void, Never>?
    private var preparing = false
    private var started = false
    private var running = false
    /// Coalesces saves that arrive while native recovery IPC is in flight. The
    /// current pass may already have performed its final observation, so it
    /// cannot safely discover a newly persisted monitor context by itself.
    private var rerunRequested = false
    private var legacyRetirements: Set<String> = []
    private init() {}

    func retireLegacy(_ names: [String]) { legacyRetirements.formUnion(names) }
    func start() {
        guard !started else { return }
        _ = ScreenTimeManager.shared
        started = true
        #if canImport(UIKit)
        setActive(UIApplication.shared.applicationState == .active)
        #else
        setActive(true)
        #endif
    }

    /// Periodic work stops on resignation. Explicit accepted commands may finish
    /// within their background assertion; expiration closes every effect lane.
    /// Durable reservations let the next activation reconcile interrupted work.
    func setActive(_ value: Bool) {
        active = value
        BlockingActuator.setEffectsEnabled(value || acceptedWork || !commands.isEmpty)
        EnforcementTransaction.setEffectsEnabled(value || acceptedWork || !commands.isEmpty)
        SchedulingManager.shared.setForegroundActive(value)
        UsageLimitManager.shared.setForegroundActive(value)
        BreakManager.shared.setForegroundActive(value)
        if !value && !acceptedWork && commands.isEmpty {
            rerunRequested = false
            worker?.cancel()
            isChecking = false
        } else if started {
            request()
        }
    }

    private func prepare() {
        guard canRun, !preparing else { return }
        preparing = true
        worker = Task {
            let endPreparation = beginBackgroundWork()
            defer { endPreparation() }
            do {
                try await withLease {
                    Migration.runIfNeeded()
                    BlockStore.shared.reload()
                    AppGroupStore.shared.reload()
                }
            } catch { }
            preparing = false
            if canRun { request() }
        }
    }

    /// Protect the short state transaction and any already-started post-unlock
    /// effect from suspension. Expiration closes admission; it never attempts to
    /// unlock another thread's state transaction or interrupt native IPC.
    private func beginBackgroundWork() -> () -> Void {
        #if canImport(UIKit)
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Enforcement recovery") { [weak self] in
            self?.commands.removeAll()
            self?.finishAcceptedWork()
            self?.setActive(false)
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
                identifier = .invalid
            }
        }
        return {
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
                identifier = .invalid
            }
        }
        #else
        return {}
        #endif
    }

    func request() {
        guard started, canRun else { return }
        if !SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2),
           BlockStore.shared.loadError == nil, AppGroupStore.shared.loadError == nil { prepare(); return }
        // Deadline fallback is independent of any stalled native operation.
        // This lane never waits for a lease and never performs DeviceActivity IPC.
        let endDeadlineWork = beginBackgroundWork()
        if let lease = EnforcementTransaction.begin(wait: false) {
            // Refresh desired state before any pending apply can execute: a
            // schedule may have ended while inactive, and observation may stall.
            let changed = reconcileState()
            let effects = lease.finish(deferEffects: true)
            Task {
                await Task.detached { for effect in effects { effect() } }.value
                endDeadlineWork()
            }
            if changed {
                BreakManager.shared.publishPersistedState()
                AdHocManager.shared.publishPersistedState()
                UsageLimitManager.shared.refresh()
            }
        } else { endDeadlineWork() }
        guard BlockStore.shared.loadError == nil, AppGroupStore.shared.loadError == nil else {
            isChecking = false
            finishAcceptedWork()
            return
        }
        guard !running else {
            isChecking = true
            rerunRequested = true
            return
        }
        guard ScreenTimeManager.shared.authorizationStatus == .approved else {
            isChecking = false
            finishAcceptedWork()
            return
        }
        BlockStore.shared.flush()
        AppGroupStore.shared.flush()
        running = true
        isChecking = true
        // Restore the existing break timer before the first native observation:
        // a persisted break still needs its deadline tick if that read stalls.
        BreakManager.shared.publishPersistedState()
        worker = Task {
            let endPass = beginBackgroundWork()
            defer { endPass() }
            defer {
                running = false
                isChecking = false
                if canRun && rerunRequested {
                    rerunRequested = false
                    request()
                } else {
                    finishAcceptedWork()
                }
            }
            do {
                var attempted: Set<String> = []
                var errors: [UUID: String] = [:]
                var observed: Set<String> = []
                // A second pass can rearm an allowance whose deadline crossed during
                // IPC. Failed semantic operations are not blindly retried this run.
                for _ in 0..<2 {
                    try Task.checkCancellation()
                    guard canRun else { throw CancellationError() }
                    observed = await Task.detached { Self.observe() }.value
                    let jobs = try await withLease {
                        reconcileState()
                        return makePlan(observed: observed, attempted: &attempted)
                    }
                    try await retire(observed: observed)
                    for job in jobs {
                        let valid = try await withLease {
                            context(job.ticket.namespace) == job.ticket.owner.context
                                && MonitorRegistration.pending(job.ticket.namespace)?.owner == job.ticket.owner
                        }
                        guard valid else {
                            try await withLease { _ = MonitorRegistration.finish(job.ticket, context: nil, succeeded: false) }
                            continue
                        }
                        let outcome = await Task.detached { job.execute() }.value
                        try await withLease {
                            let result = completeRegistration(job.ticket, succeeded: outcome.succeeded)
                            if result == .promoted || result == .alreadyAccepted { observed.insert(job.ticket.name) }
                            if result == .promoted || result == .alreadyAccepted,
                                let id = Self.blockID(job.ticket.namespace)
                            {
                                if job.ticket.namespace.hasPrefix("usage.") {
                                    SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageError(blockID: id))
                                }
                                if job.ticket.namespace.hasPrefix("lock.") || job.ticket.namespace.hasPrefix("adhoc.") {
                                    SharedDefaults.suite.removeObject(
                                        forKey: SharedDefaults.Keys.usageLockError(blockID: id))
                                }
                            }
                            if result == .failed { publishFailure(job.ticket, detail: outcome.error, errors: &errors) }
                            if result == .promoted, !outcome.reportsProgress, job.ticket.namespace.hasPrefix("usage."),
                                let id = Self.blockID(job.ticket.namespace)
                            {
                                SharedDefaults.suite.removeObject(forKey: UsageProgress.key(id))
                            }
                            // Time can change ownership even without a saved-data edit.
                            reconcileState()
                        }
                        try await retire(observed: observed)
                    }
                    if jobs.isEmpty { break }
                }
                try Task.checkCancellation()
                guard canRun else { throw CancellationError() }
                observed = await Task.detached { Self.observe() }.value
                try await withLease {
                    reconcileState()
                    guard let blocks = BlockResolution.loadBlocks(), let groups = BlockResolution.loadGroups() else { return }
                    registeredUsageIDs = Set(
                        blocks.filter {
                            $0.type == .timer
                                && SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: $0.id))
                                    == nil
                                && observed.contains(UsageMonitoring.usageActivityName(for: $0.id).rawValue)
                                && MonitorRegistration.load("usage.\($0.id.uuidString)", legacyName: UsageMonitoring.legacyUsageName($0.id),
                                    context: UsageMonitoring.registrationContext(for: $0, groups: groups) ?? "")?.confirmed?.context
                                    == UsageMonitoring.registrationContext(for: $0, groups: groups)
                        }.map(\.id))
                }
                hasChecked = true
                SchedulingManager.shared.publishRecovery(errors: errors)
                UsageLimitManager.shared.refresh()
                AdHocManager.shared.publishPersistedState()
                BreakManager.shared.publishPersistedState()
            } catch { /* Resignation/expiration: reconcile pending work on activation. */ }
        }
    }

    /// Never block MainActor acquiring a lease held by another process's IPC.
    private func withLease<T>(_ body: () -> T) async throws -> T {
        while canRun && !Task.isCancelled {
            let endWork = beginBackgroundWork()
            if let lease = EnforcementTransaction.begin(wait: false) {
                let result = body()
                let effects = lease.finish(deferEffects: true)
                await Task.detached { for effect in effects { effect() } }.value
                endWork()
                try Task.checkCancellation()
                guard canRun else { throw CancellationError() }
                return result
            }
            endWork()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CancellationError()
    }
    nonisolated private static func observe() -> Set<String> {
        precondition(!Thread.isMainThread)
        return Set(DeviceActivityCenter().activities.map(\.rawValue))
    }
    nonisolated private static func stop(_ name: String) {
        precondition(!Thread.isMainThread)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(rawValue: name)])
    }
    private static func blockID(_ namespace: String) -> UUID? {
        namespace.split(separator: ".").dropFirst().first.flatMap { UUID(uuidString: String($0)) }
    }

    private func context(_ namespace: String) -> String? {
        guard let id = Self.blockID(namespace) else { return nil }
        let defaults = SharedDefaults.suite
        if namespace.hasPrefix("adhoc.") {
            guard let session = AdHocMonitoring.session, session.id == id, session.endsAt > Date() else { return nil }
            return AdHocMonitoring.registrationContext(session)
        }
        guard let block = BlockResolution.loadBlock(id: id) else { return nil }
        if namespace.hasPrefix("block.") {
            guard block.type == .schedule, let schedule = block.schedule else { return nil }
            return ScheduleEnforcement.registrationContext(schedule)
        }
        if namespace.hasPrefix("usage.") {
            guard defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) == nil else { return nil }
            guard let groups = BlockResolution.loadGroups() else { return nil }
            return UsageMonitoring.registrationContext(for: block, groups: groups)
        }
        if namespace.hasPrefix("lock."),
            let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date, end > Date()
        {
            return UsageMonitoring.lockContext(blockID: id, end: end)
        }
        if namespace.hasPrefix("break."), let end = BreakMonitoring.breakEnd(blockID: id) ?? BreakMonitoring.pendingEnd(blockID: id), end > Date() {
            return BreakMonitoring.registrationContext(blockID: id, end: end)
        }
        return nil
    }

    /// Persist state and shield intent only. BlockingActuator defers every native
    /// shield call until the OUTERMOST lease is released, including nested helpers.
    @discardableResult
    private func reconcileState() -> Bool {
        let changed = reconcileDeadlines()
        let defaults = SharedDefaults.suite
        let now = Date()
        // Persisted intent (including emergency/expiry clears) remains retryable
        // even when unrelated configuration cannot be decoded.
        defer { BlockingActuator.replayPending() }
        if let session = AdHocMonitoring.session, session.registered != false {
            BlockingActuator.apply(tokens: session.tokens, blockID: session.id)
        }
        guard let blocks = BlockResolution.loadBlocks() else { return changed }
        for block in blocks {
            if block.type == .schedule { ScheduleEnforcement.reconcile(block: block, now: now, stopMonitoring: false) }
            if block.type != .schedule {
                let locked = block.type == .timer &&
                    (defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date).map { $0 > now } == true
                if locked { defaults.set(block.isEnabled, forKey: "usageLockManual.\(block.id)") }
                if (block.isEnabled || locked) && !BreakMonitoring.isOnBreak(blockID: block.id) {
                    if let tokens = BlockResolution.tokens(forBlockID: block.id) {
                        BlockingActuator.apply(tokens: tokens, blockID: block.id)
                    }
                } else {
                    BlockingActuator.clearShields(blockID: block.id)
                }
            }
        }
        return changed
    }

    private func reconcileDeadlines() -> Bool {
        let defaults = SharedDefaults.suite
        let now = Date()
        var changed = false
        for id in BlockingActuator.persistedOwnerIDs {
            if let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date, end <= now {
                UsageMonitoring.releaseExpiredLock(blockID: id, now: now, stopMonitoring: false)
                changed = true
            }
        }
        for block in BlockResolution.loadBlocks() ?? [] {
            if let end = BreakMonitoring.pendingEnd(blockID: block.id), end <= now {
                BreakMonitoring.endBreak(blockID: block.id, reapply: true, stopMonitoring: false)
                changed = true
            }
            if let end = BreakMonitoring.breakEnd(blockID: block.id), end <= now {
                BreakMonitoring.endBreak(blockID: block.id, reapply: true, stopMonitoring: false)
                changed = true
            }
        }
        if let session = AdHocMonitoring.session, session.endsAt <= now {
            AdHocMonitoring.finish(id: session.id, stopMonitoring: false)
            changed = true
        }
        return changed
    }

    private func completeRegistration(_ ticket: MonitorReservation, succeeded: Bool) -> MonitorLedger.Completion {
        if ticket.namespace.hasPrefix("usage.") {
            return UsageMonitoring.finishRegistration(ticket, context: context(ticket.namespace), succeeded: succeeded)
        }
        if ticket.namespace.hasPrefix("adhoc.") {
            return AdHocMonitoring.finishRegistration(ticket, succeeded: succeeded)
        }
        if ticket.namespace.hasPrefix("break."), let id = Self.blockID(ticket.namespace),
           let end = BreakMonitoring.breakEnd(blockID: id) ?? BreakMonitoring.pendingEnd(blockID: id) {
            return BreakMonitoring.finishRegistration(ticket, blockID: id, end: end, succeeded: succeeded)
        }
        return MonitorRegistration.finish(ticket, context: context(ticket.namespace), succeeded: succeeded)
    }

    private func makePlan(observed: Set<String>, attempted: inout Set<String>) -> [RecoveryJob] {
        var jobs: [RecoveryJob] = []
        let defaults = SharedDefaults.suite
        func plan(
            _ namespace: String, legacy: String, schedule: DeviceActivitySchedule,
            events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:],
            fallback: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        ) {
            guard let semantic = context(namespace),
                let ledger = MonitorRegistration.load(namespace, legacyName: legacy, context: semantic)
            else { return }
            if let pending = ledger.pending, pending.context == semantic, observed.contains(pending.name) {
                let ticket = MonitorReservation(namespace: namespace, owner: pending)
                _ = completeRegistration(ticket, succeeded: true)
                return
            }
            if !commands.isEmpty, ledger.pending != nil,
               namespace.hasPrefix("break.") || namespace.hasPrefix("adhoc.") { return }
            let legacySegmentsPresent =
                namespace.hasPrefix("block.") && ledger.confirmed?.name == namespace
                && observed.contains(namespace + ".early") && observed.contains(namespace + ".late")
            if let confirmed = ledger.confirmed, confirmed.context == semantic,
                observed.contains(confirmed.name) || legacySegmentsPresent
            {
                _ = completeRegistration(MonitorReservation(namespace: namespace, owner: confirmed), succeeded: true)
                if let id = Self.blockID(namespace) {
                    if namespace.hasPrefix("usage.") {
                        defaults.removeObject(forKey: SharedDefaults.Keys.usageError(blockID: id))
                    }
                    if namespace.hasPrefix("lock.") || namespace.hasPrefix("adhoc.") {
                        defaults.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: id))
                    }
                }
                return
            }
            guard attempted.insert(namespace + "|" + semantic).inserted,
                let ticket = MonitorRegistration.reserve(namespace, legacyName: legacy, context: semantic)
            else { return }
            jobs.append(RecoveryJob(ticket: ticket, schedule: schedule, events: events, fallback: fallback))
        }
        guard let blocks = BlockResolution.loadBlocks(), let groups = BlockResolution.loadGroups() else { return jobs }
        for block in blocks {
            if block.type == .schedule, let schedule = block.schedule {
                plan(
                    "block.\(block.id.uuidString)", legacy: "block.\(block.id.uuidString)",
                    schedule: schedule.deviceActivitySchedule())
            }
            if block.type == .timer {
                if let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date {
                    plan(
                        "lock.\(block.id.uuidString)", legacy: "lock.\(block.id.uuidString)",
                        schedule: deadlineSchedule(end))
                } else if let event = UsageMonitoring.usageEvent(for: block, groups: groups) {
                    plan(
                        "usage.\(block.id.uuidString)", legacy: UsageMonitoring.legacyUsageName(block.id),
                        schedule: UsageMonitoring.allDaySchedule,
                        events: UsageMonitoring.progressEvents(for: block, limitEvent: event),
                        fallback: [UsageMonitoring.usageEventName: event])
                } else {
                    MonitorRegistration.invalidate(
                        "usage.\(block.id.uuidString)", legacyName: UsageMonitoring.legacyUsageName(block.id))
                    defaults.set(
                        "No measurable apps selected. Open Lists and select apps, categories or websites in the Screen Time picker. Typed website addresses alone cannot measure usage.",
                        forKey: SharedDefaults.Keys.usageError(blockID: block.id))
                }
            }
            if let end = BreakMonitoring.breakEnd(blockID: block.id) ?? BreakMonitoring.pendingEnd(blockID: block.id) {
                plan(
                    "break.\(block.id.uuidString)", legacy: "break.\(block.id.uuidString)",
                    schedule: deadlineSchedule(end))
            }
        }
        if let session = AdHocMonitoring.session {
            plan(
                "adhoc.\(session.id.uuidString)", legacy: "adhoc.\(session.id.uuidString)",
                schedule: deadlineSchedule(session.endsAt))
        }
        return jobs
    }

    private func deadlineSchedule(_ end: Date) -> DeviceActivitySchedule {
        let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let monitorEnd = max(end, start.addingTimeInterval(900))
        let warning = Int(ceil(monitorEnd.timeIntervalSince(end)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: monitorEnd),
            repeats: false,
            warningTime: warning > 0 ? DateComponents(second: warning) : nil)
    }

    private func publishFailure(_ ticket: MonitorReservation, detail: String?, errors: inout [UUID: String]) {
        guard let id = Self.blockID(ticket.namespace) else { return }
        if ticket.namespace.hasPrefix("block.") { errors[id] = "Couldn’t start this schedule. \(detail ?? "")" }
        if ticket.namespace.hasPrefix("usage.") {
            SharedDefaults.suite.set(
                "Usage tracking couldn't start. Allow Screen Time access and retry.",
                forKey: SharedDefaults.Keys.usageError(blockID: id))
        }
        if ticket.namespace.hasPrefix("lock.") || ticket.namespace.hasPrefix("adhoc.") {
            SharedDefaults.suite.set(
                "Automatic end could not be restored. Open Tyri at the end of this session.",
                forKey: SharedDefaults.Keys.usageLockError(blockID: id))
        }
        if ticket.namespace.hasPrefix("break.") {
            BreakMonitoring.endBreak(blockID: id, reapply: true, stopMonitoring: false)
            BreakManager.shared.lastError =
                "Your break ended because its automatic re-lock could not be restored. Blocking is back on."
        }
    }

    private func retire(observed: Set<String>) async throws {
        let names = try await withLease {
            guard BlockResolution.loadBlocks() != nil, BlockResolution.loadGroups() != nil else { return Set<String>() }
            for key in SharedDefaults.suite.dictionaryRepresentation().keys
            where key.hasPrefix(MonitorRegistration.prefix) {
                let namespace = String(key.dropFirst(MonitorRegistration.prefix.count))
                if context(namespace) == nil { MonitorRegistration.invalidate(namespace, legacyName: namespace) }
            }
            for name in observed {
                let parts = name.split(separator: ".")
                guard parts.count >= 2, ["block", "usage", "lock", "break", "adhoc"].contains(String(parts[0])),
                    let id = UUID(uuidString: String(parts[1])), BlockResolution.loadBlock(id: id) == nil,
                    AdHocMonitoring.session?.id != id
                else { continue }
                let namespace = parts.prefix(2).joined(separator: ".")
                MonitorRegistration.invalidate(namespace, legacyName: name)
            }
            var names = MonitorRegistration.retirementNames(observed: observed)
            names.formUnion(legacyRetirements)
            // A migrated app can rediscover old preset monitors after a crash.
            for name in observed where name.hasPrefix("preset.") {
                if Self.blockID(name) != nil { names.insert(name) }
            }
            return names
        }
        for name in names {
            try Task.checkCancellation()
            guard canRun else { throw CancellationError() }
            await Task.detached { Self.stop(name) }.value
        }
        try await withLease { MonitorRegistration.acknowledgeRetired(names) }
        legacyRetirements.subtract(names)
    }
}
