//
//  BreakManager.swift
//  Tyri
//
//  App-side state for the bounded break mechanic: starts a break on a
//  schedule/tag block (shield lifts immediately), publishes the countdown, and
//  auto-re-locks at expiry. The out-of-process re-lock — app killed mid-break —
//  is handled by the TyriMonitor extension's one-shot break window (see
//  BreakMonitoring); `restoreActiveBreaksIfAny()` is the launch backstop.
//

import Foundation
import Combine

@MainActor
class BreakManager: ObservableObject {
    static let shared = BreakManager()

    struct ActiveBreak: Equatable {
        let blockID: UUID
        let endsAt: Date
    }

    @Published private(set) var isStarting = false
    @Published var lastError: String?
    @Published private(set) var activeBreak: ActiveBreak?

    private var foregroundActive = true
    private var tickTimer: Timer?
    private var defaults: UserDefaults { SharedDefaults.suite }

    private init() {}

    // MARK: - Queries

    func isOnBreak(blockID: UUID) -> Bool {
        BreakMonitoring.isOnBreak(blockID: blockID)
    }

    /// Can this block offer its "Take a break" action right now? (Type and
    /// activity gating is the caller's job — this covers the break rules.)
    func isBreakAvailable(for block: BlockRule) -> Bool {
        !isStarting && block.type != .timer
            && block.breakMinutes > 0
            && !BreakMonitoring.breakUsed(blockID: block.id)
            && BreakMonitoring.pendingEnd(blockID: block.id) == nil
            && !isOnBreak(blockID: block.id)
            && activeBreak == nil
    }

    /// Time remaining for the active break, or 0 if none.
    var remaining: TimeInterval {
        guard let active = activeBreak else { return 0 }
        return max(0, active.endsAt.timeIntervalSinceNow)
    }

    // MARK: - Lifecycle

    /// Start the block's single per-activation break. No-op if breaks are off,
    /// already used this activation, or another break is running.
    func start(for block: BlockRule) {
        guard isBreakAvailable(for: block) else { return }
        isStarting = true
        Task {
            let succeeded = (try? await ForegroundRecovery.shared.command {
                BreakMonitoring.startBreak(blockID: block.id, minutes: block.breakMinutes)
            }) ?? false
            isStarting = false
            if succeeded || BreakMonitoring.isOnBreak(blockID: block.id) { lastError = nil }
            else if BreakMonitoring.pendingEnd(blockID: block.id) != nil {
                lastError = "Your break is waiting for iOS to confirm its automatic re-lock. Apps stay blocked until then. Reopen Tyri to resume confirmation; the original end time still applies."
            } else {
                lastError = "The automatic re-lock could not be scheduled. Your block is still on. Please try again."
            }
            publishPersistedState()
            SchedulingManager.shared.refresh()
        }
    }

    /// End the active break now and re-lock (if the block is still logically on).
    func endActiveBreak() {
        guard let active = activeBreak else { return }
        finish(blockID: active.blockID, reapply: true)
    }

    /// Drop break state for a block without re-shielding — the block itself is
    /// being released (tag toggle-off, cooldown release, delete, emergency).
    func cancelIfActive(blockID: UUID) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { ForegroundRecovery.shared.finish(transition) }
        // Shared state may exist even when local state doesn't (e.g. app relaunch
        // raced the restore) — always reset it.
        BreakMonitoring.resetAllowance(blockID: blockID)
        if activeBreak?.blockID == blockID {
            activeBreak = nil
            stopTickTimer()
        }
    }

    /// Resume a mid-flight break after launch, or complete one that expired while
    /// the app was closed and the extension's one-shot window didn't fire.
    func restoreActiveBreaksIfAny() {
        ForegroundRecovery.shared.request()
        publishPersistedState()
    }

    func publishPersistedState() {
        let now = Date()
        activeBreak = nil
        stopTickTimer()
        for block in BlockStore.shared.blocks {
            guard let endsAt = BreakMonitoring.breakEnd(blockID: block.id) else { continue }
            if endsAt > now {
                lastError = nil
                activeBreak = ActiveBreak(blockID: block.id, endsAt: endsAt)
                startTickTimer()
                return
            } else {
                ForegroundRecovery.shared.request()
            }
        }
    }

    // MARK: - Private

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
        stopTickTimer()
        if active { publishPersistedState() }
    }

    private func finish(blockID: UUID, reapply: Bool) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { ForegroundRecovery.shared.finish(transition) }
        BreakMonitoring.endBreak(blockID: blockID, reapply: reapply)
        activeBreak = nil
        stopTickTimer()
        SchedulingManager.shared.refresh()
        #if DEBUG
        DebugLog.shared.log(.actuator, "break end block=\(blockID.uuidString.prefix(8)) reapply=\(reapply)")
        #endif
    }

    private func startTickTimer() {
        guard foregroundActive else { return }
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let active = self.activeBreak else { return }
                // Force a publisher update so views recompute `remaining`.
                self.objectWillChange.send()
                // Unlike a cooldown, a break auto-completes: the whole point is
                // that the shield comes back without the user's help. The
                // extension's one-shot window does the same out-of-process;
                // both paths are idempotent.
                if active.endsAt <= Date() {
                    ForegroundRecovery.shared.request()
                }
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
