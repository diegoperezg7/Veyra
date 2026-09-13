import XCTest

/// The journal switches are custom controls, and a custom control that looks
/// pressable but is not is worse than a plain one. These press them.
final class JournalTests: XCTestCase {
    @MainActor func testHabitSwitchRecordsYesNoAndBackToUnrecorded() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--route", "journal"]
        app.launch()

        let alcohol = app.otherElements["habit-alcohol"]
        XCTAssertTrue(alcohol.waitForExistence(timeout: 15))
        let yes = alcohol.buttons.element(boundBy: 1)
        let no = alcohol.buttons.element(boundBy: 0)

        // Nothing is answered yet, so the counter is absent.
        XCTAssertFalse(app.staticTexts["1"].exists)
        yes.tap()
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 3), "el + no registró el hábito")
        no.tap()
        XCTAssertTrue(app.staticTexts["1"].exists, "cambiar de + a − no debe cambiar el recuento")
        // Pressing the lit side again clears it.
        no.tap()
        XCTAssertFalse(app.staticTexts["1"].waitForExistence(timeout: 2), "volver a pulsar − debe dejarlo sin registrar")
    }
}
