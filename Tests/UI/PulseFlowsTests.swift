import XCTest

final class PulseFlowsTests: XCTestCase {
    @MainActor func testBatteryDetailOpensFromHome() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["battery-detail"].waitForExistence(timeout: 15))
        app.buttons["battery-detail"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Cerrar"].firstMatch.tap()
    }

    @MainActor func testCoreNavigationAcrossTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["score-recovery"].waitForExistence(timeout: 15))
        app.buttons["score-recovery"].tap()
        XCTAssertTrue(app.navigationBars["Recuperación"].waitForExistence(timeout: 5))
        app.buttons["Cerrar"].firstMatch.tap()

        // The AI and nutrition tabs are gone; Trends replaced them.
        XCTAssertFalse(app.tabBars.buttons["Nutrición"].exists)
        XCTAssertFalse(app.tabBars.buttons["Inteligencia"].exists)
        app.tabBars.buttons["Tendencias"].tap()
        XCTAssertTrue(app.navigationBars["Tendencias"].waitForExistence(timeout: 5))
    }
}
