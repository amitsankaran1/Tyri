//
//  CooldownManager.swift
//  Tyri
//
//  Tracks an active cooldown countdown when the user requests an early disable
//  on a scheduled-active preset. Persists the end-time so killing the app
//  doesn't bypass the wait.
//

import Foundation
import Combine

@MainActor
class CooldownManager: ObservableObject {
    static let shared = CooldownManager()

    struct ActiveCooldown: Equatable {
        let blockID: UUID
        let endsAt: Date
    }

    @Published private(set) var activeCooldown: ActiveCooldown?

    private var tickTimer: Timer?
    private var defaults: UserDefaults { SharedDefaults.suite }

    private init() {}

    /// Restore unfinished cooldowns from disk.
    /// If the cooldown end-time has already passed, completes it now.
    func restoreActiveCooldownsIfAny() {
        // Look across all blocks — only one cooldown is active at a time
        // but we don't track which one is "active" so we scan.
        let now = Date()
        for block in BlockStore.shared.blocks {
            let key = SharedDefaults.Keys.cooldownEnd(blockID: block.id)
            guard let endsAt = defaults.object(forKey: key) as? Date else { continue }
            if endsAt > now {
                activeCooldown = ActiveCooldown(blockID: block.id, endsAt: endsAt)
                startTickTimer()
                return
            } else {
                // Cooldown already expired while app was closed — release.
                completeImmediately(blockID: block.id)
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Start a new cooldown. If one is already active for a different block, it's cancelled.
    /// Zero minutes means "no cooldown = no early disable", so a cooldown must never
    /// start for it — the disable path simply doesn't exist for those blocks.
    func start(for blockID: UUID, minutes: Int) {
        guard minutes >= 1 else { return }
        cancel()
        let endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let cooldown = ActiveCooldown(blockID: blockID, endsAt: endsAt)
        activeCooldown = cooldown
        defaults.set(endsAt, forKey: SharedDefaults.Keys.cooldownEnd(blockID: blockID))
        startTickTimer()
        #if DEBUG
        DebugLog.shared.log(.cooldown, "start(\(minutes)m) block=\(blockID.uuidString.prefix(8)) ends=\(endsAt)")
        #endif
    }

    func cancel() {
        guard let active = activeCooldown else { return }
        defaults.removeObject(forKey: SharedDefaults.Keys.cooldownEnd(blockID: active.blockID))
        activeCooldown = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Time remaining for the active cooldown, or 0 if none.
    var remaining: TimeInterval {
        guard let active = activeCooldown else { return 0 }
        return max(0, active.endsAt.timeIntervalSinceNow)
    }

    var isComplete: Bool {
        guard let active = activeCooldown else { return false }
        return active.endsAt <= Date()
    }

    /// Releases the preset's shield once the cooldown ends.
    /// The schedule remains registered — the next interval will re-shield.
    func complete() {
        guard let active = activeCooldown else { return }
        completeImmediately(blockID: active.blockID)
        defaults.removeObject(forKey: SharedDefaults.Keys.cooldownEnd(blockID: active.blockID))
        activeCooldown = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func completeImmediately(blockID: UUID) {
        // Note whether this release is ending a usage lockout (vs. a scheduled
        // block) before we clear any state.
        let wasUsageLocked = (defaults.object(
            forKey: SharedDefaults.Keys.usageLockEnd(blockID: blockID)) as? Date).map { $0 > Date() } ?? false

        // Clear the named store and the running flag.
        ScreenTimeManager.shared.clearBlockShield(id: blockID)
        defaults.removeObject(forKey: SharedDefaults.Keys.running(blockID: blockID))

        // Releasing a usage lockout early: drop the lockout window and start a
        // fresh budget so the limit re-arms.
        if wasUsageLocked {
            UsageLimitManager.shared.rearmAfterRelease(blockID: blockID)
        }

        // Also turn off manual enable so the editor reflects the change.
        if let block = BlockStore.shared.block(id: blockID), block.isEnabled {
            BlockStore.shared.setEnabled(id: blockID, enabled: false)
        }
        SchedulingManager.shared.refresh()
        UsageLimitManager.shared.refresh()
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let active = self.activeCooldown else { return }
                // Force a publisher update so the view recomputes `remaining`.
                self.objectWillChange.send()
                // At expiry, stop ticking but do NOT auto-complete: the user must
                // tap "Release Block" (auto-completing here cleared the shield
                // silently and left the button permanently disabled). The
                // app-killed case is still auto-released on next launch by
                // `restoreActiveCooldownsIfAny()`.
                if active.endsAt <= Date() {
                    self.tickTimer?.invalidate()
                    self.tickTimer = nil
                }
            }
        }
    }
}
