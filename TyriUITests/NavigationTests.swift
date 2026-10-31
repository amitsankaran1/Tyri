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
        app.staticTexts["Work focus"].tap()
        let name = app.textFields["Block name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Work focus")
        let list = app.switches["Social media"]
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
        XCTAssertTrue(app.staticTexts["Evening focus"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        XCTAssertTrue(app.staticTexts["Evening focus"].waitForExistence(timeout: 5))
        app.staticTexts["Evening focus"].tap()
        XCTAssertTrue(app.buttons["edit-schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-schedule"].label.contains("Weekends"))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Take a break, 5 min"].exists)
    }

}
