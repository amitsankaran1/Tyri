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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertTrue(app.textFields["List name"].isHittable)
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
}
