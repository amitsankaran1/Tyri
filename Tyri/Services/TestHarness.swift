//
//  TestHarness.swift
//  Tyri
//
//  Demo-state seeding (BLOCK_SEED_DEMO_STATE=1) and a light launch smoke check
//  (BLOCK_RUN_TEST_HARNESS=1). Compiled out of release builds.
//

#if DEBUG

import Foundation
import FamilyControls

@MainActor
enum TestHarness {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BLOCK_RUN_TEST_HARNESS"] == "1"
    }

    static var seedDemoState: Bool {
        ProcessInfo.processInfo.environment["BLOCK_SEED_DEMO_STATE"] == "1"
    }

    /// Populate representative groups + blocks so screenshots cover data-rich UI.
    /// Idempotent (wipes prior blocks/groups first). Apps are empty — the Simulator
    /// can't synthesize ApplicationTokens — but the rules, state, and UI are real.
    static func seedDemoStateIfRequested() {
        guard seedDemoState else { return }

        DebugSimulator.resetAllRuntime()
        for block in BlockStore.shared.blocks { BlockStore.shared.delete(id: block.id) }
        for group in AppGroupStore.shared.groups { AppGroupStore.shared.delete(id: group.id) }

        AppConfigurationStore.shared.registerTag(identifier: "demo-tag-04A3B2C1")

        // Groups
        let social = AppGroupStore.shared.create(name: "Social media")
        let games = AppGroupStore.shared.create(name: "Games")

        // Schedule block (work hours, weekdays) on Social.
        let work = BlockStore.shared.create(name: "Work focus", type: .schedule)
        if var b = BlockStore.shared.block(id: work.id) {
            b.appGroupIDs = [social.id]
            b.schedule = BlockingSchedule(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0, weekdays: [2,3,4,5,6])
            b.cooldownMinutes = 5
            BlockStore.shared.update(b)
        }

        // Timer block on Social.
        let doom = BlockStore.shared.create(name: "Doomscroll guard", type: .timer)
        if var b = BlockStore.shared.block(id: doom.id) {
            b.appGroupIDs = [social.id]
            b.usageLimitMinutes = 30
            b.usageLockMinutes = 180
            b.cooldownMinutes = 5
            BlockStore.shared.update(b)
        }

        // Tag block on Games.
        let gameTag = BlockStore.shared.create(name: "Game break", type: .tag)
        if var b = BlockStore.shared.block(id: gameTag.id) {
            b.appGroupIDs = [games.id]
            BlockStore.shared.update(b)
        }

        BlockStore.shared.flush()
        AppGroupStore.shared.flush()

        // Make one scheduled block active + one usage lock active for the Home screen.
        BlockingActuator.start(blockID: work.id)
        DebugSimulator.fireUsageThreshold(blockID: doom.id)
        SchedulingManager.shared.refresh()
        UsageLimitManager.shared.refresh()

        print("🌱 Seeded demo state: 2 groups, 3 blocks (1 scheduled + 1 usage-locked), tag registered")
    }

    /// Light launch smoke check: verify the stores round-trip and resolution works.
    static func runIfEnabled() {
        guard isEnabled else { return }
        let g = AppGroupStore.shared.create(name: "Harness group")
        let b = BlockStore.shared.create(name: "Harness block", type: .schedule)
        var bb = BlockStore.shared.block(id: b.id)!
        bb.appGroupIDs = [g.id]
        BlockStore.shared.update(bb)
        BlockStore.shared.flush()
        AppGroupStore.shared.flush()

        let resolvedBlock = BlockResolution.loadBlock(id: b.id)
        let groupsLoaded = BlockResolution.loadGroups().contains { $0.id == g.id }
        let ok = resolvedBlock?.appGroupIDs == [g.id] && groupsLoaded

        BlockStore.shared.delete(id: b.id)
        AppGroupStore.shared.delete(id: g.id)
        BlockStore.shared.flush()
        AppGroupStore.shared.flush()

        print(ok ? "✅ TestHarness: store round-trip + resolution OK" : "❌ TestHarness: round-trip FAILED")
    }
}

#endif
