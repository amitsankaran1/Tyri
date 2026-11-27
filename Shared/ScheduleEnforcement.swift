import Foundation

/// Shared by foreground recovery and extension callbacks. Callback delivery order
/// is not schedule state: stopping/replacing a monitor can deliver a stale end.
enum ScheduleEnforcement {
    static func registrationContext(_ schedule: BlockingSchedule) -> String {
        "\(schedule.startHour):\(schedule.startMinute)-\(schedule.endHour):\(schedule.endMinute)|\(schedule.weekdays.sorted())|\(schedule.repeats)"
    }
    static func manualRegistrationContext(end: Date) -> String {
        String(end.timeIntervalSinceReferenceDate)
    }

    static func releaseCurrentWindow(block: BlockRule, now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard block.type == .schedule, let window = block.schedule?.activeWindow(at: now) else { return }
        SharedDefaults.suite.set(window.end, forKey: SharedDefaults.Keys.scheduleReleasedUntil(blockID: block.id))
    }

    static func reconcile(blockID: UUID, now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let block = BlockResolution.loadBlock(id: blockID) else { return }
        reconcile(block: block, now: now)
    }

    static func reconcile(block: BlockRule, now: Date = Date(), stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard block.type == .schedule else { return }
        let defaults = SharedDefaults.suite
        let runningKey = SharedDefaults.Keys.running(blockID: block.id)
        let windowKey = SharedDefaults.Keys.scheduleWindowStart(blockID: block.id)
        let releaseKey = SharedDefaults.Keys.scheduleReleasedUntil(blockID: block.id)
        let window = block.schedule?.activeWindow(at: now)
        let releasedUntil = defaults.object(forKey: releaseKey) as? Date
        if let releasedUntil, releasedUntil <= now { defaults.removeObject(forKey: releaseKey) }

        // Vacation suppresses windows that begin after the pause; it never lifts
        // an activation that was already under way.
        let paused = window.map { VacationMode.suppresses(block.id, windowStart: $0.start, at: now) } ?? false
        if let window, !(releasedUntil.map { $0 > now } ?? false), !paused {
            let previousStart = defaults.object(forKey: windowKey) as? Date
            // Adopt an existing activation on upgrade without cancelling its break.
            if previousStart != window.start &&
                !(previousStart == nil && defaults.bool(forKey: runningKey)) {
                BreakMonitoring.resetAllowance(blockID: block.id, stopMonitoring: stopMonitoring)
            }
            defaults.set(window.start, forKey: windowKey)
            defaults.set(true, forKey: runningKey)
            if !BreakMonitoring.isOnBreak(blockID: block.id) {
                if let tokens = BlockResolution.tokens(forBlockID: block.id) {
                    BlockingActuator.apply(tokens: tokens, blockID: block.id)
                }
            }
        } else {
            if defaults.bool(forKey: runningKey) || defaults.object(forKey: windowKey) != nil {
                BreakMonitoring.resetAllowance(blockID: block.id, stopMonitoring: stopMonitoring)
            }
            defaults.removeObject(forKey: runningKey)
            defaults.removeObject(forKey: windowKey)
            // Ending a schedule must not lift an independent manual activation.
            if block.isEnabled(at: now) {
                if !BreakMonitoring.isOnBreak(blockID: block.id) {
                    if let tokens = BlockResolution.tokens(forBlockID: block.id) {
                        BlockingActuator.apply(tokens: tokens, blockID: block.id)
                    }
                }
            } else {
                if block.manualScheduleEnd != nil &&
                    (BreakMonitoring.breakEnd(blockID: block.id) != nil || BreakMonitoring.pendingEnd(blockID: block.id) != nil) {
                    BreakMonitoring.resetAllowance(blockID: block.id, stopMonitoring: stopMonitoring)
                }
                BlockingActuator.clearShields(blockID: block.id)
            }
        }
    }
}
