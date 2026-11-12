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
import OSLog

class TyriMonitorExtension: DeviceActivityMonitor {
    private let log = Logger(subsystem: "name.amitsankaran.Block", category: "MonitorCallbacks")

    private enum ActivityKind {
        case schedule    // block.<UUID> (and .early/.late) — time-of-day block
        case usage       // usage.<UUID> — cumulative counting window
        case lock        // lock.<UUID> — one-shot usage lockout window
        case breakWindow // break.<UUID> — one-shot break window (shield lifted)
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        super.intervalDidStart(for: activity)
        log.notice("Interval start \(activity.rawValue, privacy: .public)")
        if activity.rawValue.hasPrefix("adhoc.") { Self.reconcileAdHoc(activity); return }
        guard let (kind, blockID) = Self.parse(activity), Self.accept(activity, kind: kind, id: blockID) else { return }
        EnforcementDiagnostics.record("callback", blockID: blockID, detail: "Interval start: \(activity.rawValue)")
        switch kind {
        case .schedule:
            ScheduleEnforcement.reconcile(blockID: blockID)
        case .lock:
            UsageMonitoring.reconcileLockout(blockID: blockID)
        case .usage:
            break // counting window only — never shields on its own.
        case .breakWindow:
            break // the app already lifted the shield when the break started.
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        super.intervalDidEnd(for: activity)
        log.notice("Interval end \(activity.rawValue, privacy: .public)")
        if activity.rawValue.hasPrefix("adhoc.") { Self.reconcileAdHoc(activity); return }
        guard let (kind, blockID) = Self.parse(activity), Self.accept(activity, kind: kind, id: blockID) else { return }
        EnforcementDiagnostics.record("callback", blockID: blockID, detail: "Interval end: \(activity.rawValue)")
        switch kind {
        case .schedule:
            ScheduleEnforcement.reconcile(blockID: blockID)
        case .lock:
            UsageMonitoring.reconcileLockout(blockID: blockID)
        case .usage:
            break // all-day window auto-restarts (repeats: true); counter resets.
        case .breakWindow:
            // Break over — re-shield, but only if the block is still logically on
            // (endBreak checks; a window that ended mid-break stays released).
            BreakMonitoring.finishIfExpired(blockID: blockID)
        }
    }

    /// Cumulative usage crossed the block's budget — lock the whole block.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        super.eventDidReachThreshold(event, activity: activity)
        log.notice("Threshold \(activity.rawValue, privacy: .public), event \(event.rawValue, privacy: .public)")
        guard let (kind, blockID) = Self.parse(activity), kind == .usage else { return }

        EnforcementDiagnostics.record("threshold", blockID: blockID, detail: "Received \(event.rawValue); current generation match: \(activity == UsageMonitoring.usageActivityName(for: blockID))")

        // Shield immediately, then register the timed lockout so it auto-releases.
        guard let block = BlockResolution.loadBlock(id: blockID), block.type == .timer,
              let groups = BlockResolution.loadGroups(),
              UsageMonitoring.acceptRegistration(activity.rawValue, for: block, groups: groups),
              (block.usageLimitMinutes ?? 0) > 0 else { return }
        if event.rawValue.hasPrefix("progress."),
           let minute = Int(event.rawValue.dropFirst("progress.".count)),
           UsageProgress.milestones(for: block.usageLimitMinutes ?? 0).contains(minute) {
            UsageProgress.record(minute, blockID: blockID)
            return
        }
        guard event == UsageMonitoring.usageEventName else { return }
        UsageProgress.record(block.usageLimitMinutes ?? 0, blockID: blockID)
        let lockMinutes = block.usageLockMinutes
        UsageMonitoring.startLockout(blockID: blockID, minutes: lockMinutes)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        super.intervalWillEndWarning(for: activity)
        if activity.rawValue.hasPrefix("adhoc.") { Self.reconcileAdHoc(activity); return }
        guard let (kind, blockID) = Self.parse(activity), Self.accept(activity, kind: kind, id: blockID) else { return }
        if kind == .lock { UsageMonitoring.reconcileLockout(blockID: blockID) }
        if kind == .breakWindow { BreakMonitoring.finishIfExpired(blockID: blockID) }
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
        uuidPart = uuidPart.split(separator: ".").first ?? uuidPart
        guard let id = UUID(uuidString: String(uuidPart)) else { return nil }
        return (kind, id)
    }

    private static func accept(_ activity: DeviceActivityName, kind: ActivityKind, id: UUID) -> Bool {
        let namespace: String
        let context: String?
        switch kind {
        case .schedule:
            namespace = "block.\(id.uuidString)"
            context = BlockResolution.loadBlock(id: id)?.schedule.map(ScheduleEnforcement.registrationContext)
        case .lock:
            namespace = "lock.\(id.uuidString)"
            context = (SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date).map {
                UsageMonitoring.lockContext(blockID: id, end: $0)
            }
        case .breakWindow:
            namespace = "break.\(id.uuidString)"
            context = (BreakMonitoring.breakEnd(blockID: id) ?? BreakMonitoring.pendingEnd(blockID: id)).map { BreakMonitoring.registrationContext(blockID: id, end: $0) }
        case .usage:
            // Interval callbacks never consume an allowance.
            return true
        }
        var name = activity.rawValue
        if name == namespace + ".early" || name == namespace + ".late" { name = namespace }
        let result = MonitorRegistration.accept(name, namespace: namespace, legacyName: namespace, context: context)
        if kind == .breakWindow, result == .promoted || result == .alreadyAccepted,
           let end = BreakMonitoring.breakEnd(blockID: id) ?? BreakMonitoring.pendingEnd(blockID: id),
           let owner = MonitorRegistration.load(namespace, legacyName: nil, context: "")?.confirmed {
            _ = BreakMonitoring.finishRegistration(MonitorReservation(namespace: namespace, owner: owner),
                                                   blockID: id, end: end, succeeded: true)
        }
        return result == .promoted || result == .alreadyAccepted
    }

    private static func reconcileAdHoc(_ activity: DeviceActivityName) {
        guard let session = AdHocMonitoring.session else { return }
        let namespace = "adhoc.\(session.id.uuidString)"
        let result = MonitorRegistration.accept(activity.rawValue, namespace: namespace, legacyName: namespace,
                                                context: AdHocMonitoring.registrationContext(session))
        if result == .promoted || result == .alreadyAccepted,
           let owner = MonitorRegistration.load(namespace, legacyName: nil, context: "")?.confirmed {
            _ = AdHocMonitoring.finishRegistration(MonitorReservation(namespace: namespace, owner: owner), succeeded: true)
            AdHocMonitoring.reconcile()
        }
    }
}
