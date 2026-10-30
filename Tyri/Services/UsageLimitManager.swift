//
//  UsageLimitManager.swift
//  Tyri
//
//  App-side owner of the usage-timer mechanic. Registers/refreshes the per-block
//  all-day usage threshold monitors (delegating the DeviceActivity calls to the
//  shared `UsageMonitoring` helper) and publishes which blocks are usage-locked
//  so the UI can react.
//
//  This is the usage-timer sibling of `SchedulingManager` (time-of-day blocks).
//

import Foundation
import Combine

@MainActor
class UsageLimitManager: ObservableObject {
    static let shared = UsageLimitManager()

    /// Blocks currently inside an active usage lockout (usageLockEnd in the future).
    @Published private(set) var activeUsageLockBlockIDs: Set<UUID> = []

    private var defaults: UserDefaults { SharedDefaults.suite }
    private var refreshTimer: Timer?

    private var groups: [AppGroup] { AppGroupStore.shared.groups }

    private init() {
        refresh()
        startPeriodicRefresh()
    }

    // MARK: - Public API

    /// Register (or refresh) the all-day usage threshold monitor for a timer block.
    ///
    /// - Parameter forceReset: when `true`, restart so iOS's threshold counter
    ///   resets (use on settings change and after a lockout). When `false`
    ///   (launch), leave an already-running monitor untouched so the day's
    ///   accumulated usage isn't wiped just by reopening the app.
    func applyUsageLimit(for block: BlockRule, forceReset: Bool = true) {
        let active = UsageMonitoring.isUsageMonitorActive(for: block.id)

        // Nothing to monitor (not a timer / limit off / empty groups): stop if running.
        guard UsageMonitoring.usageEvent(for: block, groups: groups) != nil else {
            if active { UsageMonitoring.stopUsageMonitor(for: block.id) }
            return
        }

        // Idempotent launch path: preserve the running monitor (and its counter).
        if active && !forceReset { return }
        if active { UsageMonitoring.stopUsageMonitor(for: block.id) }

        UsageMonitoring.startUsageMonitor(for: block, groups: groups)
        #if DEBUG
        DebugLog.shared.log(.deviceActivity,
            "applyUsageLimit(\(block.name)): \(block.usageLimitMinutes ?? 0)m → lock \(block.usageLockMinutes)m")
        #endif
    }

    /// Full teardown: stop the counting + lockout windows and clear the lock state.
    /// Only releases the shield if a usage lock was actually holding it (and no
    /// scheduled run or manual enable is keeping it up).
    func removeUsageLimit(for block: BlockRule) {
        let wasLocked = lockEnd(for: block.id) != nil
        UsageMonitoring.stopUsageMonitor(for: block.id)
        UsageMonitoring.stopLockout(for: block.id) // also clears the persisted end-time
        if wasLocked {
            let scheduledRunning = defaults.bool(forKey: SharedDefaults.Keys.running(blockID: block.id))
            if !scheduledRunning && !block.isEnabled {
                ScreenTimeManager.shared.clearBlockShield(id: block.id)
            }
        }
        refresh()
        #if DEBUG
        DebugLog.shared.log(.deviceActivity, "removeUsageLimit(\(block.name))")
        #endif
    }

    /// Re-register all usage monitors. Call once at launch — uses the non-resetting
    /// path so a relaunch doesn't hand back a fresh daily budget.
    func reapplyAllUsageLimits() {
        for block in BlockStore.shared.blocks where block.type == .timer {
            applyUsageLimit(for: block, forceReset: false)
        }
        refresh()
    }

    /// Clear any lockouts whose end-time has already passed (e.g. while the app
    /// was closed and the one-shot lock window didn't fire) and re-arm the budget.
    func reconcileExpiredLocks() {
        let now = Date()
        for block in BlockStore.shared.blocks where block.type == .timer {
            let key = SharedDefaults.Keys.usageLockEnd(blockID: block.id)
            guard let endsAt = defaults.object(forKey: key) as? Date, endsAt <= now else { continue }
            UsageMonitoring.stopLockout(for: block.id) // also clears the persisted end-time
            BlockingActuator.end(blockID: block.id)
            applyUsageLimit(for: block, forceReset: true) // fresh budget
            #if DEBUG
            DebugLog.shared.log(.deviceActivity, "reconcile: cleared expired usage lock \(block.id.uuidString.prefix(8))")
            #endif
        }
        refresh()
    }

    /// Re-arm a block's budget after an early release / external clear.
    func rearmAfterRelease(blockID: UUID) {
        UsageMonitoring.stopLockout(for: blockID)
        if let block = BlockStore.shared.block(id: blockID) {
            applyUsageLimit(for: block, forceReset: true)
        }
        refresh()
    }

    /// Recompute `activeUsageLockBlockIDs` from the persisted lock end-times.
    func refresh() {
        let now = Date()
        var ids: Set<UUID> = []
        for block in BlockStore.shared.blocks {
            if let endsAt = defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date,
               endsAt > now {
                ids.insert(block.id)
            }
        }
        if ids != activeUsageLockBlockIDs {
            activeUsageLockBlockIDs = ids
        }
    }

    /// End-time of an active usage lockout for a block, or nil if not locked.
    func lockEnd(for blockID: UUID) -> Date? {
        guard let endsAt = defaults.object(
            forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date,
              endsAt > Date() else { return nil }
        return endsAt
    }

    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
}
