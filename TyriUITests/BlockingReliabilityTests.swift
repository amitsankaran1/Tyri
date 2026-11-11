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
    func testBackgroundResumePreservesEditorAfterRefreshInterval() {
        let row = app.buttons["open-block-Doomscroll guard"]
        for _ in 0..<7 where !row.isHittable { app.swipeUp() }
        row.tap()
        let name = app.textFields["Block name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText(" resume draft")
        let draft = name.value as? String
        capture("suspension-before-home-simulator-fixture")
        XCUIDevice.shared.press(.home)
        // Longer than both 30-second periodic recovery timers.
        let elapsed = expectation(description: "background refresh interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 40)
        app.activate()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, draft, "Unsaved editor state survives without relaunch")
        capture("suspension-after-resume-simulator-fixture")
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertEqual(name.value as? String, draft)
        }
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
    func testTemporarySessionShowsEnforcementFailure() {
        app.terminate()
        app.launchEnvironment["TYRI_UI_REVIEW"] = "adhoc-error"
        app.launch()
        let row = app.buttons["ad-hoc-block"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.staticTexts["Blocking needs attention"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["temporary-session-error"].exists || app.staticTexts["temporary-session-error"].exists)
        capture("temporary-session-error-empty-token-fixture")
    }
    func testNeedsAttentionProvidesRecoveryAndListLink() {
        app.terminate()
        app.launchEnvironment["TYRI_UI_REVIEW"] = "attention"
        app.launch()
        let row = app.buttons["open-block-Doomscroll guard"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["View recovery steps"].exists)
        capture("attention-home-presentation-fixture")
        row.tap()
        let instructions = app.staticTexts["block-recovery-instructions"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertTrue(instructions.label.contains("Select apps"))
        XCTAssertTrue(app.buttons["Retry blocking"].exists)
        capture("attention-recovery-empty-selection-fixture")
        app.buttons["Edit Social media"].tap()
        XCTAssertTrue(app.navigationBars["List details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select apps"].exists)
        capture("attention-linked-list-fixture")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Retry blocking"].waitForExistence(timeout: 5))
        app.buttons["Retry blocking"].tap()
        XCTAssertTrue(app.buttons["Allow Screen Time access"].waitForExistence(timeout: 5))
        capture("attention-retry-permission-recovery-simulator")
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
