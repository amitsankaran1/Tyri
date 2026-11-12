import XCTest

/// Simulator UI evidence. DEBUG fixtures contain no Screen Time picker tokens;
/// these tests do not establish real shielding or NFC hardware behavior.
@MainActor final class StabilityReviewTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    private func launch(_ scenario: String? = nil, largeText: Bool = false) {
        app.launchEnvironment = ["BLOCK_SEED_DEMO_STATE": "1", "BLOCK_RUN_TEST_HARNESS": "1"]
        if let scenario { app.launchEnvironment["TYRI_UI_REVIEW"] = scenario }
        if largeText { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 15))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "review-fix-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func scroll(_ element: XCUIElement) {
        for _ in 0..<9 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func openTag() {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "NFC tag")).firstMatch
        scroll(row); row.tap()
        XCTAssertTrue(app.navigationBars["NFC tag"].waitForExistence(timeout: 5))
    }
    func testTagDisconnectRequiresConfirmationAndRefusesActiveBlock() {
        launch()
        app.buttons["Settings"].firstMatch.tap()
        openTag()
        let disconnect = app.buttons["Disconnect tag"].firstMatch
        XCTAssertTrue(disconnect.isEnabled)
        disconnect.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("disconnect-confirmation")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let debug = app.buttons["Debug menu"]
        scroll(debug); debug.tap()
        let scan = app.buttons["Simulate registered tag scan (toggle)"]
        scroll(scan); scan.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Return to the top of Settings after the debug scroll.
        app.swipeDown(); app.swipeDown()
        openTag()
        XCTAssertFalse(disconnect.isEnabled)
        XCTAssertTrue(app.staticTexts["Stop your tag blocks with your current tag or Emergency Access before disconnecting it."].exists)
        capture("active-tag-disconnect-disabled-simulated-scan")
    }
    func testUnreadableDataKeepsSettingsAndEmergencyAccessReachable() {
        launch("unreadable")
        XCTAssertTrue(app.buttons["Settings"].firstMatch.isHittable)
        XCTAssertFalse(app.buttons["Create your first block"].exists)
        capture("unreadable-data-focus-fixture")
        app.buttons["Settings"].firstMatch.tap()
        let challenge = app.buttons["Start typing challenge"]
        scroll(challenge); challenge.tap()
        XCTAssertTrue(app.navigationBars["Emergency Access"].waitForExistence(timeout: 5))
        let response = app.textViews["Type the passage"]
        response.tap(); response.typeText("X am")
        XCTAssertTrue(app.staticTexts["Check character 1: expected ‘i’, found ‘x’."].exists)
        XCTAssertFalse(app.buttons["Disable blocking"].isEnabled)
        capture("emergency-access-mismatch-fixture")
    }
    func testPendingTemporarySessionIsNotShownAsBlocking() {
        launch("adhoc-pending")
        XCTAssertTrue(app.staticTexts["Waiting for confirmation"].waitForExistence(timeout: 5))
        let row = app.buttons["ad-hoc-block"]
        scroll(row)
        XCTAssertTrue(row.label.contains("Waiting for iOS"))
        capture("pending-temporary-session-fixture")
    }
    func testReadableDurationsAndExpandedDiagnostics() {
        launch("tracking-pending")
        let row = app.buttons["open-block-Doomscroll guard"]
        scroll(row); row.tap()
        let duration = app.buttons["usage-duration"]
        scroll(duration)
        XCTAssertEqual(duration.value as? String, "30 min")
        XCTAssertEqual(app.buttons["lock-duration"].value as? String, "3 hr")
        capture("duration-units-and-single-exit-fixture")
        app.buttons["Cancel"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let diagnostics = app.buttons["Blocking diagnostics"]
        scroll(diagnostics); diagnostics.tap()
        let report = app.staticTexts["blocking-diagnostics-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label CONTAINS %@", "Temporary session:")
        expectation(for: ready, evaluatedWith: report)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(report.label.contains("Break awaiting confirmation:"))
        XCTAssertTrue(report.label.contains("Screen Time is not authorized"))
        capture("expanded-diagnostics-fixture")
    }
    func testLargestTextBreakCountdown() {
        launch("break", largeText: true)
        let countdown = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Resumes in")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        capture("largest-text-break-countdown-fixture")
    }
}
