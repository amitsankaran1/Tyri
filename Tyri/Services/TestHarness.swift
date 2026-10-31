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
import ManagedSettings

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
            b.schedule = BlockingSchedule(startHour: 0, startMinute: 0, endHour: 0, endMinute: 0, weekdays: Set(1...7))
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

    /// Exercise actual shared-state recovery, independent of extension delivery.
    private static func runScheduleRegressionChecks() {
        var block = BlockRule(name: "Schedule regression", type: .schedule)
        block.schedule = BlockingSchedule(startHour: 0, endHour: 0, weekdays: Set(1...7))
        let id = block.id
        let suite = SharedDefaults.suite
        BlockStore.shared.insert(block)
        defer {
            BlockingActuator.end(blockID: id)
            suite.removeObject(forKey: SharedDefaults.Keys.scheduleWindowStart(blockID: id))
            suite.removeObject(forKey: SharedDefaults.Keys.scheduleReleasedUntil(blockID: id))
            BlockStore.shared.delete(id: id)
            BlockStore.shared.flush()
        }
        let now = Date()
        let window = block.schedule!.activeWindow(at: now)!
        ScheduleEnforcement.reconcile(blockID: id, now: now)
        precondition(suite.bool(forKey: SharedDefaults.Keys.running(blockID: id)), "Missing callback must recover")
        // A repeated callback / foreground refresh must preserve an active break.
        let breakEnd = now.addingTimeInterval(300)
        suite.set(breakEnd, forKey: SharedDefaults.Keys.breakEnd(blockID: id))
        suite.set(true, forKey: SharedDefaults.Keys.breakUsed(blockID: id))
        ScheduleEnforcement.reconcile(blockID: id, now: now)
        precondition(BreakMonitoring.breakEnd(blockID: id) == breakEnd, "Refresh shortened break")
        precondition(BreakMonitoring.breakUsed(blockID: id), "Refresh reset allowance")
        // Simulate a lost running flag on relaunch, with window identity preserved.
        suite.removeObject(forKey: SharedDefaults.Keys.running(blockID: id))
        ScheduleEnforcement.reconcile(blockID: id, now: now)
        precondition(suite.bool(forKey: SharedDefaults.Keys.running(blockID: id)))
        precondition(BreakMonitoring.breakEnd(blockID: id) == breakEnd)
        ScheduleEnforcement.releaseCurrentWindow(block: block, now: now)
        ScheduleEnforcement.reconcile(blockID: id, now: now)
        ScheduleEnforcement.reconcile(blockID: id, now: now)
        precondition(!suite.bool(forKey: SharedDefaults.Keys.running(blockID: id)), "Early release must survive refresh")
        ScheduleEnforcement.reconcile(blockID: id, now: window.end.addingTimeInterval(1))
        precondition(suite.bool(forKey: SharedDefaults.Keys.running(blockID: id)), "Next window must re-arm")
        precondition(!BreakMonitoring.breakUsed(blockID: id), "Next window gets a fresh break")
        block.schedule = nil
        BlockStore.shared.update(block)
        BlockStore.shared.flush()
        ScheduleEnforcement.reconcile(blockID: id)
        precondition(!suite.bool(forKey: SharedDefaults.Keys.running(blockID: id)), "Removed schedule must clear")
        print("✅ Schedule regression: missing callback, relaunch, break, release, next window, removal passed")
    }

    /// Light launch smoke check: verify the stores round-trip and resolution works.
    static func runIfEnabled() {
        guard isEnabled else { return }
        runScheduleRegressionChecks()
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
