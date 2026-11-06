import XCTest
@MainActor final class BlockingReliabilityTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["BLOCK_SEED_DEMO_STATE"] = "1"
        app.launchEnvironment["BLOCK_RUN_TEST_HARNESS"] = "1"
        app.launchEnvironment["TYRI_UI_REVIEW"] = "tracking"
        app.launch()
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    func testBlockNowExplainsMissingAuthorization() {
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 10))
        for _ in 0..<7 where !app.buttons["open-block-Doomscroll guard"].isHittable { app.swipeUp() }
        app.buttons["open-block-Doomscroll guard"].tap()
        XCTAssertTrue(app.textFields["Block name"].waitForExistence(timeout: 10))
        let toggle=app.switches["Block now"]
        for _ in 0..<6 where !toggle.isHittable {app.swipeUp()}
        XCTAssertTrue(toggle.exists)
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        capture("block-now-toggle")
        XCTAssertEqual(toggle.value as? String, "1")
        for _ in 0..<8 where !app.buttons["save-block"].isHittable { app.swipeUp() }
        app.buttons["save-block"].tap()
        let alert = app.alerts["Couldn’t start blocking"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Allow Screen Time access in Settings before using Block now."].exists)
        capture("block-now-authorization-error")
    }
    func testActiveActionsAppearBeforeConfiguration() {
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TYRI_UI_REVIEW")
        app.launch()
        let row = app.buttons["open-block-Doomscroll guard"]
        for _ in 0..<7 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.textFields["Block name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Stop early…"].isHittable)
        capture("active-actions-simulated-lock-no-authorization")
    }
    func testDiagnosticsAvailableWithoutDebugMenu() {
        app.buttons["Settings"].tap()
        app.buttons["Blocking diagnostics"].tap()
        let report=app.staticTexts["blocking-diagnostics-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("Authorization:"))
        XCTAssertTrue(report.label.contains("Settings readback is not proof of effective shielding."))
        XCTAssertTrue(app.buttons["Share diagnostics"].exists)
        capture("blocking-diagnostics")
    }
}
