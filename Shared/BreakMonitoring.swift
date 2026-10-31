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
        DeviceActivityName(rawValue: "break.\(blockID.uuidString)")
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
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let windowEnd = now.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: windowEnd),
            repeats: false,
            warningTime: minutes < 15 ? DateComponents(minute: 15 - max(1, minutes)) : nil
        )
        do {
            try DeviceActivityCenter().startMonitoring(breakActivityName(for: blockID), during: schedule)
        } catch {
            print("❌ startBreak monitoring failed for \(blockID): \(error)")
            return false
        }
        SharedDefaults.suite.set(end, forKey: SharedDefaults.Keys.breakEnd(blockID: blockID))
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.breakUsed(blockID: blockID))

        BlockingActuator.clearShields(blockID: blockID)
        return true
    }

    static func finishIfExpired(blockID: UUID, now: Date = Date()) {
        guard let end = breakEnd(blockID: blockID), end <= now else { return }
        endBreak(blockID: blockID, reapply: true)
    }

    /// End the break: tear down the one-shot window and clear the break state.
    /// With `reapply`, the shield goes back up — but only when the block is still
    /// logically on (scheduled window running, or manually/tag enabled); a window
    /// that ended or a tag toggled off during the break must stay released.
    /// `breakUsed` is intentionally NOT cleared here — the allowance resets only
    /// when a fresh activation starts.
    static func endBreak(blockID: UUID, reapply: Bool) {
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.breakEnd(blockID: blockID))
        DeviceActivityCenter().stopMonitoring([breakActivityName(for: blockID)])
        guard reapply else { return }

        if let block = BlockResolution.loadBlock(id: blockID), block.type == .schedule {
            ScheduleEnforcement.reconcile(block: block)
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
    static func resetAllowance(blockID: UUID) {
        endBreak(blockID: blockID, reapply: false)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.breakUsed(blockID: blockID))
    }
}
