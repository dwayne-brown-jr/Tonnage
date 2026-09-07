import XCTest

/// End-to-end smoke tests for the critical flows. They launch with `-uitesting`, which (in a
/// DEBUG build, handled in RootView) bypasses the first-run onboarding gates and seeds demo
/// data — so these run deterministically against a populated app.
///
/// ── ONE-TIME SETUP (Xcode GUI) ───────────────────────────────────────────────────────────
/// This file isn't in a target yet. In Xcode: File ▸ New ▸ Target… ▸ "UI Testing Bundle",
/// name it `TonnageUITests`, set the test host to the Tonnage app, point the target's folder
/// at this directory, and enable it in the Tonnage scheme's Test action. Then it runs via
/// `xcodebuild test -scheme Tonnage -destination 'platform=iOS Simulator,name=…'`.
/// ─────────────────────────────────────────────────────────────────────────────────────────
final class TonnageUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }

    @MainActor
    func testLaunchesToTrainWithoutCrashing() throws {
        let app = launchedApp()
        XCTAssertTrue(app.staticTexts["TRAIN"].waitForExistence(timeout: 10),
                      "App should launch straight to TRAIN under -uitesting (no crash, no gate)")
    }

    @MainActor
    func testAllTabsNavigate() throws {
        let app = launchedApp()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10), "Tab bar should appear")
        for (tab, header) in [("Coach", "COACH"), ("Move", "MOVE"), ("Data", "DATA"), ("Train", "TRAIN")] {
            tabs.buttons[tab].tap()
            XCTAssertTrue(app.staticTexts[header].firstMatch.waitForExistence(timeout: 5),
                          "\(header) header should appear after tapping \(tab)")
        }
    }

    @MainActor
    func testDataShowsSeededContent() throws {
        let app = launchedApp()
        app.tabBars.firstMatch.buttons["Data"].tap()
        // Seeded demo data → DATA shows real cards, not the empty state.
        XCTAssertTrue(app.staticTexts["This Week"].waitForExistence(timeout: 5),
                      "DATA should show the This Week card with seeded data")
        XCTAssertFalse(app.staticTexts["No Data Yet"].exists,
                       "DATA should not show the empty state when data is seeded")
    }

    @MainActor
    func testCoachComposerPresent() throws {
        let app = launchedApp()
        app.tabBars.firstMatch.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["COACH"].waitForExistence(timeout: 5))
        // Composer should be present. We don't send a message here — that's a live network
        // call against the proxy and shouldn't run in CI. Validate the entry point exists.
        let hasComposer = app.textFields.firstMatch.waitForExistence(timeout: 5)
            || app.textViews.firstMatch.exists
        XCTAssertTrue(hasComposer, "Coach composer should be present")
    }
}
