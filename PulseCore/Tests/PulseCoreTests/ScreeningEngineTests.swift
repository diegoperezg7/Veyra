import XCTest
@testable import PulseCore

final class ScreeningEngineTests: XCTestCase {
    func testTemperatureNeedsABaselineBeforeItReportsADeviation() {
        XCTAssertNil(TemperatureDeviationEngine.calculate(nightly: [36.1, 36.2, 36.0]))
        let stable = [36.1, 36.2, 36.0, 36.1, 36.15, 36.05]
        let result = TemperatureDeviationEngine.calculate(nightly: stable, latest: 36.1)
        XCTAssertEqual(result?.deviation ?? 9, 0, accuracy: 0.1)
        XCTAssertEqual(result?.band, "temperatureTypical")
        XCTAssertFalse(result?.unusual ?? true)

        let fever = TemperatureDeviationEngine.calculate(nightly: stable, latest: 37.5)
        XCTAssertEqual(fever?.band, "temperatureMarked")
        XCTAssertTrue(fever?.unusual ?? false)
    }

    func testBreathingDisturbancesFollowTheThresholdSuppliedByHealthKit() {
        XCTAssertEqual(BreathingDisturbanceEngine.classify(1.0, elevatedFrom: 1.5), "breathingNotElevated")
        XCTAssertEqual(BreathingDisturbanceEngine.classify(2.0, elevatedFrom: 1.5), "breathingElevated")
        // One night is never enough to report a pattern.
        XCTAssertNil(BreathingDisturbanceEngine.monthly(nightly: [3, 3], elevatedFrom: 1.5))
        let month = BreathingDisturbanceEngine.monthly(nightly: Array(repeating: 3.0, count: 20) + Array(repeating: 0.5, count: 10), elevatedFrom: 1.5)
        XCTAssertEqual(month?.elevatedNights, 20)
        XCTAssertTrue(month?.persistent ?? false)
    }

    func testMidSleepAveragesOnTheClockFaceNotTheNumberLine() {
        let calendar = Calendar(identifier: .gregorian)
        func night(day: Int, asleepAt hour: Int, minute: Int, hours: Double) -> SleepSession {
            var components = DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)
            components.timeZone = TimeZone(identifier: "UTC")
            var c = calendar
            c.timeZone = TimeZone(identifier: "UTC")!
            let start = c.date(from: components)!
            return SleepSession(segments: [.init(start: start, end: start.addingTimeInterval(hours * 3600), stage: .core)])
        }
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Asleep 23:00–07:00 every night: mid-sleep is 03:00, which a plain
        // mean of minutes-after-midnight would put at around 13:00.
        let sessions = (1...8).map { night(day: $0, asleepAt: 23, minute: 0, hours: 8) }
        let result = ChronotypeEngine.calculate(sessions: sessions, calendar: utc)
        XCTAssertEqual(result?.midSleep ?? 0, 180, accuracy: 5)
        XCTAssertEqual(result?.band, "chronotypeModeratelyEarly")

        let late = (1...8).map { night(day: $0, asleepAt: 3, minute: 0, hours: 8) }
        XCTAssertEqual(ChronotypeEngine.calculate(sessions: late, calendar: utc)?.band, "chronotypeModeratelyLate")
        XCTAssertNil(ChronotypeEngine.calculate(sessions: Array(sessions.prefix(3)), calendar: utc))
    }

    func testAtrialFibrillationBandsFollowKPRhythmTertiles() {
        XCTAssertEqual(AtrialFibrillationEngine.band(0.5)?.key, "afibMinimal")
        XCTAssertEqual(AtrialFibrillationEngine.band(6)?.key, "afibLow")
        XCTAssertEqual(AtrialFibrillationEngine.band(11.4)?.key, "afibHigh")
        XCTAssertEqual(AtrialFibrillationEngine.band(100)?.key, "afibHigh")
        XCTAssertNil(AtrialFibrillationEngine.band(.nan))
    }

    func testWalkingSteadinessUsesApplesOwnThresholds() {
        XCTAssertEqual(WalkingSteadinessEngine.classify(60, lowFrom: 50, veryLowFrom: 40), "steadinessOK")
        XCTAssertEqual(WalkingSteadinessEngine.classify(45, lowFrom: 50, veryLowFrom: 40), "steadinessLow")
        XCTAssertEqual(WalkingSteadinessEngine.classify(30, lowFrom: 50, veryLowFrom: 40), "steadinessVeryLow")
    }

    func testBloodPressureReportsBothGuidelines() {
        let normal = BloodPressureEngine.classify(systolic: 115, diastolic: 72)
        XCTAssertEqual(normal?.band, "bpNormal")
        XCTAssertEqual(normal?.europeanBand, "bpEuropeanOptimal")

        // The case the two guidelines disagree on: 135/85 is stage 1
        // hypertension in the United States and high-normal in Europe.
        let contested = BloodPressureEngine.classify(systolic: 135, diastolic: 85)
        XCTAssertEqual(contested?.band, "bpStage1")
        XCTAssertEqual(contested?.europeanBand, "bpEuropeanHighNormal")

        // The category takes the higher of the two numbers.
        XCTAssertEqual(BloodPressureEngine.classify(systolic: 118, diastolic: 95)?.band, "bpStage2")
        XCTAssertTrue(BloodPressureEngine.classify(systolic: 185, diastolic: 95)?.crisis ?? false)
        XCTAssertNil(BloodPressureEngine.classify(systolic: 80, diastolic: 120))

        // One reading never makes a category.
        XCTAssertNil(BloodPressureEngine.average(systolic: [120, 122], diastolic: [78, 80]))
        XCTAssertEqual(BloodPressureEngine.average(systolic: [120, 124, 122], diastolic: [78, 80, 79])?.band, "bpElevated")
    }

    func testVO2PercentileIsCentredOnTheReferenceCurve() {
        let median = WellnessAgeEngine.expectedVO2(age: 35, sex: "male")!
        XCTAssertEqual(VO2MaxNorms.percentile(vo2: median, age: 35, sex: "male")!, 50, accuracy: 1)
        XCTAssertGreaterThan(VO2MaxNorms.percentile(vo2: median + 10, age: 35, sex: "male")!, 85)
        XCTAssertLessThan(VO2MaxNorms.percentile(vo2: median - 10, age: 35, sex: "male")!, 15)
        // The same measurement is a better percentile at an older age.
        let fixed = 45.0
        XCTAssertGreaterThan(VO2MaxNorms.percentile(vo2: fixed, age: 55, sex: "male")!,
                             VO2MaxNorms.percentile(vo2: fixed, age: 25, sex: "male")!)
        XCTAssertNil(VO2MaxNorms.percentile(vo2: 45, age: 35, sex: nil))
        XCTAssertEqual(VO2MaxNorms.band(percentile: 50), "vo2Average")
    }

    func testWeeklyActivityCountsVigorousMinutesDouble() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func workout(_ zones: [Double], offsetDays: Double = 1) -> WorkoutSummary {
            let begin = start.addingTimeInterval(offsetDays * 86400)
            return .init(start: begin, end: begin.addingTimeInterval(3600), activity: "running", zoneMinutes: zones)
        }
        let end = start.addingTimeInterval(7 * 86400)

        // 75 vigorous minutes satisfy the guideline on their own.
        let vigorous = WeeklyActivityEngine.calculate(workouts: [workout([0, 40, 35, 0, 0])], from: start, to: end)
        XCTAssertEqual(vigorous.vigorousMinutes, 75)
        XCTAssertEqual(vigorous.equivalentMinutes, 150)
        XCTAssertTrue(vigorous.meetsGuideline)
        XCTAssertEqual(vigorous.band, "activityMeets")

        // The same minutes at moderate intensity do not.
        let moderate = WeeklyActivityEngine.calculate(workouts: [workout([75, 0, 0, 0, 0])], from: start, to: end)
        XCTAssertFalse(moderate.meetsGuideline)
        XCTAssertEqual(moderate.equivalentMinutes, 75)

        // Work outside the window does not count.
        let outside = WeeklyActivityEngine.calculate(workouts: [workout([0, 40, 35, 0, 0], offsetDays: 20)], from: start, to: end)
        XCTAssertEqual(outside.equivalentMinutes, 0)
        XCTAssertEqual(outside.band, "activityInactive")

        XCTAssertTrue(WeeklyActivityEngine.calculate(workouts: [workout([0, 100, 100, 0, 0])], from: start, to: end).exceedsUpperRange)
    }
}
