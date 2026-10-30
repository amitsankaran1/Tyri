//
//  TyriMonitorExtension.swift
//  TyriMonitor
//
//  DeviceActivityMonitor extension. Runs out-of-process when iOS triggers a scheduled
//  interval or a usage threshold.
//
//  Activity names (see SchedulingManager / UsageMonitoring / BreakMonitoring):
//    - "block.<UUID>" / ".early" / ".late"  → time-of-day scheduled block
//    - "usage.<UUID>"                        → all-day usage counting window
//    - "lock.<UUID>"                         → one-shot usage lockout window
//    - "break.<UUID>"                        → one-shot break window (shield lifted)
//
//  Required target setup (do in Xcode UI):
//    - Target: TyriMonitor (Device Activity Monitor Extension template)
//    - Embed in host app: Tyri
//    - Capabilities on this target: Family Controls, App Groups (group.com.amitsankaran.Block)
//    - Target membership for the Shared/ files (SharedDefaults, BlockRule, AppGroup,
//      BlockingSchedule, BlockingActuator, UsageMonitoring, BreakMonitoring,
//      BlockResolution): tick BOTH targets.
//

import DeviceActivity
import Foundation

class TyriMonitorExtension: DeviceActivityMonitor {

    private enum ActivityKind {
        case schedule    // block.<UUID> (and .early/.late) — time-of-day block
        case usage       // usage.<UUID> — cumulative counting window
        case lock        // lock.<UUID> — one-shot usage lockout window
        case breakWindow // break.<UUID> — one-shot break window (shield lifted)
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let (kind, blockID) = Self.parse(activity) else { return }
        switch kind {
        case .schedule:
            BlockingActuator.start(blockID: blockID)
        case .lock:
            // Lockout window began — ensure the shield is up (idempotent; the
            // threshold handler already applied it).
            BlockingActuator.start(blockID: blockID, bypassWeekday: true, setRunningFlag: false)
        case .usage:
            break // counting window only — never shields on its own.
        case .breakWindow:
            break // the app already lifted the shield when the break started.
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let (kind, blockID) = Self.parse(activity) else { return }
        switch kind {
        case .schedule:
            BlockingActuator.end(blockID: blockID)
        case .lock:
            // Lockout elapsed — release the shield, clear the lock state, and
            // re-arm the usage budget from zero.
            BlockingActuator.end(blockID: blockID)
            UsageMonitoring.stopLockout(for: blockID)
            UsageMonitoring.startUsageMonitor(forBlockID: blockID)
        case .usage:
            break // all-day window auto-restarts (repeats: true); counter resets.
        case .breakWindow:
            // Break over — re-shield, but only if the block is still logically on
            // (endBreak checks; a window that ended mid-break stays released).
            BreakMonitoring.endBreak(blockID: blockID, reapply: true)
        }
    }

    /// Cumulative usage crossed the block's budget — lock the whole block.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let (kind, blockID) = Self.parse(activity), kind == .usage else { return }

        // Shield immediately, then register the timed lockout so it auto-releases.
        BlockingActuator.start(blockID: blockID, bypassWeekday: true, setRunningFlag: false)
        let lockMinutes = BlockResolution.loadBlock(id: blockID)?.usageLockMinutes ?? 180
        UsageMonitoring.startLockout(blockID: blockID, minutes: lockMinutes)
    }

    // MARK: - Parsing

    /// Map an activity name to its kind + block UUID. Returns nil for anything
    /// unrecognized.
    private static func parse(_ activity: DeviceActivityName) -> (ActivityKind, UUID)? {
        let raw = activity.rawValue
        let kind: ActivityKind
        let rest: Substring
        if raw.hasPrefix("block.") {
            kind = .schedule
            rest = raw.dropFirst("block.".count)
        } else if raw.hasPrefix("usage.") {
            kind = .usage
            rest = raw.dropFirst("usage.".count)
        } else if raw.hasPrefix("lock.") {
            kind = .lock
            rest = raw.dropFirst("lock.".count)
        } else if raw.hasPrefix("break.") {
            kind = .breakWindow
            rest = raw.dropFirst("break.".count)
        } else {
            return nil
        }

        // Strip the cross-midnight segment suffix used by scheduled blocks.
        var uuidPart = rest
        if uuidPart.hasSuffix(".early") {
            uuidPart = uuidPart.dropLast(".early".count)
        } else if uuidPart.hasSuffix(".late") {
            uuidPart = uuidPart.dropLast(".late".count)
        }
        guard let id = UUID(uuidString: String(uuidPart)) else { return nil }
        return (kind, id)
    }
}
