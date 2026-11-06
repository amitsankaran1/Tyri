import XCTest

@MainActor
final class DurationTests: XCTestCase {
    func testDurationRangeCancellationAndPersistence() {
        let app = XCUIApplication()
        app.launchEnvironment["BLOCK_SEED_DEMO_STATE"] = "1"
        app.launchEnvironment["BLOCK_RUN_TEST_HARNESS"] = "1"
        app.launchEnvironment["TYRI_UI_REVIEW"] = "tracking"
        app.launch()
        for _ in 0..<7 where !app.buttons["open-block-Doomscroll guard"].isHittable { app.swipeUp() }
        app.buttons["open-block-Doomscroll guard"].tap()
        XCTAssertTrue(app.textFields["Block name"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["usage-duration"].tap()
        XCTAssertTrue(app.navigationBars["Allow usage for"].waitForExistence(timeout: 5))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "0 hr")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "5 min")
        XCTAssertEqual(app.staticTexts["duration-preview"].label, "00:05")
        capture("duration-minimum", app)
        app.buttons["Done"].tap()
        app.buttons["lock-duration"].tap()
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "23 hr")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "55 min")
        XCTAssertEqual(app.staticTexts["duration-preview"].label, "23:55")
        capture("duration-maximum", app)
        app.buttons["Done"].tap()
        app.buttons["lock-duration"].tap()
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "0 hr")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "5 min")
        app.navigationBars["Then block for"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["23:55"].exists)
        capture("duration-settings", app)
        app.buttons["Save"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "BLOCK_SEED_DEMO_STATE")
        app.launch()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["open-block-Doomscroll guard"].isHittable { app.swipeUp() }
        for _ in 0..<7 where !app.buttons["open-block-Doomscroll guard"].isHittable { app.swipeUp() }
        app.buttons["open-block-Doomscroll guard"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["00:05"].exists)
        XCTAssertTrue(app.staticTexts["23:55"].exists)
        capture("duration-persisted", app)
    }

    func testReportedUsageAndLiveBlockedCounter() {
        let app = XCUIApplication()
        app.launchEnvironment["BLOCK_SEED_DEMO_STATE"] = "1"
        app.launchEnvironment["BLOCK_RUN_TEST_HARNESS"] = "1"
        app.launchEnvironment["TYRI_UI_REVIEW"] = "tracking"
        app.launch()
        XCTAssertTrue(app.staticTexts["9 of 30 min used"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Last reported by iOS · updates about every 1 min"].exists)
        capture("usage-reported-fixture", app)
        app.terminate()
        app.launchEnvironment["TYRI_UI_REVIEW"] = "locked"
        app.launch()
        let counter = app.staticTexts["lock-elapsed"].firstMatch
        for _ in 0..<5 where !counter.exists { app.swipeUp() }
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        let first = counter.label
        let changed = NSPredicate { _, _ in counter.label != first }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        capture("lock-counting-up-fixture", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
