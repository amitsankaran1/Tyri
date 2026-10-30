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

enum UsageMonitoring {

    // MARK: - Names

    /// All-day counting window carrying the cumulative-usage threshold event.
    static func usageActivityName(for blockID: UUID) -> DeviceActivityName {
        DeviceActivityName(rawValue: "usage.\(blockID.uuidString)")
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
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }

    /// The threshold event for a timer block, or nil if the limit is off / the
    /// resolved group selection is empty.
    static func usageEvent(for block: BlockRule, groups: [AppGroup]) -> DeviceActivityEvent? {
        guard block.type == .timer, let limit = block.usageLimitMinutes, limit > 0 else { return nil }
        let tokens = BlockResolution.tokens(for: block, groups: groups)
        guard !tokens.isEmpty else { return nil }
        return DeviceActivityEvent(
            applications: tokens.apps,
            categories: tokens.categories,
            webDomains: tokens.webDomains,
            threshold: DateComponents(minute: limit)
        )
    }

    // MARK: - Register / tear down

    /// Start the all-day usage threshold monitor for a timer block. Returns false
    /// when there's nothing to monitor or registration fails.
    @discardableResult
    static func startUsageMonitor(for block: BlockRule, groups: [AppGroup]) -> Bool {
        guard let event = usageEvent(for: block, groups: groups) else { return false }
        do {
            try DeviceActivityCenter().startMonitoring(
                usageActivityName(for: block.id),
                during: allDaySchedule,
                events: [usageEventName: event]
            )
            return true
        } catch {
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
        DeviceActivityCenter().stopMonitoring([usageActivityName(for: blockID)])
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
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        SharedDefaults.suite.set(end, forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID))

        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: cal.dateComponents([.hour, .minute, .second], from: end),
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(lockActivityName(for: blockID), during: schedule)
        } catch {
            print("❌ startLockout failed for \(blockID): \(error)")
        }
    }

    /// Stop the lockout window and clear its persisted end-time.
    static func stopLockout(for blockID: UUID) {
        DeviceActivityCenter().stopMonitoring([lockActivityName(for: blockID)])
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID))
    }
}
