//
//  VacationMode.swift
//  Tyri
//
//  A temporary pause of selected blocks' AUTOMATIC activation until a fixed
//  instant. Decisions (TSK-174):
//    - The resume time is one absolute instant, recorded with the time zone it
//      was chosen in; travelling does not move it.
//    - Vacation never lifts a shield that is already up. A schedule window that
//      began before the block was paused runs to its end; an existing usage
//      lockout runs to its deadline.
//    - Only automatic activation is suppressed: schedule windows and usage-limit
//      lockouts. Block now and NFC tag toggles still enforce normally.
//    - Ending early only adds protection, so it is immediate.
//
//  The pause is time-based: every reconcile path compares against `resumeAt`, so
//  a pause expires even if no callback arrives. The one-shot "vacation.<id>"
//  monitor (registered by ForegroundRecovery) re-shields a window that is in
//  progress at the resume time and gives suppressed usage limits a fresh allowance.
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation

struct VacationPlan: Codable, Equatable {
    /// Changes whenever the plan is replaced, so each version owns a new monitor.
    let id: UUID
    /// Block ID → when that block's pause began. A window that started before
    /// this instant is an existing activation and is not suppressed.
    var pausedSince: [UUID: Date]
    var resumeAt: Date
    /// Time zone the resume time was chosen in (display only; `resumeAt` is absolute).
    var timeZoneID: String

    var blockIDs: Set<UUID> { Set(pausedSince.keys) }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

enum VacationMode {
    static let planKey = "vacation.v1"
    static let errorKey = "vacationError.v1"
    static let namespacePrefix = "vacation."
    static func suppressedLimitKey(_ blockID: UUID) -> String { "vacationSuppressedLimit.\(blockID.uuidString)" }

    static var plan: VacationPlan? {
        guard let data = SharedDefaults.suite.data(forKey: planKey) else { return nil }
        return try? JSONDecoder().decode(VacationPlan.self, from: data)
    }

    static func namespace(_ plan: VacationPlan) -> String { namespacePrefix + plan.id.uuidString }

    static func registrationContext(_ plan: VacationPlan) -> String {
        String(plan.resumeAt.timeIntervalSince1970.bitPattern, radix: 16) + "|" + plan.id.uuidString
    }

    /// The plan whose resume monitor should exist now, if any.
    static func pendingPlan(now: Date = Date()) -> VacationPlan? {
        plan.flatMap { $0.resumeAt > now ? $0 : nil }
    }

    /// Is this block's automatic activation paused at `now`?
    static func pauses(_ blockID: UUID, at now: Date = Date()) -> Bool {
        guard let plan = pendingPlan(now: now) else { return false }
        return plan.pausedSince[blockID] != nil
    }

    /// Should the schedule window that began at `windowStart` stay off?
    /// Windows that began before the pause are existing activations and continue.
    static func suppresses(_ blockID: UUID, windowStart: Date, at now: Date = Date()) -> Bool {
        guard let plan = pendingPlan(now: now), let since = plan.pausedSince[blockID] else { return false }
        return windowStart >= since
    }

    /// Start or replace the vacation. Blocks already paused keep their original
    /// pause start, so changing the plan cannot revive a suppressed window.
    /// Returns nil when the request is invalid or the lease is unavailable.
    @discardableResult
    static func start(blockIDs: Set<UUID>, resumeAt requested: Date, timeZone: TimeZone = .current,
                      now: Date = Date()) -> VacationPlan? {
        guard let transition = EnforcementTransaction.begin() else { return nil }
        defer { transition.finish() }

        // DeviceActivity uses whole seconds; a minute picker never needs more.
        let resumeAt = Date(timeIntervalSince1970: floor(requested.timeIntervalSince1970 / 60) * 60)
        guard !blockIDs.isEmpty, resumeAt > now else { return nil }
        let previous = pendingPlan(now: now)
        var since: [UUID: Date] = [:]
        for id in blockIDs { since[id] = previous?.pausedSince[id] ?? now }
        let next = VacationPlan(id: UUID(), pausedSince: since, resumeAt: resumeAt, timeZoneID: timeZone.identifier)
        save(next)
        SharedDefaults.suite.removeObject(forKey: errorKey)
        if let previous {
            MonitorRegistration.invalidate(namespace(previous), legacyName: nil)
            // Blocks removed from the plan resume now; re-adding later is a fresh pause.
            let dropped = previous.blockIDs.subtracting(blockIDs)
            if !dropped.isEmpty { resume(dropped, inlineRearm: false) }
        }
        return next
    }

    /// End the vacation now (ending early only adds protection).
    /// `inlineRearm` (extension) performs native monitor changes directly. The
    /// app path only persists state: the old allowance is invalidated for
    /// ForegroundRecovery to replace, and obsolete monitors are retired there.
    static func end(inlineRearm: Bool = false) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let current = plan else { return }
        save(nil)
        MonitorRegistration.invalidate(namespace(current), legacyName: nil)
        SharedDefaults.suite.removeObject(forKey: errorKey)
        resume(current.blockIDs, inlineRearm: inlineRearm)
    }

    /// Callbacks and foreground recovery consult the deadline, never callback order.
    @discardableResult
    static func reconcile(now: Date = Date(), inlineRearm: Bool = false) -> Bool {
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { transition.finish() }

        guard let current = plan, current.resumeAt <= now else { return false }
        end(inlineRearm: inlineRearm)
        return true
    }

    /// A usage limit was reached while paused: don't lock, but remember to give
    /// the block a fresh allowance at resume (iOS won't report this threshold again today).
    static func recordSuppressedLimit(blockID: UUID) {
        SharedDefaults.suite.set(true, forKey: suppressedLimitKey(blockID))
    }

    private static func resume(_ ids: Set<UUID>, inlineRearm: Bool) {
        for id in ids {
            guard let block = BlockResolution.loadBlock(id: id) else {
                SharedDefaults.suite.removeObject(forKey: suppressedLimitKey(id))
                continue
            }
            if block.type == .schedule {
                // App-side recovery leaves native teardown to its retirement pass.
                ScheduleEnforcement.reconcile(block: block, stopMonitoring: inlineRearm)
            } else if block.type == .timer, SharedDefaults.suite.bool(forKey: suppressedLimitKey(id)) {
                SharedDefaults.suite.removeObject(forKey: suppressedLimitKey(id))
                if inlineRearm {
                    UsageMonitoring.startUsageMonitor(forBlockID: id)
                } else {
                    // Retire the consumed allowance; foreground recovery registers a new one.
                    MonitorRegistration.invalidate("usage.\(id.uuidString)", legacyName: UsageMonitoring.legacyUsageName(id))
                }
            }
        }
    }

    private static func save(_ plan: VacationPlan?) {
        if let plan, let data = try? JSONEncoder().encode(plan) {
            SharedDefaults.suite.set(data, forKey: planKey)
        } else {
            SharedDefaults.suite.removeObject(forKey: planKey)
        }
    }
}
