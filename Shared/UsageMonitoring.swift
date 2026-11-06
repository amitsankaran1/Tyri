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
        DeviceActivityName(rawValue: "usage.\(blockID.uuidString)" + (SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID)).map { "." + $0 } ?? ""))
    }

    /// One-shot lockout window registered once the threshold is reached.
    static func lockActivityName(for blockID: UUID) -> DeviceActivityName {
        DeviceActivityName(rawValue: "lock.\(blockID.uuidString)")
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

    private static func progressEvents(for block: BlockRule, limitEvent: DeviceActivityEvent) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
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
        guard let event = usageEvent(for: block, groups: groups) else { return false }
        let center = DeviceActivityCenter()
        let oldActivities = center.activities.filter { $0.rawValue == "usage.\(block.id.uuidString)" || $0.rawValue.hasPrefix("usage.\(block.id.uuidString).") }
        let key = SharedDefaults.Keys.usageGeneration(blockID: block.id)
        let previous = SharedDefaults.suite.string(forKey: key)
        // Each allowance gets a new identity: a delivered threshold from an old
        // allowance cannot consume the next one, and iOS gets a fresh event counter.
        SharedDefaults.suite.set(UUID().uuidString, forKey: key)
        let activity = usageActivityName(for: block.id)
        do {
            var reportsProgress = true
            do {
                try center.startMonitoring(activity, during: allDaySchedule, events: progressEvents(for: block, limitEvent: event))
            } catch {
                // Progress is optional: never lose enforcement because extra
                // reporting events could not be registered on this device.
                try center.startMonitoring(activity, during: allDaySchedule, events: [usageEventName: event])
                reportsProgress = false
            }
            if reportsProgress { UsageProgress.record(0, blockID: block.id, reset: true) }
            else { SharedDefaults.suite.removeObject(forKey: UsageProgress.key(block.id)) }
            center.stopMonitoring(oldActivities)
            EnforcementDiagnostics.record("registration", blockID: block.id, detail: "Registered allowance; progress events: \(reportsProgress)")
            log.notice("Registered allowance \(activity.rawValue, privacy: .public)")
            SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageError(blockID: block.id))
            return true
        } catch {
            if let previous { SharedDefaults.suite.set(previous, forKey: key) }
            else { SharedDefaults.suite.removeObject(forKey: key) }
            SharedDefaults.suite.set("Usage tracking couldn't start. Allow Screen Time access and retry.",
                                     forKey: SharedDefaults.Keys.usageError(blockID: block.id))
            EnforcementDiagnostics.record("registration", blockID: block.id, detail: "FAILED: \(error.localizedDescription)")
            log.error("Allowance registration failed: \(error.localizedDescription, privacy: .public)")
            print("❌ startUsageMonitor failed for \(block.id): \(error)")
            return false
        }
    }

    /// Convenience used by the extension, which loads from the shared store.
    @discardableResult
    static func startUsageMonitor(forBlockID id: UUID) -> Bool {
        guard let block = BlockResolution.loadBlock(id: id) else { return false }
        return startUsageMonitor(for: block, groups: BlockResolution.loadGroups())
    }

    static func stopUsageMonitor(for blockID: UUID) {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter {
            $0.rawValue == "usage.\(blockID.uuidString)" || $0.rawValue.hasPrefix("usage.\(blockID.uuidString).")
        })
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
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        guard let block = BlockResolution.loadBlock(id: blockID), block.type == .timer else { return }
        let key = SharedDefaults.Keys.usageLockEnd(blockID: blockID)
        // Repeated thresholds must not replace the live monitor or its deadline.
        if let end = SharedDefaults.suite.object(forKey: key) as? Date, end > now {
            reconcileLockout(blockID: blockID, now: now)
            return
        }
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        SharedDefaults.suite.set(end, forKey: key)
        log.notice("Lock started \(blockID.uuidString, privacy: .public), expires \(end.timeIntervalSince1970)")
        BlockingActuator.start(blockID: blockID, bypassWeekday: true, setRunningFlag: false)

        // The consumed allowance no longer needs an activity slot. Release it
        // after shielding, before registering expiry (iOS allows 20 activities).
        stopUsageMonitor(for: blockID)
        registerLockout(blockID: blockID, end: end, now: now)
    }

    private static func registerLockout(blockID: UUID, end: Date, now: Date) {
        let cal = Calendar.current
        // DeviceActivity requires a minimum 15-minute interval. Short lockouts
        // use the warning callback at their real deadline, with end as a backstop.
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        let monitorEnd = max(end, start.addingTimeInterval(900))
        let warning = monitorEnd.timeIntervalSince(end)
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: monitorEnd),
            repeats: false, warningTime: warning > 0 ? DateComponents(second: Int(ceil(warning))) : nil
        )
        do {
            try DeviceActivityCenter().startMonitoring(lockActivityName(for: blockID), during: schedule)
            SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
        } catch {
            SharedDefaults.suite.set("Blocking is on, but its automatic end couldn't be registered. Open Tyri to retry.",
                                     forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
            print("❌ startLockout failed for \(blockID): \(error)")
        }
    }

    /// Both callbacks and foreground recovery consult the deadline, never callback order.
    static func reconcileLockout(blockID: UUID, now: Date = Date()) {
        guard let block = BlockResolution.loadBlock(id: blockID), block.type == .timer,
              let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date else { return }
        if end > now {
            if !DeviceActivityCenter().activities.contains(lockActivityName(for: blockID)) {
                registerLockout(blockID: blockID, end: end, now: now)
            }
            BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: BlockResolution.loadGroups()), blockID: blockID)
            return
        }
        // Invalidate persisted state before stopping: stop can itself deliver an end callback.
        log.notice("Lock expired \(blockID.uuidString, privacy: .public), rearming allowance")
        stopLockout(for: blockID)
        if block.isEnabled {
            BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: BlockResolution.loadGroups()), blockID: blockID)
        } else {
            BlockingActuator.end(blockID: blockID)
        }
        startUsageMonitor(forBlockID: blockID)
    }

    /// Stop the lockout window and clear its persisted end-time.
    static func stopLockout(for blockID: UUID) {
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: blockID))
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID))
        DeviceActivityCenter().stopMonitoring([lockActivityName(for: blockID)])
    }
}
