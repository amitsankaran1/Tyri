import Foundation

/// Shared by foreground recovery and extension callbacks. Callback delivery order
/// is not schedule state: stopping/replacing a monitor can deliver a stale end.
enum ScheduleEnforcement {
    static func releaseCurrentWindow(block: BlockRule, now: Date = Date()) {
        guard block.type == .schedule, let window = block.schedule?.activeWindow(at: now) else { return }
        SharedDefaults.suite.set(window.end, forKey: SharedDefaults.Keys.scheduleReleasedUntil(blockID: block.id))
    }

    static func reconcile(blockID: UUID, now: Date = Date()) {
        guard let block = BlockResolution.loadBlock(id: blockID) else { return }
        reconcile(block: block, now: now)
    }

    static func reconcile(block: BlockRule, now: Date = Date()) {
        guard block.type == .schedule else { return }
        let defaults = SharedDefaults.suite
        let runningKey = SharedDefaults.Keys.running(blockID: block.id)
        let windowKey = SharedDefaults.Keys.scheduleWindowStart(blockID: block.id)
        let releaseKey = SharedDefaults.Keys.scheduleReleasedUntil(blockID: block.id)
        let window = block.schedule?.activeWindow(at: now)
        let releasedUntil = defaults.object(forKey: releaseKey) as? Date
        if let releasedUntil, releasedUntil <= now { defaults.removeObject(forKey: releaseKey) }

        if let window, !(releasedUntil.map { $0 > now } ?? false) {
            let previousStart = defaults.object(forKey: windowKey) as? Date
            // Adopt an existing activation on upgrade without cancelling its break.
            if previousStart != window.start &&
                !(previousStart == nil && defaults.bool(forKey: runningKey)) {
                BreakMonitoring.resetAllowance(blockID: block.id)
            }
            defaults.set(window.start, forKey: windowKey)
            defaults.set(true, forKey: runningKey)
            if !BreakMonitoring.isOnBreak(blockID: block.id) {
                BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: BlockResolution.loadGroups()),
                                       blockID: block.id)
            }
        } else {
            if defaults.bool(forKey: runningKey) || defaults.object(forKey: windowKey) != nil {
                BreakMonitoring.resetAllowance(blockID: block.id)
            }
            defaults.removeObject(forKey: runningKey)
            defaults.removeObject(forKey: windowKey)
            // Ending a schedule must not lift an independent manual activation.
            if block.isEnabled {
                if !BreakMonitoring.isOnBreak(blockID: block.id) {
                    BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: BlockResolution.loadGroups()),
                                           blockID: block.id)
                }
            } else {
                BlockingActuator.clearShields(blockID: block.id)
            }
        }
    }
}
