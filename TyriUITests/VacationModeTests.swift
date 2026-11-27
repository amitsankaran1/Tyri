import XCTest

/// Simulator UI evidence for TSK-174. DEBUG fixtures have no Screen Time tokens
/// or authorization; these tests do not establish real shielding or background
/// resume on a device.
@MainActor final class VacationModeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ["BLOCK_SEED_DEMO_STATE": "1", "BLOCK_RUN_TEST_HARNESS": "1", "TYRI_UI_REVIEW": "vacation"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "vacation-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testStartShowAndEndVacation() {
        let entry = app.buttons["vacation-mode"]
        reveal(entry)
        XCTAssertTrue(entry.label.contains("Pause blocks for vacation"))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Vacation mode"].waitForExistence(timeout: 5))
        // Tag blocks start only from the tag, so they are not offered.
        XCTAssertFalse(app.switches["Game break"].exists)
        let start = app.buttons["start-vacation"]
        XCTAssertFalse(start.isEnabled, "nothing selected yet")
        // Tap the control itself; a row-center tap doesn't flip a labeled switch on iOS 26+.
        app.switches["Doomscroll guard"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        capture("1-choose")
        XCTAssertTrue(start.isEnabled)
        reveal(start)
        start.tap()

        let resume = app.staticTexts["vacation-resume"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5) || app.otherElements["vacation-resume"].exists)
        XCTAssertTrue(app.staticTexts["Doomscroll guard"].exists)
        capture("2-active")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
        let summary = app.buttons["vacation-mode"]
        reveal(summary)
        XCTAssertTrue(summary.label.contains("1 block paused until"), summary.label)
        let paused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "On vacation · Resumes")).firstMatch
        reveal(paused)
        capture("3-home")

        summary.tap()
        let end = app.buttons["end-vacation"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
        reveal(app.buttons["vacation-mode"])
        XCTAssertTrue(app.buttons["vacation-mode"].label.contains("Pause blocks for vacation"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "On vacation")).firstMatch.exists)
    }
}
