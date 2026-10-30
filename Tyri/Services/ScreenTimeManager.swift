//
//  ScreenTimeManager.swift
//  Tyri
//
//  Created by Amit Sankaran on 1/7/26.
//
//  Every block — scheduled, timer, or NFC tag — applies through its own set of
//  `ManagedSettingsStore(named: "block.<UUID>"...)` stores (chunked apps +
//  categories; see BlockingActuator). iOS unions shields across stores, so
//  blocks never clobber each other.
//

import Foundation
import FamilyControls
import ManagedSettings
import Combine

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var authorizationStatus: AuthorizationStatus = .notDetermined

    private init() {
        checkAuthorizationStatus()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            checkAuthorizationStatus()
            restoreBlockingIfNeeded()
            try? await Task.sleep(nanoseconds: 500_000_000)
            checkAuthorizationStatus()
        }
    }

    /// Reapply shields for blocks that should be on across launches: manually
    /// force-enabled blocks and toggled-on tag blocks. (Scheduled/usage shields
    /// persist in their named stores and are managed by the extension.)
    func restoreBlockingIfNeeded() {
        guard authorizationStatus == .approved else {
            print("⚠️ Cannot restore blocking: authorization not approved")
            return
        }
        for block in BlockStore.shared.blocks where block.isEnabled {
            applyBlockShield(block)
        }
    }

    func checkAuthorizationStatus() {
        let previousStatus = authorizationStatus
        let status = AuthorizationCenter.shared.authorizationStatus
        authorizationStatus = status
        if previousStatus != .approved && status == .approved {
            restoreBlockingIfNeeded()
        }
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        checkAuthorizationStatus()
        restoreBlockingIfNeeded()
    }

    // MARK: - Per-block shields

    /// Apply a block's shield (union of its groups' tokens) to its named stores.
    /// Resolves against the in-memory `AppGroupStore` (which can be ahead of the
    /// persisted copy the extension reads), then defers to BlockingActuator.
    func applyBlockShield(_ block: BlockRule) {
        guard authorizationStatus == .approved else {
            #if DEBUG
            DebugLog.shared.log(.screenTime, "applyBlockShield(\(block.name)) skipped — auth not approved")
            #endif
            return
        }
        // Mid-break the shield must stay down — the break's re-lock (extension
        // window / BreakManager) restores it. Without this, launch restore or a
        // Save while on break would silently cut the break short.
        guard !BreakMonitoring.isOnBreak(blockID: block.id) else {
            #if DEBUG
            DebugLog.shared.log(.screenTime, "applyBlockShield(\(block.name)) skipped — on break")
            #endif
            return
        }
        let tokens = BlockResolution.tokens(for: block, groups: AppGroupStore.shared.groups)
        BlockingActuator.apply(tokens: tokens, blockID: block.id)
        #if DEBUG
        let chunkCount = SharedDefaults.suite.integer(forKey: SharedDefaults.Keys.shieldChunkCount(blockID: block.id))
        DebugLog.shared.log(.screenTime, "applyBlockShield(\(block.name)): \(tokens.apps.count) apps + \(tokens.webDomains.count) domains → \(chunkCount) chunk store(s), \(tokens.categories.count) categories")
        #endif
    }

    /// Clear a block's shield (cooldown completion, manual disable, tag toggle-off).
    /// Releasing the block also ends any break on it — without re-shielding — so no
    /// orphaned break window can re-lock a block the user already turned off.
    func clearBlockShield(id: UUID) {
        BreakManager.shared.cancelIfActive(blockID: id)
        BlockingActuator.clearShields(blockID: id)
        #if DEBUG
        DebugLog.shared.log(.screenTime, "clearBlockShield for \(id.uuidString.prefix(8))")
        #endif
    }

    /// Emergency override: clear every block's shield and turn off manual/tag
    /// state. Scheduled/timer blocks may re-apply at their next interval.
    func disableAllBlocks() {
        for block in BlockStore.shared.blocks {
            clearBlockShield(id: block.id)
            UsageMonitoring.stopLockout(for: block.id)
            SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.running(blockID: block.id))
            if block.isEnabled {
                BlockStore.shared.setEnabled(id: block.id, enabled: false)
            }
        }
        CooldownManager.shared.cancel()
        SchedulingManager.shared.refresh()
        UsageLimitManager.shared.refresh()
    }

    /// Single source of truth for "this block is currently enforcing a shield":
    /// manual/tag enable, scheduled interval running, or usage lockout in effect.
    ///
    /// Not itself observable — views get reactivity by holding `@StateObject`s of
    /// `BlockStore` (isEnabled), `SchedulingManager` (running flags), and
    /// `UsageLimitManager` (usage locks), whose published state covers everything
    /// this reads.
    func isBlockActive(_ block: BlockRule) -> Bool {
        let suite = SharedDefaults.suite
        let scheduledActive = suite.bool(forKey: SharedDefaults.Keys.running(blockID: block.id))
        let usageLocked = (suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) as? Date).map { $0 > Date() } ?? false
        return block.isEnabled || scheduledActive || usageLocked
    }

    /// Re-apply if currently shielded (manual, scheduled-running, or usage-locked).
    func updateBlockShieldIfActive(_ block: BlockRule) {
        if isBlockActive(block) {
            applyBlockShield(block)
        }
    }
}
