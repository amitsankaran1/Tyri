//
//  TyriApp.swift
//  Tyri
//
//  Created by Amit Sankaran on 1/7/26.
//

import SwiftUI
import CoreNFC

@main
struct TyriApp: App {
    @StateObject private var nfcManager = NFCManager.shared

    init() {
        AppConfigurationStore.migrateLegacyDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    _ = AppGroupStore.shared
                    _ = BlockStore.shared
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["BLOCK_SEED_LEGACY"] == "1" {
                        Migration.seedLegacyForTesting()
                    }
                    #endif
                    Migration.runIfNeeded()
                    BlockStore.shared.reload()
                    AppGroupStore.shared.reload()
                    SchedulingManager.shared.reapplyAllSchedules()
                    UsageLimitManager.shared.reapplyAllUsageLimits()
                    UsageLimitManager.shared.reconcileExpiredLocks()
                    CooldownManager.shared.restoreActiveCooldownsIfAny()
                    BreakManager.shared.restoreActiveBreaksIfAny()
                    #if DEBUG
                    TestHarness.seedDemoStateIfRequested()
                    TestHarness.runIfEnabled()
                    #endif
                }
        }
    }
}
