import XCTest
@testable import PulseCore

final class PerformanceEngineTests: XCTestCase {
    func testStrainScoreNeverExceedsDashboardScale() {
        XCTAssertEqual(StrainEngine.score(rawLoad: 0, history: [100, 110, 120]), 0)
        XCTAssertLessThanOrEqual(StrainEngine.score(rawLoad: 100_000, history: [100, 110, 120]), 100)
        XCTAssertGreaterThanOrEqual(StrainEngine.score(rawLoad: .nan, history: [100, 110, 120]), 0)
    }

    func testStressReadsHeartRateReserveAndCannotPin() {
        let hrvBaseline = Baseline(median: 45, mad: 5, count: 14)
        func stress(_ hr: Double, movement: Double = 0) -> Double? {
            StressEngine.calculate(hr: hr, resting: 55, maximum: 185, hrv: nil,
                                   hrvBaseline: hrvBaseline, movement: movement, workout: false)
        }
        // At rest the reading sits near the floor, not near the ceiling.
        let atRest = stress(58)
        XCTAssertNotNil(atRest)
        XCTAssertLessThan(atRest!, 15)

        // It rises with reserve and stays inside the scale at the extreme.
        XCTAssertLessThan(stress(58)!, stress(85)!)
        XCTAssertLessThan(stress(85)!, stress(130)!)
        XCTAssertLessThanOrEqual(stress(220)!, 100)

        // Regression: the previous version compared the day's heart rate to a
        // resting baseline, saturating the ±3 bound and pinning the result at
        // 30 + 3 × 22 = 96 all day. Ordinary waking rates must not do that.
        for rate in [70.0, 75, 80, 90, 100] {
            XCTAssertLessThan(stress(rate)!, 90, "\(rate) bpm should not read as extreme activation")
        }

        // Movement explains a raised rate, so it lowers the reading.
        XCTAssertLessThan(stress(95, movement: 1)!, stress(95, movement: 0)!)

        // Workouts are effort, not activation.
        XCTAssertNil(StressEngine.calculate(hr: 150, resting: 55, maximum: 185, hrv: nil,
                                            hrvBaseline: nil, movement: 0, workout: true))
        // Without a resting reference or a usable maximum there is no reserve.
        XCTAssertNil(StressEngine.calculate(hr: 80, resting: nil, maximum: 185, hrv: nil,
                                            hrvBaseline: nil, movement: 0, workout: false))
        XCTAssertNil(StressEngine.calculate(hr: 80, resting: 55, maximum: 60, hrv: nil,
                                            hrvBaseline: nil, movement: 0, workout: false))
    }

    /// The day's account must come from the level actually reached, because the
    /// modelled terms and the drawn line diverge wherever the value clamps.
    func testEnergySummaryReadsTheLevelsNotTheModelledTerms() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func point(_ minute: Int, _ value: Double, asleep: Bool = false) -> EnergyPoint {
            .init(date: start.addingTimeInterval(Double(minute) * 60), value: value, asleep: asleep)
        }
        let summary = EnergySummaryEngine.summarise([
            point(0, 30, asleep: true), point(15, 50, asleep: true), point(30, 70, asleep: true),
            point(45, 60), point(60, 55), point(75, 65)
        ])
        XCTAssertEqual(summary.charged, 50, accuracy: 0.001)   // 20 + 20 + 10
        XCTAssertEqual(summary.spent, 15, accuracy: 0.001)     // 10 + 5
        // The final run is still open, so its peak is the current level.
        XCTAssertEqual(summary.lastChargePeak, 65)
        XCTAssertEqual(summary.sleepSpan?.lowerBound, start)
        XCTAssertEqual(summary.chargingSpans.count, 2)

        XCTAssertEqual(EnergySummaryEngine.summarise([]).charged, 0)
    }

    func testWellnessAgeRequiresActualObservedSignals() {
        // Chronological age alone is not an estimate.
        XCTAssertNil(WellnessAgeEngine.calculate(inputs: .init(chronologicalAge: 35, biologicalSex: "male")))
        // Nor is a signal without a declared age.
        XCTAssertNil(WellnessAgeEngine.calculate(inputs: .init(chronologicalAge: nil, biologicalSex: "male", sleepScores: [80], steps: [9_000])))

        let result = WellnessAgeEngine.calculate(inputs: .init(
            chronologicalAge: 35, biologicalSex: "male",
            restingHeartRate: Array(repeating: 55, count: 14),
            sleepScores: Array(repeating: 82, count: 14),
            steps: Array(repeating: 8_000, count: 14)
        ))
        XCTAssertNotNil(result)
        XCTAssertTrue((18...100).contains(result!.age))
        // Absent signals are reported as absent rather than silently dropped.
        XCTAssertTrue(result!.contributors.contains { $0.id == "vo2" && $0.score == nil })
        // Without VO2max there is no fitness anchor, and that is stated.
        XCTAssertNil(result!.fitnessAge)
        XCTAssertTrue(result!.report.limitations.contains("confidenceNoFitnessAnchor"))
    }

    /// The anchor of the whole estimate: inverting the published VO2max-by-age
    /// curve. A value equal to the median for an age must return that age.
    func testFitnessAgeInvertsTheReferenceCurve() {
        for age in [25.0, 40, 55, 70] {
            for sex in ["male", "female"] {
                let expected = WellnessAgeEngine.expectedVO2(age: age, sex: sex)
                XCTAssertNotNil(expected)
                let recovered = WellnessAgeEngine.fitnessAge(vo2: expected!, sex: sex)
                XCTAssertNotNil(recovered)
                XCTAssertEqual(recovered!, age, accuracy: 0.01)
            }
        }
        let fit = WellnessAgeEngine.fitnessAge(vo2: 48, sex: "male")!
        let unfit = WellnessAgeEngine.fitnessAge(vo2: 28, sex: "male")!
        XCTAssertLessThan(fit, unfit)
        // Without a declared sex there is no curve to invert.
        XCTAssertNil(WellnessAgeEngine.fitnessAge(vo2: 48, sex: nil))
    }

    func testHighFitnessLowersTheEstimateAndPoorFitnessRaisesIt() {
        func estimate(vo2: Double) -> WellnessAgeEstimate {
            WellnessAgeEngine.calculate(inputs: .init(
                chronologicalAge: 40, biologicalSex: "male",
                vo2: Array(repeating: vo2, count: 42),
                restingHeartRate: Array(repeating: 60, count: 42),
                sleepScores: Array(repeating: 75, count: 42),
                steps: Array(repeating: 7_500, count: 42)
            ))!
        }
        let fit = estimate(vo2: 50), unfit = estimate(vo2: 26)
        XCTAssertLessThan(fit.age, 40)
        XCTAssertGreaterThan(unfit.age, 40)
        XCTAssertNotNil(fit.fitnessAge)
        // However extreme the input, the estimate stays inside its stated bound.
        XCTAssertLessThanOrEqual(abs(unfit.delta), WellnessAgeEngine.maximumDeviation)
    }

    /// Training and stress must actually move the number: they were the two
    /// signals the previous version ignored entirely.
    func testTrainingAndStressChangeTheEstimate() {
        func estimate(exercise: Double, stress: Double) -> WellnessAgeEstimate {
            WellnessAgeEngine.calculate(inputs: .init(
                chronologicalAge: 40, biologicalSex: "male",
                vo2: Array(repeating: 38, count: 42),
                restingHeartRate: Array(repeating: 60, count: 42),
                sleepScores: Array(repeating: 75, count: 42),
                steps: Array(repeating: 7_500, count: 42),
                exerciseMinutes: Array(repeating: exercise, count: 42),
                stress: Array(repeating: stress, count: 42)
            ))!
        }
        XCTAssertLessThan(estimate(exercise: 45, stress: 30).age, estimate(exercise: 5, stress: 30).age)
        XCTAssertLessThan(estimate(exercise: 25, stress: 25).age, estimate(exercise: 25, stress: 70).age)
    }

    func testWellnessAgeAnswersFromTheFirstDayWithLowConfidence() {
        func estimate(days: Int) -> WellnessAgeEstimate {
            WellnessAgeEngine.calculate(inputs: .init(
                chronologicalAge: 40, biologicalSex: "male",
                vo2: Array(repeating: 30, count: days),
                sleepScores: Array(repeating: 55, count: days),
                steps: Array(repeating: 3_000, count: days)
            ))!
        }
        let oneDay = estimate(days: 1), sixWeeks = estimate(days: 42)
        // A single day answers, but with little confidence and a wide range.
        XCTAssertLessThan(oneDay.report.percent, 30)
        XCTAssertGreaterThan(oneDay.margin, sixWeeks.margin)
        // The correction is scaled by confidence, so one day barely moves the
        // estimate away from the chronological age.
        XCTAssertLessThan(abs(oneDay.delta), abs(sixWeeks.delta))
        XCTAssertGreaterThan(sixWeeks.report.percent, oneDay.report.percent)
    }

    func testConfidenceFallsWithMissingSignalsShortHistoryAndStaleData() {
        let complete = [Contributor("a", score: 50, weight: 50), Contributor("b", score: 50, weight: 50)]
        let partial = [Contributor("a", score: 50, weight: 50), Contributor("b", score: nil, weight: 50)]

        let mature = ConfidenceEngine.evaluate(contributors: complete, observations: 42)
        XCTAssertGreaterThan(mature.percent, 90)
        XCTAssertTrue(mature.limitations.isEmpty)

        let missing = ConfidenceEngine.evaluate(contributors: partial, observations: 42)
        XCTAssertLessThan(missing.percent, mature.percent)
        XCTAssertTrue(missing.limitations.contains("confidenceMissingSignals"))

        let young = ConfidenceEngine.evaluate(contributors: complete, observations: 3)
        XCTAssertLessThan(young.percent, 40)
        XCTAssertTrue(young.limitations.contains("confidenceShortHistory"))

        let stale = ConfidenceEngine.evaluate(contributors: complete, observations: 42, ageInDays: 5)
        XCTAssertLessThan(stale.percent, mature.percent)
        XCTAssertTrue(stale.limitations.contains("confidenceStaleData"))

        // Bands follow the percentage, so the old enum keeps working.
        XCTAssertEqual(ConfidenceEngine.level(for: 95), .high)
        XCTAssertEqual(ConfidenceEngine.level(for: 10), .insufficient)
    }

    func testHeartRateZonesFollowThePersonalMaximum() {
        // The same heart rate is a different zone for different athletes; the
        // reader used to hardcode 185 bpm for everyone.
        let lower = HeartRateZoneEngine.zone(heartRate: 150, resting: 50, maximum: 170)
        let higher = HeartRateZoneEngine.zone(heartRate: 150, resting: 50, maximum: 200)
        XCTAssertNotNil(lower)
        XCTAssertNotNil(higher)
        XCTAssertGreaterThan(lower!, higher!)
    }

    func testOvernightHeartRateDipIsMeasuredAgainstWakingHours() {
        let dip = SleepEngine.heartRateDip(nightly: [48, 50, 52, 49], waking: [70, 74, 68, 72])
        XCTAssertNotNil(dip)
        XCTAssertGreaterThan(dip!, 25)
        // No dip when the night is not lower than the day.
        XCTAssertNil(SleepEngine.heartRateDip(nightly: [80], waking: [70, 72]))
        XCTAssertNil(SleepEngine.heartRateDip(nightly: [], waking: [70]))
    }

    func testStrengthWorkCountsTowardsStrain() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let batch = HealthBatch(vitals: [Vital(id: "steps", value: 4_000, unit: "steps", date: day)])
        let without = DailyEngine.calculate(date: day, batch: batch, history: [], calendar: calendar, now: day.addingTimeInterval(86_400))
        let with = DailyEngine.calculate(date: day, batch: batch, history: [], context: DailyContext(strengthLoad: 120),
                                         calendar: calendar, now: day.addingTimeInterval(86_400))
        XCTAssertNotNil(with.rawLoad)
        XCTAssertGreaterThan(with.rawLoad!, without.rawLoad ?? 0)
        XCTAssertGreaterThan(with.score(.strain).value ?? 0, without.score(.strain).value ?? 0)
    }
}
