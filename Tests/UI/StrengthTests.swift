import XCTest

/// Logging a workout end to end. The screen is built out of custom controls —
/// number fields, a tick, an add-set button — and each of them has to actually
/// do something when pressed.
final class StrengthTests: XCTestCase {
    @MainActor func testLoggingAWorkoutFromEmptyToFinished() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--route", "strength"]
        app.launch()

        XCTAssertTrue(app.buttons["Empezar entrenamiento"].waitForExistence(timeout: 15))
        app.buttons["Empezar entrenamiento"].tap()

        // The empty session opens straight into logging.
        XCTAssertTrue(app.buttons["Añadir ejercicio"].waitForExistence(timeout: 8))
        app.buttons["Añadir ejercicio"].tap()

        // Pick an exercise out of the library by name.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Press de banca")
        let first = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Press de banca'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()

        // One set row appears. Tapping a field selects what is in it, so typing
        // replaces the pre-filled number rather than appending to it.
        let weight = app.textFields["weight-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8), "no apareció la serie")
        weight.tap()
        weight.typeText("60")
        let reps = app.textFields["reps-1"]
        reps.tap()
        reps.typeText("10")
        XCTAssertEqual(reps.value as? String, "10", "escribir debe sustituir el valor, no añadirse a él")

        // Ticking it is what makes it count.
        app.buttons["complete-1"].tap()
        XCTAssertTrue(app.staticTexts["600 kg"].waitForExistence(timeout: 5), "el volumen no recogió la serie")

        // A second set repeats the first rather than starting blank.
        app.buttons["Añadir serie"].tap()
        let second = app.textFields["weight-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(second.value as? String, "60", "la nueva serie debe partir de la anterior")

        let finish = app.buttons["Finalizar y guardar"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        // The confirmation dialog asks before dropping anything unticked. It
        // has to be addressed through `sheets`: the button behind it carries
        // the same label and is the one a plain query resolves to.
        let confirm = app.sheets.buttons["Finalizar y guardar"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sheets.buttons["Descartar entrenamiento"].exists,
                      "el diálogo debe ofrecer descartar")
        confirm.tap()

        // Back on the strength screen, the workout is offered to repeat. The
        // card can sit below the fold once there is a volume summary above it.
        let repeatCard = app.staticTexts["Repetir un entrenamiento"]
        var attempts = 0
        while !repeatCard.exists && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(repeatCard.waitForExistence(timeout: 8),
                      "el entrenamiento terminado no aparece para repetir")
    }
}
