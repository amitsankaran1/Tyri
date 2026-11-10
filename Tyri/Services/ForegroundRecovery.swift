import Combine
import DeviceActivity
import FamilyControls
import Foundation

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
            do { try center.startMonitoring(name, during: schedule, events: events) } catch {
                guard !fallback.isEmpty else { throw error }
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
    private var started = false
    private var running = false
    private var legacyRetirements: Set<String> = []
    private init() {}

    func retireLegacy(_ names: [String]) { legacyRetirements.formUnion(names) }
    func start() {
        guard !started else { return }
        _ = ScreenTimeManager.shared
        started = true
        Task {
            await withLease {
                Migration.runIfNeeded()
                BlockStore.shared.reload()
                AppGroupStore.shared.reload()
            }
            request()
        }
    }

    func request() {
        guard started else { return }
        guard SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2) else { return }
        // Deadline fallback is independent of any stalled native operation.
        // This lane never waits for a lease and never performs DeviceActivity IPC.
        if let lease = EnforcementTransaction.begin(wait: false) {
            let changed = reconcileDeadlines()
            lease.finish()
            if changed {
                BreakManager.shared.publishPersistedState()
                AdHocManager.shared.publishPersistedState()
                UsageLimitManager.shared.refresh()
            }
        }
        guard !running else { return }
        guard ScreenTimeManager.shared.authorizationStatus == .approved else {
            isChecking = false
            return
        }
        BlockStore.shared.flush()
        AppGroupStore.shared.flush()
        running = true
        isChecking = true
        // Restore the existing break timer before the first native observation:
        // a persisted break still needs its deadline tick if that read stalls.
        BreakManager.shared.publishPersistedState()
        Task {
            var attempted: Set<String> = []
            var errors: [UUID: String] = [:]
            var observed: Set<String> = []
            // A second pass can rearm an allowance whose deadline crossed during
            // IPC. Failed semantic operations are not blindly retried this run.
            for _ in 0..<2 {
                observed = await Task.detached { Self.observe() }.value
                let jobs = await withLease {
                    reconcileState()
                    return makePlan(observed: observed, attempted: &attempted)
                }
                await retire(observed: observed)
                for job in jobs {
                    let valid = await withLease {
                        context(job.ticket.namespace) == job.ticket.owner.context
                            && MonitorRegistration.pending(job.ticket.namespace)?.owner == job.ticket.owner
                    }
                    guard valid else {
                        await withLease { _ = MonitorRegistration.finish(job.ticket, context: nil, succeeded: false) }
                        continue
                    }
                    let outcome = await Task.detached { job.execute() }.value
                    await withLease {
                        let currentContext = context(job.ticket.namespace)
                        let result: MonitorLedger.Completion
                        if job.ticket.namespace.hasPrefix("usage.") {
                            result = UsageMonitoring.finishRegistration(
                                job.ticket, context: currentContext, succeeded: outcome.succeeded)
                        } else {
                            result = MonitorRegistration.finish(
                                job.ticket, context: currentContext, succeeded: outcome.succeeded)
                        }
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
                    await retire(observed: observed)
                }
                if jobs.isEmpty { break }
            }
            observed = await Task.detached { Self.observe() }.value
            await withLease {
                reconcileState()
                registeredUsageIDs = Set(
                    BlockResolution.loadBlocks().filter {
                        $0.type == .timer
                            && SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: $0.id))
                                == nil
                            && observed.contains(UsageMonitoring.usageActivityName(for: $0.id).rawValue)
                    }.map(\.id))
            }
            SchedulingManager.shared.publishRecovery(errors: errors)
            UsageLimitManager.shared.refresh()
            AdHocManager.shared.publishPersistedState()
            BreakManager.shared.publishPersistedState()
            running = false
            isChecking = false
        }
    }

    /// Never block MainActor acquiring a lease held by another process's IPC.
    private func withLease<T>(_ body: () -> T) async -> T {
        while true {
            if let lease = EnforcementTransaction.begin(wait: false) {
                let result = body()
                lease.finish()
                return result
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
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
            return UsageMonitoring.registrationContext(for: block, groups: BlockResolution.loadGroups())
        }
        if namespace.hasPrefix("lock."),
            let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date, end > Date()
        {
            return UsageMonitoring.lockContext(blockID: id, end: end)
        }
        if namespace.hasPrefix("break."), let end = BreakMonitoring.breakEnd(blockID: id), end > Date() {
            return BreakMonitoring.registrationContext(blockID: id, end: end)
        }
        return nil
    }

    /// Pure state/shield helpers suppress all DeviceActivity calls in this lease.
    private func reconcileState() {
        _ = reconcileDeadlines()
        let defaults = SharedDefaults.suite
        let now = Date()
        let groups = BlockResolution.loadGroups()
        for block in BlockResolution.loadBlocks() {
            if block.type == .schedule { ScheduleEnforcement.reconcile(block: block, now: now, stopMonitoring: false) }
            if block.type == .timer,
                let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date
            {
                if end > now {
                    BlockingActuator.apply(
                        tokens: BlockResolution.tokens(for: block, groups: groups), blockID: block.id)
                }
            }
            if block.isEnabled && !BreakMonitoring.isOnBreak(blockID: block.id) {
                BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: groups), blockID: block.id)
            }
        }
        if let session = AdHocMonitoring.session {
            BlockingActuator.apply(tokens: session.tokens, blockID: session.id)
        }
    }

    private func reconcileDeadlines() -> Bool {
        let defaults = SharedDefaults.suite
        let now = Date()
        var changed = false
        for block in BlockResolution.loadBlocks() {
            if block.type == .timer,
                let end = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date,
                end <= now
            {
                UsageMonitoring.stopLockout(for: block.id, stopMonitoring: false)
                if block.isEnabled {
                    BlockingActuator.apply(
                        tokens: BlockResolution.tokens(for: block, groups: BlockResolution.loadGroups()),
                        blockID: block.id)
                } else {
                    BlockingActuator.end(blockID: block.id, stopMonitoring: false)
                }
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
                if namespace.hasPrefix("usage.") {
                    _ = UsageMonitoring.finishRegistration(ticket, context: semantic, succeeded: true)
                } else {
                    _ = MonitorRegistration.finish(ticket, context: semantic, succeeded: true)
                }
                return
            }
            let legacySegmentsPresent =
                namespace.hasPrefix("block.") && ledger.confirmed?.name == namespace
                && observed.contains(namespace + ".early") && observed.contains(namespace + ".late")
            if let confirmed = ledger.confirmed, confirmed.context == semantic,
                observed.contains(confirmed.name) || legacySegmentsPresent
            {
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
        for block in BlockResolution.loadBlocks() {
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
                } else if let event = UsageMonitoring.usageEvent(for: block, groups: BlockResolution.loadGroups()) {
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
            if let end = BreakMonitoring.breakEnd(blockID: block.id) {
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
        let calendar = Calendar.current
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: monitorEnd),
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

    private func retire(observed: Set<String>) async {
        let names = await withLease {
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
        for name in names { await Task.detached { Self.stop(name) }.value }
        await withLease { MonitorRegistration.acknowledgeRetired(names) }
        legacyRetirements.subtract(names)
    }
}
