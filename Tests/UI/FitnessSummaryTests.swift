import XCTest

/// Fitness has to answer, without opening anything: did I train this month, how
/// much, what did I lift and am I getting stronger.
final class FitnessSummaryTests: XCTestCase {

    @MainActor func testFitnessShowsTheMonthAndTheStrengthSummary() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed", "--tab", "fitness"]
        app.launch()

        func reach(_ label: String, scrolls: Int = 8) -> Bool {
            var attempts = 0
            while !app.staticTexts[label].exists && attempts < scrolls {
                app.swipeUp()
                attempts += 1
            }
            return app.staticTexts[label].exists
        }

        XCTAssertTrue(app.staticTexts["Calendario de actividad"].waitForExistence(timeout: 15))
        XCTAssertTrue(reach("Resumen de la actividad"), "falta el resumen de la actividad")
        XCTAssertTrue(reach("Volumen total"), "falta el volumen por grupo muscular")

        // The volume has to be real, not a row of zeroes: that was the symptom
        // of the exercise catalogue not being loaded on this screen.
        let zeroes = app.staticTexts.matching(NSPredicate(format: "label == '0 kg'")).count
        XCTAssertLessThan(zeroes, 6, "el volumen por grupo sale todo a cero")

        XCTAssertTrue(reach("Progreso de fuerza"), "falta el progreso de fuerza")
        // Exercises are named, not shown as identifiers.
        XCTAssertTrue(app.staticTexts["Press de banca"].exists
                      || app.staticTexts["Prensa de piernas"].exists,
                      "los ejercicios deben aparecer con su nombre")
    }
}
