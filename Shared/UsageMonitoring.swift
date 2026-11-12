//
//  UsageMonitoring.swift
//  Tyri
//
//  Shared DeviceActivity registration for the usage-timer mechanic. Used by:
//    - UsageLimitManager (app side: registers monitors, observable state)
//    - TyriMonitorExtension (re-arms the budget when a lockout ends)
//
//  Keeping registration here — rather than duplicated in app + extension —
//  mirrors `BlockingActuator`, so both sides build identical monitors.
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
import DeviceActivity
import FamilyControls
import OSLog

enum UsageMonitoring {
    private static let log = Logger(subsystem: "name.amitsankaran.Block", category: "UsageCycle")

    // MARK: - Names

    /// All-day counting window carrying the cumulative-usage threshold event.
    static func usageActivityName(for blockID: UUID) -> DeviceActivityName {
        DeviceActivityName(rawValue: MonitorRegistration.current("usage.\(blockID.uuidString)", legacyName: legacyUsageName(blockID)))
    }

    static func legacyUsageName(_ id: UUID) -> String {
        "usage.\(id.uuidString)" + (SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: id)).map { "." + $0 } ?? "")
    }

    static func registrationContext(for block: BlockRule, groups: [AppGroup]) -> String? {
        guard usageEvent(for: block, groups: groups) != nil else { return nil }
        let tokens = BlockResolution.tokens(for: block, groups: groups)
        return "\(block.usageLimitMinutes ?? 0)|" + tokenIdentity(tokens.apps) + "|" + tokenIdentity(tokens.categories) + "|" + tokenIdentity(tokens.webDomains)
    }

    private static func tokenIdentity<T: Encodable & Hashable>(_ tokens: Set<T>) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return tokens.compactMap { try? encoder.encode($0).base64EncodedString() }.sorted().joined(separator: ",")
    }

    @discardableResult
    static func finishRegistration(_ ticket: MonitorReservation, context: String?, succeeded: Bool) -> MonitorLedger.Completion {
        let result = MonitorRegistration.finish(ticket, context: context, succeeded: succeeded)
        if result == .promoted, let id = UUID(uuidString: String(ticket.namespace.dropFirst("usage.".count))) {
            publishGeneration(ticket.name, blockID: id)
        }
        return result
    }

    private static func publishGeneration(_ name: String, blockID: UUID) {
        SharedDefaults.suite.set(String(name.dropFirst("usage.\(blockID.uuidString).".count)), forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID))
        SharedDefaults.suite.removeObject(forKey: UsageProgress.key(blockID))
    }

    static func acceptRegistration(_ name: String, for block: BlockRule, groups: [AppGroup]) -> Bool {
        let namespace = "usage.\(block.id.uuidString)"
        let result = MonitorRegistration.accept(name, namespace: namespace, legacyName: legacyUsageName(block.id), context: registrationContext(for: block, groups: groups))
        if result == .promoted { publishGeneration(name, blockID: block.id) }
        return result == .promoted || result == .alreadyAccepted
    }

    /// One-shot lockout window registered once the threshold is reached.
    static func lockActivityName(for blockID: UUID) -> DeviceActivityName {
        let base = "lock.\(blockID.uuidString)"
        return DeviceActivityName(rawValue: MonitorRegistration.current(base, legacyName: base))
    }

    static let usageEventName = DeviceActivityEvent.Name(rawValue: "limit")

    // MARK: - Schedules / events

    /// Repeating all-day window; iOS resets the threshold counter at the interval
    /// boundary (≈midnight), giving the daily reset for free.
    static var allDaySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    /// The threshold event for a timer block, or nil if the limit is off / the
    /// resolved group selection is empty.
    static func usageEvent(for block: BlockRule, groups: [AppGroup]) -> DeviceActivityEvent? {
        guard block.type == .timer, let limit = block.usageLimitMinutes, limit > 0 else { return nil }
        let tokens = BlockResolution.tokens(for: block, groups: groups)
        guard !tokens.isEmpty else { return nil }
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(applications: tokens.apps, categories: tokens.categories,
                                       webDomains: tokens.webDomains, threshold: DateComponents(minute: limit),
                                       includesPastActivity: false)
        }
        return DeviceActivityEvent(
            applications: tokens.apps,
            categories: tokens.categories,
            webDomains: tokens.webDomains,
            threshold: DateComponents(minute: limit)
        )
    }

    static func progressEvents(for block: BlockRule, limitEvent: DeviceActivityEvent) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events = [usageEventName: limitEvent]
        for minute in UsageProgress.milestones(for: block.usageLimitMinutes ?? 0) {
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(applications: limitEvent.applications, categories: limitEvent.categories,
                                            webDomains: limitEvent.webDomains, threshold: DateComponents(minute: minute),
                                            includesPastActivity: false)
            } else {
                event = DeviceActivityEvent(applications: limitEvent.applications, categories: limitEvent.categories,
                                            webDomains: limitEvent.webDomains, threshold: DateComponents(minute: minute))
            }
            events[DeviceActivityEvent.Name("progress.\(minute)")] = event
        }
        return events
    }

    // MARK: - Register / tear down

    /// Start the all-day usage threshold monitor for a timer block. Returns false
    /// when there's nothing to monitor or registration fails.
    @discardableResult
    static func startUsageMonitor(for block: BlockRule, groups: [AppGroup]) -> Bool {
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { transition.finish() }

        guard SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) == nil,
              let event = usageEvent(for: block, groups: groups) else { return false }
        guard let context = registrationContext(for: block, groups: groups) else { return false }
        let previous = MonitorRegistration.load("usage.\(block.id.uuidString)", legacyName: legacyUsageName(block.id), context: context)
        let oldNames = [previous?.confirmed?.name, previous?.pending?.name].compactMap { $0 }
        guard let ticket = MonitorRegistration.reserve("usage.\(block.id.uuidString)", legacyName: legacyUsageName(block.id), context: context) else { return false }
        let result = MonitorResult()
        EnforcementTransaction.afterUnlock(key: ticket.name) {
            guard EnforcementTransaction.effectsAreEnabled else { return }
            let center = DeviceActivityCenter()
            let oldActivities = oldNames.map { DeviceActivityName(rawValue: $0) }
            // Each allowance gets a new identity: a delivered threshold from an old
            // allowance cannot consume the next one, and iOS gets a fresh event counter.
            let activity = DeviceActivityName(rawValue: ticket.name)
            // A replacement needs a slot too. At the activity ceiling, retaining the
            // old generation makes every retry fail forever. This call intentionally
            // starts a fresh allowance; retire the old one only when space is needed.
            if center.activities.count >= 20 && !oldActivities.isEmpty {
                center.stopMonitoring(oldActivities)
            }
            do {
                var reportsProgress = true
                do {
                    try center.startMonitoring(activity, during: allDaySchedule, events: progressEvents(for: block, limitEvent: event))
                } catch {
                    guard EnforcementTransaction.effectsAreEnabled else { throw error }
                    // Progress is optional: never lose enforcement because extra
                    // reporting events could not be registered on this device.
                    try center.startMonitoring(activity, during: allDaySchedule, events: [usageEventName: event])
                    reportsProgress = false
                }
                guard let commit = EnforcementTransaction.beginEffect() else { return }
                let accepted = finishRegistration(ticket, context: currentUsageContext(blockID: block.id), succeeded: true)
                guard accepted == .promoted || accepted == .alreadyAccepted else { commit.finish(); center.stopMonitoring([activity]); return }
                if !reportsProgress && accepted == .promoted { SharedDefaults.suite.removeObject(forKey: UsageProgress.key(block.id)) }
                EnforcementDiagnostics.record("registration", blockID: block.id, detail: "Registered allowance; progress events: \(reportsProgress)")
                log.notice("Registered allowance \(activity.rawValue, privacy: .public)")
                SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageError(blockID: block.id))
                result.succeeded = true
                commit.finish()
                center.stopMonitoring(oldActivities)
            } catch {
                guard let commit = EnforcementTransaction.beginEffect() else { return }
                defer { commit.finish() }
                let completion = finishRegistration(ticket, context: currentUsageContext(blockID: block.id), succeeded: false)
                guard completion == .failed else { return }
                SharedDefaults.suite.set("Usage tracking couldn't start. Allow Screen Time access and retry.",
                                         forKey: SharedDefaults.Keys.usageError(blockID: block.id))
                EnforcementDiagnostics.record("registration", blockID: block.id, detail: "FAILED: \(error.localizedDescription)")
                log.error("Allowance registration failed: \(error.localizedDescription, privacy: .public)")
                print("❌ startUsageMonitor failed for \(block.id): \(error)")
                result.error = error
            }
        }
        transition.finish()
        return result.succeeded
    }

    private static func currentUsageContext(blockID: UUID) -> String? {
        guard SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) == nil,
              let block = BlockResolution.loadBlock(id: blockID),
              let groups = BlockResolution.loadGroups() else { return nil }
        return registrationContext(for: block, groups: groups)
    }

    /// Convenience used by the extension, which loads from the shared store.
    @discardableResult
    static func startUsageMonitor(forBlockID id: UUID) -> Bool {
        guard let block = BlockResolution.loadBlock(id: id), let groups = BlockResolution.loadGroups() else { return false }
        return startUsageMonitor(for: block, groups: groups)
    }

    static func stopUsageMonitor(for blockID: UUID) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        MonitorRegistration.invalidate("usage.\(blockID.uuidString)", legacyName: legacyUsageName(blockID))
        EnforcementTransaction.afterUnlock(key: "stopUsage.\(blockID.uuidString)") {
            let center = DeviceActivityCenter()
            let observed = Set(center.activities.map(\.rawValue))
            guard let lease = EnforcementTransaction.beginEffect() else { return }
            let retired = MonitorRegistration.retirementNames(observed: observed)
                .filter { $0 == "usage.\(blockID.uuidString)" || $0.hasPrefix("usage.\(blockID.uuidString).") }
            lease.finish()
            center.stopMonitoring(retired.map { DeviceActivityName(rawValue: $0) })
        }
    }

    /// True if the all-day usage monitor is currently registered for this block.
    static func isUsageMonitorActive(for blockID: UUID) -> Bool {
        DeviceActivityCenter().activities.contains(usageActivityName(for: blockID))
    }

    /// Register a one-shot lockout window from now until now + `minutes`, and
    /// persist the end-time. The extension's `intervalDidEnd` for this activity
    /// clears the shield and re-arms the budget; `reconcileExpiredLocks` is the
    /// backstop if the one-shot window doesn't fire (e.g. very short lockouts).
    static func startLockout(blockID: UUID, minutes: Int) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        guard let block = BlockResolution.loadBlock(id: blockID), block.type == .timer,
              BlockResolution.loadGroups() != nil else { return }
        let key = SharedDefaults.Keys.usageLockEnd(blockID: blockID)
        // Repeated thresholds must not replace the live monitor or its deadline.
        if let end = SharedDefaults.suite.object(forKey: key) as? Date, end > now {
            reconcileLockout(blockID: blockID, now: now)
            return
        }
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        SharedDefaults.suite.set(end, forKey: key)
        SharedDefaults.suite.set(block.isEnabled, forKey: "usageLockManual.\(blockID)")
        log.notice("Lock started \(blockID.uuidString, privacy: .public), expires \(end.timeIntervalSince1970)")
        BlockingActuator.start(blockID: blockID, bypassWeekday: true, setRunningFlag: false)

        // The consumed allowance no longer needs an activity slot. Release it
        // after shielding, before registering expiry (iOS allows 20 activities).
        stopUsageMonitor(for: blockID)
        registerLockout(blockID: blockID, end: end, now: now)
    }

    private static func registerLockout(blockID: UUID, end: Date, now: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // DeviceActivity requires a minimum 15-minute interval. Short lockouts
        // use the warning callback at their real deadline, with end as a backstop.
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        let monitorEnd = max(end, start.addingTimeInterval(900))
        let warning = monitorEnd.timeIntervalSince(end)
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: monitorEnd),
            repeats: false, warningTime: warning > 0 ? DateComponents(second: Int(ceil(warning))) : nil
        )
        let base = "lock.\(blockID.uuidString)"
        guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: lockContext(blockID: blockID, end: end)) else { return }
        EnforcementTransaction.afterUnlock(key: ticket.name) {
            guard EnforcementTransaction.effectsAreEnabled else { return }
            let outcome = MonitorResult()
            do {
                try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: ticket.name), during: schedule)
                outcome.succeeded = true
            } catch { outcome.error = error }
            guard let lease = EnforcementTransaction.beginEffect() else { return }
            defer { lease.finish() }
            let currentEnd = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date
            let current = currentEnd.flatMap { value in
                BlockResolution.loadBlock(id: blockID)?.type == .timer ? lockContext(blockID: blockID, end: value) : nil
            }
            let result = MonitorRegistration.finish(ticket, context: current, succeeded: outcome.succeeded)
            if result == .promoted || result == .alreadyAccepted {
                SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
            } else if result == .failed {
                SharedDefaults.suite.set("Blocking is on, but its automatic end couldn't be registered. Open Tyri to retry.",
                                         forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
            }
            if result == .obsolete {
                EnforcementTransaction.afterUnlock(key: "stop." + ticket.name) {
                    DeviceActivityCenter().stopMonitoring([DeviceActivityName(rawValue: ticket.name)])
                }
            }
        }
    }

    /// Both callbacks and foreground recovery consult the deadline, never callback order.
    static func reconcileLockout(blockID: UUID, now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date else { return }
        if end <= now {
            releaseExpiredLock(blockID: blockID, now: now)
            return
        }
        guard let block = BlockResolution.loadBlock(id: blockID), block.type == .timer,
              let groups = BlockResolution.loadGroups(),
              Set(block.appGroupIDs).isSubset(of: Set(groups.map(\.id))) else { return }
        if end > now {
            let activity = lockActivityName(for: blockID)
            EnforcementTransaction.afterUnlock(key: "repairLock.\(blockID)") {
                guard !DeviceActivityCenter().activities.contains(activity),
                      let lease = EnforcementTransaction.beginEffect() else { return }
                defer { lease.finish() }
                guard SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date == end,
                      end > Date() else { return }
                registerLockout(blockID: blockID, end: end, now: Date())
            }
            BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: groups), blockID: blockID)
            return
        }
    }

    static func releaseExpiredLock(blockID: UUID, now: Date = Date(), stopMonitoring: Bool = true) {
        guard let lease = EnforcementTransaction.begin() else { return }
        defer { lease.finish() }
        guard let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date,
              end <= now else { return }
        let manualSnapshot = SharedDefaults.suite.object(forKey: "usageLockManual.\(blockID)") as? Bool
        stopLockout(for: blockID, stopMonitoring: stopMonitoring)
        let block = BlockResolution.loadBlock(id: blockID)
        let manual = block?.isEnabled ?? manualSnapshot
        if manual == false { BlockingActuator.end(blockID: blockID, stopMonitoring: stopMonitoring) }
        // Legacy locks may predate the snapshot. Unknown ownership cannot be
        // interpreted as off: preserve the intent and keep Emergency Access available.
        else if let tokens = BlockResolution.tokens(forBlockID: blockID) {
            BlockingActuator.apply(tokens: tokens, blockID: blockID)
        }
        guard stopMonitoring else { return }
        let generation = SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID))
        EnforcementTransaction.afterUnlock(key: "rearm.\(blockID)") {
            guard !isUsageMonitorActive(for: blockID), let rearm = EnforcementTransaction.beginEffect() else { return }
            defer { rearm.finish() }
            guard SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) == nil,
                  SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID)) == generation,
                  MonitorRegistration.pending("usage.\(blockID.uuidString)") == nil else { return }
            startUsageMonitor(forBlockID: blockID)
        }
    }

    /// Stop the lockout window and clear its persisted end-time.
    static func stopLockout(for blockID: UUID, stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        let activity = lockActivityName(for: blockID)
        MonitorRegistration.invalidate("lock.\(blockID.uuidString)", legacyName: "lock.\(blockID.uuidString)")
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID))
        SharedDefaults.suite.removeObject(forKey: "usageLockManual.\(blockID)")
        if stopMonitoring {
            EnforcementTransaction.afterUnlock(key: "stop." + activity.rawValue) {
                DeviceActivityCenter().stopMonitoring([activity])
            }
        }
    }

    static func lockContext(blockID: UUID, end: Date) -> String {
        String(end.timeIntervalSince1970.bitPattern, radix: 16) + "|" + (SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID)) ?? "legacy")
    }
}
