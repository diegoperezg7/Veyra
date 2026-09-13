import XCTest
@testable import PulseCore

final class EnergyBankTests: XCTestCase {
    func testDailyEngineProducesProvisionalStressFromHeartRate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let values = [60.0, 72.0, 68.0].enumerated().map { index, value in
            Vital(id: "hr", value: value, unit: "bpm", date: day.addingTimeInterval(Double(index) * 900))
        }
        let snapshot = DailyEngine.calculate(
            date: day,
            batch: HealthBatch(vitals: values),
            history: [],
            calendar: calendar,
            now: day.addingTimeInterval(86_400)
        )
        XCTAssertFalse(snapshot.stress.isEmpty)
        XCTAssertNotNil(snapshot.score(.stress).value)
    }

    func testDailyTimelineStopsAtNowAndFlagsMissingStress() {
        let day = Date(timeIntervalSince1970: 1_783_036_800)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: day)
        let wake = start.addingTimeInterval(8 * 3600)
        let batch = HealthBatch(sleep: [.init(start: start, end: wake, stage: .unspecified)])
        let now = wake.addingTimeInterval(3600)
        let result = DailyEngine.calculate(date: start, batch: batch, history: [], calendar: calendar, now: now)
        // The simulation now starts at the night's onset, so the timeline
        // spans the sleep as well as the waking hour that follows it.
        XCTAssertEqual(result.energy.last?.date, now)
        XCTAssertEqual(result.score(.energy).algorithmVersion, DailyEngine.algorithmVersion)
        XCTAssertNotNil(result.score(.energy).value)
        // Intervals inside the night are not "predicted": they are asleep.
        XCTAssertTrue(result.energyDetail?.contains { $0.asleep } ?? false)
        XCTAssertTrue(result.energy.suffix(3).allSatisfy(\.predicted))
        let future = DailyEngine.calculate(date: start, batch: batch, history: [], calendar: calendar, now: start)
        XCTAssertTrue(future.energy.isEmpty)
    }
    func testMissingSleepCarriesTheEveningForwardButInventsNothing() {
        // A day with no scored night continues from the previous evening
        // instead of leaving the battery blank all day.
        XCTAssertEqual(EnergyBankEngine.morning(previous: 50, recovery: 80, sleep: nil), 50)
        // With neither a night nor a prior value there is nothing to report.
        XCTAssertNil(EnergyBankEngine.morning(previous: nil, recovery: 80, sleep: .nan))
        XCTAssertNil(EnergyBankEngine.morning(previous: .nan, recovery: 80, sleep: nil))
    }
    func testSleepOnlyEstimateWhileCalibrating() {
        XCTAssertEqual(EnergyBankEngine.morning(previous: nil, recovery: nil, sleep: 75), 75)
        XCTAssertEqual(EnergyBankEngine.morning(previous: .nan, recovery: 80, sleep: 60), 73)
    }
    func testRestAndExerciseMoveInExpectedDirections() {
        let rest = EnergyBankEngine.step(energy: 50, stress: 10, load: 0, resting: true)
        let workout = EnergyBankEngine.step(energy: 50, stress: nil, load: 50, resting: false)
        XCTAssertGreaterThan(rest.value, 50)
        XCTAssertLessThan(workout.value, 50)
        XCTAssertGreaterThan(EnergyBankEngine.step(energy: 50, stress: nil, load: 0, resting: false, napMinutes: 15).value, 50)
    }
    func testStepReportsWhyTheLevelMoved() {
        let workout = EnergyBankEngine.step(energy: 60, stress: 80, load: 30, resting: false)
        XCTAssertGreaterThan(workout.loadDrain, 0)
        XCTAssertGreaterThan(workout.stressDrain, 0)
        XCTAssertGreaterThan(workout.baselineDrain, 0)
        XCTAssertEqual(workout.value, 60 + workout.restoration - workout.stressDrain - workout.loadDrain - workout.baselineDrain, accuracy: 0.000001)
    }
    func testSleepingRechargesAndSuspendsTheWakingCost() {
        let rate = EnergyBankEngine.sleepRate(start: 20, target: 80, minutes: 480)
        XCTAssertEqual(rate, 0.125, accuracy: 0.0001)
        let asleep = EnergyBankEngine.step(energy: 20, stress: nil, load: 0, resting: false, asleepMinutes: 15, sleepRate: rate)
        XCTAssertTrue(asleep.asleep)
        XCTAssertEqual(asleep.baselineDrain, 0)
        XCTAssertEqual(asleep.stressDrain, 0)
        XCTAssertGreaterThan(asleep.value, 20)
        // A night with nothing to climb towards does not fabricate a recharge.
        XCTAssertEqual(EnergyBankEngine.sleepRate(start: 80, target: 20, minutes: 480), 0)
    }
    func testBadInputsAndBounds() {
        for start in [Double.nan, .infinity, -20, 0, 50, 100, 150] {
            for stress in [Double.nan, .infinity, -100, 100] {
                let value = EnergyBankEngine.step(energy: start, stress: stress, load: .infinity, resting: false, napMinutes: .nan).value
                XCTAssertTrue(value.isFinite)
                XCTAssertTrue((0...100).contains(value))
            }
        }
        XCTAssertEqual(EnergyBankEngine.step(energy: 50, stress: 100, load: 100, resting: false, minutes: 0).value, 50)
    }
    func testExerciseLoadDoesNotDependOnIntervalSplitting() {
        let whole = EnergyBankEngine.step(energy: 80, stress: 65, load: 20, resting: false, minutes: 30).value
        let first = EnergyBankEngine.step(energy: 80, stress: 65, load: 10, resting: false).value
        let second = EnergyBankEngine.step(energy: first, stress: 65, load: 10, resting: false).value
        XCTAssertEqual(whole, second, accuracy: 0.000001)
    }
}
