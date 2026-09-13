import XCTest

/// A recorded workout has to be reachable and has to show what a session
/// actually raises: how hard, where the time went, and what it cost.
final class WorkoutDetailTests: XCTestCase {

    @MainActor func testWorkoutDetailShowsTheWholeSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed", "--tab", "fitness"]
        app.launch()

        // Reach the workout list and open the most recent session.
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        let row = app.staticTexts["Carrera"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "la lista de entrenamientos no aparece")
        row.tap()

        XCTAssertTrue(app.staticTexts["Intensidad"].waitForExistence(timeout: 10),
                      "el detalle no abre")
        // Everything the screen exists for, in the order it is laid out.
        for section in ["Frecuencia cardíaca", "Tiempo en zonas", "Foco cardiovascular",
                        "Impacto cardiovascular", "Recuperación cardíaca",
                        "Detalle del entrenamiento", "Fuente"] {
            var attempts = 0
            while !app.staticTexts[section].exists && attempts < 6 {
                app.swipeUp()
                attempts += 1
            }
            XCTAssertTrue(app.staticTexts[section].exists, "falta la sección «\(section)»")
        }
        // The zone breakdown covers zone 0 through 5.
        for zone in 0...5 {
            XCTAssertTrue(app.staticTexts["Z\(zone)"].firstMatch.exists, "falta la zona Z\(zone)")
        }
        // And the source is named, which is how you tell where it came from.
        XCTAssertTrue(app.staticTexts["Apple Watch de Diego"].exists)
    }

    /// The complaint that started this: a finished workout was nowhere to be
    /// seen from the screen you land on.
    @MainActor func testTodaysWorkoutIsReachableFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed", "--tab", "home"]
        app.launch()
        let card = app.staticTexts["Entrenamiento de hoy"]
        var attempts = 0
        while !card.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "el entrenamiento de hoy no aparece en Inicio")
    }
}
