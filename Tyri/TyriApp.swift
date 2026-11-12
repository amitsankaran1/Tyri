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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var nfcManager = NFCManager.shared

    init() {
        AppConfigurationStore.migrateLegacyDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { phase in
                    ForegroundRecovery.shared.setActive(phase == .active)
                }
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
                    CooldownManager.shared.restoreActiveCooldownsIfAny()
                    #if DEBUG
                    TestHarness.seedDemoStateIfRequested()
                    TestHarness.runIfEnabled()
                    #endif
                    ForegroundRecovery.shared.start()
                }
        }
    }
}
