import XCTest

@MainActor
final class OnboardingTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["BLOCK_SEED_DEMO_STATE"] = "1"
        app.launchEnvironment["BLOCK_RUN_TEST_HARNESS"] = "1"
    }
    private func capture(_ name: String) {
        for (i, screen) in XCUIScreen.screens.enumerated() {
            let a = XCTAttachment(screenshot: screen.screenshot())
            a.name = "\(name)-\(i)"; a.lifetime = .keepAlways; add(a)
        }
    }
    private func describe(_ fixture: String) {
        app.launchEnvironment["TYRI_DESCRIPTION_FIXTURE"] = fixture
        app.launch()
        app.buttons["Add block"].tap()
        let action = app.buttons["describe-block-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.textViews["block-description"].waitForExistence(timeout: 5))
        app.buttons["Block Social media and Games weekdays from 9am to 5pm"].tap()
        app.buttons["interpret-description"].tap()
    }
    func testStarterListsAndCancel() {
        app.launch()
        app.buttons["Lists"].firstMatch.tap()
        app.buttons["Build lists with suggestions"].tap()
        XCTAssertTrue(app.navigationBars["Build your lists"].waitForExistence(timeout: 5))
        capture("onboarding-starters")
        app.buttons["starter-Scrollers"].tap()
        XCTAssertTrue(app.textFields["List name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["List name"].value as? String, "Scrollers")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        capture("onboarding-scrollers-ideas")
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Scrollers"].exists)
    }
    func testMissingListReturnsToDraftAndSaves() {
        describe("missing")
        XCTAssertTrue(app.buttons["Create Shopping"].waitForExistence(timeout: 5))
        capture("description-missing-list")
        app.buttons["Create Shopping"].tap()
        XCTAssertTrue(app.textFields["List name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.navigationBars["New list"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Create Shopping"].waitForExistence(timeout: 5))
        app.buttons["Create Shopping"].tap()
        let website=app.textFields["Add website (e.g. goodreads.com)"]
        website.tap(); website.typeText("example.com")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["review-described-block"].waitForExistence(timeout: 5))
        app.buttons["review-described-block"].tap()
        XCTAssertTrue(app.navigationBars["Review block"].waitForExistence(timeout: 5))
        capture("description-review-weekly")
        app.buttons["Save"].tap()
        // Simulator authorization is absent. Configuration can persist, enforcement is not proven.
        app.swipeUp()
        capture("description-saved-simulator-warning")
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
        // Simulator authorization warnings precede the lazily rendered block rows.
        for _ in 0..<6 where !app.staticTexts["Focus time"].firstMatch.exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Focus time"].firstMatch.exists)
        app.buttons["Lists"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Shopping"].waitForExistence(timeout: 5))
        capture("description-list-persisted")
    }
    func testExactUsageAndRotation() {
        describe("usage")
        XCTAssertTrue(app.buttons["review-described-block"].waitForExistence(timeout: 5))
        app.buttons["review-described-block"].tap()
        XCTAssertTrue(app.navigationBars["Review block"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Use apps for 40 min, then block them for 50 min. Repeat after each block ends."].waitForExistence(timeout: 5))
        capture("description-exact-40-50")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Use apps for 40 min, then block them for 50 min. Repeat after each block ends."].exists)
        capture("description-exact-rotated")
        XCUIDevice.shared.orientation = .portrait
        app.navigationBars["Review block"].buttons["Cancel"].tap()
        XCTAssertTrue(app.textViews["block-description"].waitForExistence(timeout: 5))
    }
    func testClarificationAndFailureKeepDescription() {
        describe("clarify")
        XCTAssertTrue(app.staticTexts["Do you mean 9am–11am or 9pm–11pm? Add AM or PM to your description."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review-described-block"].exists)
        capture("description-clarification")
        app.navigationBars["Describe a block"].buttons["Cancel"].tap()
        app.buttons["Discard description"].tap()
        app.terminate()
        describe("failure")
        XCTAssertTrue(app.staticTexts["The model service is unavailable. Your description is still here; retry or use the manual editor."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["block-description"].value as? String, "Block Social media and Games weekdays from 9am to 5pm")
        capture("description-service-failure")
    }
}
