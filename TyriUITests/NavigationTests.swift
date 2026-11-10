import XCTest

/// Exercises persistence and active-block restrictions through the native UI.
@MainActor
final class NavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["BLOCK_SEED_DEMO_STATE"] = "1"
        app.launchEnvironment["BLOCK_RUN_TEST_HARNESS"] = "1"
        app.launch()
    }

    private func capture(_ name: String) {
        // The Duo's cover remains `main` even when its inner display is active.
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name)-screen-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func openLists() {
        let tab = app.buttons["Lists"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    func testAdHocBlockSetupAndValidation() throws {
        app.buttons["ad-hoc-block"].tap()
        XCTAssertTrue(app.navigationBars["Block for a while"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start blocking"].isEnabled)
        app.buttons["ad-hoc-list"].tap()
        let social = app.buttons["Social media"]
        XCTAssertTrue(social.waitForExistence(timeout: 5))
        social.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilGone(social))
        app.buttons["ad-hoc-duration"].tap()
        let custom = app.buttons["Custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilGone(custom))
        XCTAssertTrue(app.steppers["custom-block-duration"].waitForExistence(timeout: 5))
        capture("ad-hoc-custom-duration")
        // No authorization bypass: Simulator cannot authorize Screen Time.
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Untitled"].exists)
    }

    func testTemporaryReleaseAppearsWhenWaitEnds() throws {
        app.terminate()
        app.launchEnvironment["TYRI_UI_REVIEW"] = "adhoc-release-wait"
        app.launch()
        app.buttons["ad-hoc-block"].tap()
        XCTAssertTrue(app.navigationBars["Block for a while"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stop early in"].waitForExistence(timeout: 5))
        capture("temporary-release-wait-fixture")
        let release = app.buttons["Release block"]
        XCTAssertTrue(release.waitForExistence(timeout: 20))
        XCTAssertTrue(release.isEnabled)
        capture("temporary-release-ready-fixture")
        release.tap()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
    }

    func testUsageUXReviewStates() throws {
        for (scenario, title) in [("tracking", "Tracking usage"), ("blocking", "Blocking on"), ("break", "On a break"), ("mixed", "Blocking on"), ("off", "Blocking off")] {
            app.terminate()
            app.launchEnvironment["TYRI_UI_REVIEW"] = scenario
            app.launch()
            let header = app.staticTexts["focus-status-title"].firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 10))
            XCTAssertEqual(header.label, title)
            capture("ux-\(scenario)")
            if scenario == "tracking" {
                XCTAssertTrue(app.staticTexts["9 of 30 min used"].exists)
                XCTAssertFalse(app.staticTexts["No active blocks"].exists)
                app.staticTexts["Doomscroll guard"].tap()
                XCTAssertTrue(app.textFields["Block name"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["9 of 30 min used"].exists)
                capture("ux-usage-detail")
                app.swipeUp()
                capture("ux-usage-settings")
                XCTAssertFalse(app.staticTexts["Daily time limit"].exists)
            }
        }
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TYRI_UI_REVIEW")
        app.launch()
        XCTAssertTrue(app.staticTexts["Screen Time access needed"].firstMatch.waitForExistence(timeout: 10))
        capture("ux-permission-required")
    }

    func testWebsiteSaveValidationAndPersistence() throws {
        openLists()
        app.buttons["Add list"].tap()
        app.textFields["List name"].tap()
        app.textFields["List name"].typeText("Website regression")
        let website = app.textFields["Add website (e.g. goodreads.com)"]
        website.tap()
        website.typeText("example..com")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["website-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(website.value as? String, "example..com")
        capture("papercut-invalid-website")
        website.tap()
        website.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "example..com".count))
        website.typeText("https://www.example.com/path?q=1")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Website regression"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        openLists()
        app.staticTexts["Website regression"].tap()
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5))
        capture("papercut-saved-website")
    }

    func testTimedBlockEndVisible() throws {
        app.terminate()
        app.launchEnvironment["TYRI_UI_REVIEW"] = "locked"
        app.launch()
        let endTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unblocks at"))
        XCTAssertGreaterThanOrEqual(endTexts.count, 2, "Banner and row show the timed end")
        XCTAssertFalse(app.staticTexts["Until you stop it"].exists)
        capture("papercut-timed-end")
    }

    func testLifecycleDiagnosticsAndScreenTimeAvailability() throws {
        app.terminate()
        app.launchEnvironment["TYRI_QA_LIFECYCLE"] = "1"
        app.launch()
        app.buttons["Settings"].tap()
        let requests = app.buttons.matching(identifier: "Allow Screen Time access")
        let request = requests.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? requests.firstMatch
        if request.waitForExistence(timeout: 5) {
            request.tap()
            _ = app.alerts.firstMatch.waitForExistence(timeout: 15)
        }
        capture("qa-screen-time-availability")
        print("QA AUTH UI: \(app.debugDescription)")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        capture("qa-safari-available")
        print("QA Safari launched; this does not prove a shield without authorization and a selected token.")
        safari.terminate()
    }

    func testListCreationCancelSaveAndPersistence() throws {
        openLists()
        capture("02-lists-compact")
        app.buttons["Add list"].tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Discard this draft")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Discard this draft"].exists)

        app.buttons["Add list"].tap()
        app.textFields["List name"].tap()
        app.textFields["List name"].typeText("Review list")
        app.buttons["Save"].tap()
        let row = app.staticTexts["Review list"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(app.textFields["List name"].value as? String, "Review list")
        capture("03-list-editor-compact")
        app.buttons["Cancel"].tap()

        // Reopen without reseeding so persistence is actually exercised.
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        openLists()
        XCTAssertTrue(app.staticTexts["Review list"].waitForExistence(timeout: 5))
    }

    func testActiveRuleRemainsProtected() throws {
        capture("01-focus-compact")
        let work = app.staticTexts["Work focus"]
        for _ in 0..<5 where !work.isHittable { app.swipeUp() }
        work.tap()
        let name = app.textFields["Block name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Work focus")
        let list = app.switches["Social media"]
        // Recovery guidance now precedes configuration in the lazy Form.
        for _ in 0..<8 where !list.exists { app.swipeUp() }
        XCTAssertTrue(list.exists)
        XCTAssertFalse(list.isEnabled, "An active block's saved list must not be removable")
        capture("04-active-block-compact")
    }

    func testDraftSurvivesOrientationRequestsAndSettingsRemainReachable() throws {
        openLists()
        app.staticTexts["Social media"].tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" draft")
        let draftValue = name.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(app.textFields["List name"].value as? String, draftValue)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: app.textFields["List name"])
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        capture("05-list-editor-after-orientation-request")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.textFields["List name"].value as? String, draftValue)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Social media"].waitForExistence(timeout: 5))
        app.buttons["Focus"].firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Screen Time"].waitForExistence(timeout: 5))
        capture("06-settings-compact")
    }
    func testSchedulePresetsAndPlainLanguageSettings() throws {
        app.buttons["Add block"].tap()
        let scheduleOption = app.buttons["Schedule"].firstMatch
        XCTAssertTrue(scheduleOption.waitForExistence(timeout: 5))
        let usageOption = app.buttons["Usage limit"].firstMatch
        let tagOption = app.buttons["NFC tag"].firstMatch
        XCTAssertLessThan(scheduleOption.frame.minY, usageOption.frame.minY)
        XCTAssertLessThan(usageOption.frame.minY, tagOption.frame.minY)
        capture("07-create-block-order")
        scheduleOption.tap()
        XCTAssertTrue(app.textFields["Block name"].waitForExistence(timeout: 5))
        let social = app.switches["Social media"]
        social.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(social.value as? String, "1")
        let editSchedule = app.buttons["edit-schedule"]
        XCTAssertTrue(editSchedule.waitForExistence(timeout: 5))
        editSchedule.tap()
        XCTAssertTrue(app.buttons["Every day"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Enable Schedule"].exists)
        app.buttons["Weekends"].tap()
        XCTAssertEqual(app.buttons["schedule-day-1"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["schedule-day-2"].value as? String, "Not selected")
        app.buttons["schedule-day-2"].tap()
        XCTAssertEqual(app.buttons["schedule-day-2"].value as? String, "Selected")
        capture("08-schedule-custom-days")
        app.buttons["Every day"].tap()
        for day in 1...7 { app.buttons["schedule-day-\(day)"].tap() }
        XCTAssertFalse(app.buttons["Done"].isEnabled)
        app.buttons["Weekdays"].tap()
        capture("09-schedule-weekdays")
        app.buttons["Weekends"].tap()
        app.buttons["Done"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["When you need access"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stop early,")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take a break,")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Early disable"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take a break,")).firstMatch.tap()
        app.buttons["5 min"].tap()
        capture("10-access-settings")
        app.swipeDown()
        app.swipeDown()
        app.textFields["Block name"].tap()
        app.textFields["Block name"].typeText("Evening focus")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        // Saving persists the rule, but failed simulator registration keeps
        // its editor open. Recovery now requests permission before retrying.
        let focus = app.navigationBars["Focus"]
        let editor = app.navigationBars["New block"]
        if !waitUntilGone(editor, timeout: 3) {
            XCTAssertTrue(editor.exists)
            let recovery = app.staticTexts["block-recovery-instructions"]
            for _ in 0..<8 where !recovery.isHittable { app.swipeDown() }
            XCTAssertTrue(recovery.waitForExistence(timeout: 5))
            XCTAssertTrue(recovery.label.contains("Allow Screen Time access"))
            XCTAssertFalse(app.buttons["retry-blocking"].exists)
            capture("papercut-schedule-error")
            app.navigationBars["New block"].buttons["Cancel"].tap()
        }
        XCTAssertTrue(waitUntilGone(editor))
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        // The status cards make this saved row fall below the initial viewport.
        for _ in 0..<5 {
            if app.staticTexts["Evening focus"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Evening focus"].isHittable)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        // The status cards make this saved row fall below the initial viewport.
        for _ in 0..<5 {
            if app.staticTexts["Evening focus"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Evening focus"].isHittable)
        app.staticTexts["Evening focus"].tap()
        for _ in 0..<5 {
            if app.buttons["edit-schedule"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["edit-schedule"].isHittable)
        XCTAssertTrue(app.buttons["edit-schedule"].label.contains("Weekends"))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Take a break, 5 min"].exists)
    }

}
