import XCTest

final class PulseFlowsTests: XCTestCase {
    @MainActor func testBatteryDetailOpensFromHome() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["battery-detail"].waitForExistence(timeout: 15))
        app.buttons["battery-detail"].tap()
        XCTAssertTrue(app.buttons["close-route"].waitForExistence(timeout: 8))
        app.buttons["close-route"].tap()
    }

    /// Regression: the score tiles are plain buttons, so their tappable area is
    /// only the pixels they draw. Before there is a score, the middle of the
    /// ring is empty and a tap in the centre — which is where anyone aims —
    /// went nowhere. This exercises the app with no data for that reason.
    @MainActor func testScoreTileOpensItsDetailBeforeThereIsAnyData() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["score-recovery"].waitForExistence(timeout: 15))
        app.buttons["score-recovery"].tap()
        XCTAssertTrue(app.buttons["close-route"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["Recuperación"].exists)
        app.buttons["close-route"].tap()
    }

    @MainActor func testCoreNavigationAcrossTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["score-recovery"].waitForExistence(timeout: 15))

        // The AI and nutrition tabs are gone; Trends replaced them.
        XCTAssertFalse(app.tabBars.buttons["Nutrición"].exists)
        XCTAssertFalse(app.tabBars.buttons["Inteligencia"].exists)
        app.tabBars.buttons["Tendencias"].tap()
        XCTAssertTrue(app.navigationBars["Tendencias"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Biología"].tap()
        XCTAssertTrue(app.navigationBars["Biología"].waitForExistence(timeout: 5))
    }
}
