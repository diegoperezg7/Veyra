import XCTest
@testable import PulseCore

/// The breakdown has to explain the number above it: if sleep says it costs
/// half a year, removing half a year of sleep debt has to move the estimate by
/// half a year.
final class AgeEffectTests: XCTestCase {

    private func inputs(sleep: Double = 75, steps: Double = 7_500, rhr: Double = 60) -> WellnessAgeInputs {
        var inputs = WellnessAgeInputs(chronologicalAge: 40, biologicalSex: "male")
        inputs.vo2 = Array(repeating: 42, count: 20)
        inputs.restingHeartRate = Array(repeating: rhr, count: 20)
        inputs.hrv = Array(repeating: 45, count: 20)
        inputs.sleepScores = Array(repeating: sleep, count: 20)
        inputs.steps = Array(repeating: steps, count: 20)
        inputs.exerciseMinutes = Array(repeating: 30, count: 20)
        inputs.stress = Array(repeating: 35, count: 20)
        inputs.bodyFat = Array(repeating: 18, count: 20)
        inputs.sleepOnsets = Array(repeating: 1_380, count: 20)
        return inputs
    }

    func testEffectsSumToTheCorrectionApplied() throws {
        let estimate = try XCTUnwrap(WellnessAgeEngine.calculate(inputs: inputs()))
        let effects = try XCTUnwrap(estimate.effects)
        XCTAssertFalse(effects.isEmpty)
        let sum = effects.reduce(0) { $0 + $1.years }
        XCTAssertEqual(sum, estimate.age - estimate.chronologicalAge, accuracy: 0.0001,
                       "el desglose debe explicar exactamente la diferencia con la edad real")
    }

    func testASignalThatHelpsSubtractsYearsAndOneThatHurtsAddsThem() throws {
        let good = try XCTUnwrap(WellnessAgeEngine.calculate(inputs: inputs(sleep: 95, steps: 12_000, rhr: 48)))
        let bad = try XCTUnwrap(WellnessAgeEngine.calculate(inputs: inputs(sleep: 45, steps: 2_000, rhr: 78)))

        func effect(_ key: String, _ estimate: WellnessAgeEstimate) -> Double {
            estimate.effects?.first { $0.key == key }?.years ?? .nan
        }
        XCTAssertLessThan(effect("sleep", good), 0, "dormir bien debe restar años")
        XCTAssertGreaterThan(effect("sleep", bad), 0, "dormir mal debe sumarlos")
        XCTAssertLessThan(effect("activity", good), effect("activity", bad))
        XCTAssertLessThan(effect("rhr", good), effect("rhr", bad))
        XCTAssertLessThan(good.age, bad.age)
    }

    func testEffectsAreOrderedFromWorstToBest() throws {
        let estimate = try XCTUnwrap(WellnessAgeEngine.calculate(inputs: inputs(sleep: 50, steps: 11_000)))
        let years = try XCTUnwrap(estimate.effects).map(\.years)
        XCTAssertEqual(years, years.sorted(by: >), "lo que más envejece va primero")
    }

    /// An estimate written by an older version has no breakdown, and that must
    /// not stop it decoding — `LocalStore` deletes what it cannot read.
    func testAnEstimateWithoutEffectsStillDecodes() throws {
        let legacy: [String: Any] = [
            "date": 0, "age": 41.0, "chronologicalAge": 40.0, "margin": 2.0,
            "report": ["percent": 70.0, "coverage": 0.8, "maturity": 0.9, "recency": 1.0, "limitations": []],
            "contributors": []
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(WellnessAgeEstimate.self, from: data)
        XCTAssertNil(decoded.effects)
        XCTAssertEqual(decoded.age, 41)
    }
}
