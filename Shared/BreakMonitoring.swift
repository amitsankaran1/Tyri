//
//  BreakMonitoring.swift
//  Tyri
//
//  Shared plumbing for a bounded break from an active schedule/tag block: the
//  shield lifts immediately and re-applies automatically when the break ends,
//  even if the app is killed — a one-shot DeviceActivity window (mirroring
//  UsageMonitoring's lockout window) has the TyriMonitor extension re-shield
//  out-of-process. Used by:
//    - BreakManager (app side: starts breaks, observable countdown, launch backstop)
//    - TyriMonitorExtension (re-applies the shield when the break window ends)
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
import DeviceActivity

enum BreakMonitoring {

    /// One-shot window spanning the break; its `intervalDidEnd` re-applies the shield.
    static func breakActivityName(for blockID: UUID) -> DeviceActivityName {
        let base = "break.\(blockID.uuidString)"
        return DeviceActivityName(rawValue: MonitorRegistration.current(base, legacyName: base))
    }

    static func registrationContext(blockID: UUID, end: Date) -> String {
        let defaults = SharedDefaults.suite
        return String(end.timeIntervalSince1970.bitPattern, radix: 16) + "|"
            + (defaults.string(forKey: "manualActivation.\(blockID.uuidString)") ?? "legacy") + "|"
            + String((defaults.object(forKey: "scheduleWindowStart.\(blockID.uuidString)") as? Date)?.timeIntervalSince1970 ?? 0)
    }

    static func pendingEnd(blockID: UUID) -> Date? {
        SharedDefaults.suite.object(forKey: "breakPendingEnd.\(blockID)") as? Date
    }

    @discardableResult
    static func finishRegistration(_ ticket: MonitorReservation, blockID: UUID, end: Date, succeeded: Bool) -> MonitorLedger.Completion {
        let block = BlockResolution.loadBlock(id: blockID)
        if let block, block.type == .schedule { ScheduleEnforcement.reconcile(block: block) }
        let currentEnd = breakEnd(blockID: blockID) ?? pendingEnd(blockID: blockID)
        let eligible = block.map { $0.type != .timer && ($0.isEnabled || SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.running(blockID: blockID))) } ?? false
        let context = eligible ? currentEnd.map { registrationContext(blockID: blockID, end: $0) } : nil
        let pendingContext = SharedDefaults.suite.string(forKey: "breakPendingContext.\(blockID)")
        let validContext = pendingEnd(blockID: blockID) == nil || pendingContext == context ? context : nil
        let result = MonitorRegistration.finish(ticket, context: validContext, succeeded: succeeded)
        if currentEnd == end, pendingEnd(blockID: blockID) != nil {
            if result == .promoted || result == .alreadyAccepted {
                SharedDefaults.suite.removeObject(forKey: "breakPendingEnd.\(blockID)")
                SharedDefaults.suite.removeObject(forKey: "breakPendingContext.\(blockID)")
                if end > Date(), let block = BlockResolution.loadBlock(id: blockID),
                   block.isEnabled || SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.running(blockID: blockID)) {
                    SharedDefaults.suite.set(end, forKey: SharedDefaults.Keys.breakEnd(blockID: blockID))
                    SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.breakUsed(blockID: blockID))
                    BlockingActuator.clearShields(blockID: blockID)
                }
            } else if result == .failed || result == .obsolete {
                SharedDefaults.suite.removeObject(forKey: "breakPendingEnd.\(blockID)")
                SharedDefaults.suite.removeObject(forKey: "breakPendingContext.\(blockID)")
            }
        }
        return result
    }

    /// Is the block currently on a break (a future `breakEnd` is the source of truth)?
    static func isOnBreak(blockID: UUID) -> Bool {
        guard let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.breakEnd(blockID: blockID)) as? Date else { return false }
        return end > Date()
    }

    static func breakEnd(blockID: UUID) -> Date? {
        SharedDefaults.suite.object(forKey: SharedDefaults.Keys.breakEnd(blockID: blockID)) as? Date
    }

    static func breakUsed(blockID: UUID) -> Bool {
        SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.breakUsed(blockID: blockID))
    }

    /// Lift the block's shield for `minutes`, marking the activation's single break
    /// as used, and register the one-shot re-lock window. The `running` flag is
    /// deliberately left in place — the schedule window is still logically active.
    ///
    /// Short breaks use an end warning on a 15-minute monitor. Register before
    /// lifting shields; if registration fails, the block remains enforced.
    @discardableResult
    static func startBreak(blockID: UUID, minutes: Int) -> Bool {
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { transition.finish() }

        guard let block = BlockResolution.loadBlock(id: blockID), block.type != .timer,
              minutes > 0, !breakUsed(blockID: blockID), breakEnd(blockID: blockID) == nil, pendingEnd(blockID: blockID) == nil else { return false }
        // Re-check ownership at execution, not only when SwiftUI displayed the button.
        if block.type == .schedule { ScheduleEnforcement.reconcile(block: block) }
        guard block.isEnabled || SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.running(blockID: blockID)) else { return false }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let windowEnd = now.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: now),
            intervalEnd: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: windowEnd),
            repeats: false,
            warningTime: minutes < 15 ? DateComponents(minute: 15 - max(1, minutes)) : nil
        )
        let base = "break.\(blockID.uuidString)"
        let context = registrationContext(blockID: blockID, end: end)
        guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: context) else { return false }
        SharedDefaults.suite.set(context, forKey: "breakPendingContext.\(blockID)")
        SharedDefaults.suite.set(end, forKey: "breakPendingEnd.\(blockID)")
        let result = MonitorResult()
        EnforcementTransaction.afterUnlock(key: ticket.name) {
            guard EnforcementTransaction.effectsAreEnabled else { return }
            do {
                try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: ticket.name), during: schedule)
                result.succeeded = true
            } catch { result.error = error }
            guard let commit = EnforcementTransaction.beginEffect() else { result.succeeded = false; return }
            let completion = finishRegistration(ticket, blockID: blockID, end: end, succeeded: result.succeeded)
            result.succeeded = (completion == .promoted || completion == .alreadyAccepted) && isOnBreak(blockID: blockID)
            commit.finish()
            if completion == .obsolete {
                DeviceActivityCenter().stopMonitoring([DeviceActivityName(rawValue: ticket.name)])
            }
        }
        transition.finish()
        return result.succeeded
    }

    static func finishIfExpired(blockID: UUID, now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let end = breakEnd(blockID: blockID) else { return }
        if end <= now { endBreak(blockID: blockID, reapply: true); return }
        EnforcementTransaction.afterUnlock(key: "repairBreak.\(blockID)") {
            guard !DeviceActivityCenter().activities.contains(breakActivityName(for: blockID)) else { return }
            guard let reservation = EnforcementTransaction.beginEffect() else { return }
            guard breakEnd(blockID: blockID) == end else { reservation.finish(); return }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
            let monitorEnd = max(end, start.addingTimeInterval(900))
            let warning = Int(ceil(monitorEnd.timeIntervalSince(end)))
            let schedule = DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: start),
                intervalEnd: cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: monitorEnd),
                repeats: false, warningTime: warning > 0 ? DateComponents(second: warning) : nil)
            let base = "break.\(blockID.uuidString)"
            let context = registrationContext(blockID: blockID, end: end)
            guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: context) else { reservation.finish(); return }
            reservation.finish()
            do {
                try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: ticket.name), during: schedule)
                guard let commit = EnforcementTransaction.beginEffect() else { return }
                defer { commit.finish() }
                _ = MonitorRegistration.finish(ticket, context: breakEnd(blockID: blockID).map { registrationContext(blockID: blockID, end: $0) }, succeeded: true)
            }
            catch {
                guard let commit = EnforcementTransaction.beginEffect() else { return }
                defer { commit.finish() }
                let result = MonitorRegistration.finish(ticket, context: breakEnd(blockID: blockID).map { registrationContext(blockID: blockID, end: $0) }, succeeded: false)
                guard result == .failed else { return }
                // Never leave an unbounded pause if its automatic re-lock is lost.
                endBreak(blockID: blockID, reapply: true)
            }
        }
    }

    /// End the break: tear down the one-shot window and clear the break state.
    /// With `reapply`, the shield goes back up — but only when the block is still
    /// logically on (scheduled window running, or manually/tag enabled); a window
    /// that ended or a tag toggled off during the break must stay released.
    /// `breakUsed` is intentionally NOT cleared here — the allowance resets only
    /// when a fresh activation starts.
    static func endBreak(blockID: UUID, reapply: Bool, stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        let activity = breakActivityName(for: blockID)
        MonitorRegistration.invalidate("break.\(blockID.uuidString)", legacyName: "break.\(blockID.uuidString)")
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.breakEnd(blockID: blockID))
        SharedDefaults.suite.removeObject(forKey: "breakPendingEnd.\(blockID)")
        SharedDefaults.suite.removeObject(forKey: "breakPendingContext.\(blockID)")
        if stopMonitoring {
            EnforcementTransaction.afterUnlock(key: "stop." + activity.rawValue) {
                DeviceActivityCenter().stopMonitoring([activity])
            }
        }
        guard reapply else { return }

        if let block = BlockResolution.loadBlock(id: blockID), block.type == .schedule {
            ScheduleEnforcement.reconcile(block: block, stopMonitoring: stopMonitoring)
            return
        }
        let running = SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.running(blockID: blockID))
        let enabled = BlockResolution.loadBlock(id: blockID)?.isEnabled ?? false
        guard running || enabled else { return }
        BlockingActuator.start(
            blockID: blockID,
            bypassWeekday: true,
            setRunningFlag: running,
            resetBreakAllowance: false
        )
    }

    /// Cancel any break state without re-shielding (window end, tag toggle-off,
    /// emergency override) and re-arm the activation's break allowance.
    static func resetAllowance(blockID: UUID, stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        endBreak(blockID: blockID, reapply: false, stopMonitoring: stopMonitoring)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.breakUsed(blockID: blockID))
    }
}
