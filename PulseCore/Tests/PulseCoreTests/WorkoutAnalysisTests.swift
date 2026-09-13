import XCTest
@testable import PulseCore

final class WorkoutAnalysisTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func workout(_ zones: [Double], below: Double? = nil, minutes: Double = 60,
                         average: Double? = nil, resting: Double? = nil, maximum: Double? = nil) -> WorkoutSummary {
        .init(start: start, end: start.addingTimeInterval(minutes * 60), activity: "running",
              zoneMinutes: zones, belowZoneMinutes: below, averageHeartRate: average,
              restingHeartRate: resting, maximumHeartRateReference: maximum)
    }

    func testZoneMinutesIncludeZoneZeroAndPadMissingZones() {
        let partial = workout([10, 5], below: 12)
        XCTAssertEqual(WorkoutAnalysis.zoneMinutes(partial), [12, 10, 5, 0, 0, 0])
        // A workout from a version that never recorded zone 0 simply has none.
        XCTAssertEqual(WorkoutAnalysis.zoneMinutes(workout([1, 2, 3, 4, 5])), [0, 1, 2, 3, 4, 5])
    }

    func testZoneShareIsNilWithoutMeasuredTime() {
        XCTAssertNil(WorkoutAnalysis.zoneShare(workout([])))
        XCTAssertNil(WorkoutAnalysis.zoneShare(workout([0, 0, 0, 0, 0], below: 0)))
        let share = WorkoutAnalysis.zoneShare(workout([30, 10, 10, 0, 0], below: 50))!
        XCTAssertEqual(share.reduce(0, +), 100, accuracy: 0.001)
        XCTAssertEqual(share[0], 50, accuracy: 0.001)
    }

    /// The three-zone model: easy below VT1, tempo between, hard above VT2.
    func testFocusSplitsAtTheVentilatoryThresholds() {
        // All of it in zones 0–2 is entirely low aerobic.
        let easy = WorkoutAnalysis.focus(workout([20, 20, 0, 0, 0], below: 20))!
        XCTAssertEqual(easy.lowAerobic, 100, accuracy: 0.001)
        XCTAssertEqual(easy.anaerobic, 0)
        XCTAssertEqual(easy.dominant, "focusLowAerobic")

        // Zones 3 and 4 are the high aerobic middle; zone 5 is anaerobic.
        let intervals = WorkoutAnalysis.focus(workout([0, 0, 0, 10, 10, 20]))!
        XCTAssertEqual(intervals.highAerobic, 50, accuracy: 0.001)
        XCTAssertEqual(intervals.anaerobic, 50, accuracy: 0.001)
        XCTAssertEqual(intervals.dominant, "focusAnaerobic")

        let tempo = WorkoutAnalysis.focus(workout([0, 0, 30, 5, 0], below: 5))!
        XCTAssertEqual(tempo.dominant, "focusHighAerobic")
        XCTAssertNil(WorkoutAnalysis.focus(workout([])))
    }

    func testZoneBoundsFollowHeartRateReserve() {
        // Resting 50, maximum 190: reserve 140. Zone 1 starts at 50% of it.
        let zone1 = WorkoutAnalysis.zoneBounds(1, resting: 50, maximum: 190)!
        XCTAssertEqual(zone1.lowerBound, 120, accuracy: 0.001)
        XCTAssertEqual(zone1.upperBound, 134, accuracy: 0.001)
        let zone0 = WorkoutAnalysis.zoneBounds(0, resting: 50, maximum: 190)!
        XCTAssertEqual(zone0.lowerBound, 50, accuracy: 0.001)
        XCTAssertEqual(zone0.upperBound, 120, accuracy: 0.001)
        // Zone 5 never exceeds the maximum it was derived from.
        XCTAssertEqual(WorkoutAnalysis.zoneBounds(5, resting: 50, maximum: 190)!.upperBound, 190, accuracy: 0.001)
        XCTAssertNil(WorkoutAnalysis.zoneBounds(1, resting: 190, maximum: 50))
        XCTAssertNil(WorkoutAnalysis.zoneBounds(9, resting: 50, maximum: 190))
    }

    func testLoadIgnoresZoneZeroAndComparesAgainstHistory() {
        let session = workout([10, 10, 10, 0, 0], below: 40)
        // 10×1 + 10×2 + 10×3 = 60. The 40 easy minutes add nothing.
        XCTAssertEqual(WorkoutAnalysis.load(session), 60)

        // Not enough previous sessions to compare against.
        XCTAssertNil(WorkoutAnalysis.loadComparison(session, history: [workout([10, 0, 0, 0, 0])]))

        let history = (1...5).map { index -> WorkoutSummary in
            var previous = workout([10, 10, 0, 0, 0])       // load 30
            previous.start = start.addingTimeInterval(-Double(index) * 86400)
            previous.end = previous.start.addingTimeInterval(3600)
            return previous
        }
        // 60 against a median of 30 is double.
        XCTAssertEqual(WorkoutAnalysis.loadComparison(session, history: history)!, 100, accuracy: 0.001)
    }

    func testIntensityIsTheReserveTheAverageSatAt() {
        let session = workout([10, 10, 0, 0, 0], average: 120, resting: 50, maximum: 190)
        XCTAssertEqual(WorkoutAnalysis.intensity(session)!, 50, accuracy: 0.001)
        // Without the references there is no comparable intensity.
        XCTAssertNil(WorkoutAnalysis.intensity(workout([10], average: 120)))
    }

    func testShareOfDayIsBoundedAndAbsentWithoutLoad() {
        let session = workout([10, 10, 10, 0, 0])          // load 60
        XCTAssertEqual(WorkoutAnalysis.shareOfDay(session, dayLoad: 120)!, 50, accuracy: 0.001)
        XCTAssertEqual(WorkoutAnalysis.shareOfDay(session, dayLoad: 30)!, 100, accuracy: 0.001)
        XCTAssertNil(WorkoutAnalysis.shareOfDay(workout([]), dayLoad: 120))
        XCTAssertNil(WorkoutAnalysis.shareOfDay(session, dayLoad: 0))
    }

    func testSubsamplingKeepsThePeaksAndTheOrder() {
        var points: [TimelinePoint] = []
        for second in stride(from: 0, to: 300, by: 5) {
            // A spike at 130 seconds that averaging would erase.
            let value = second == 130 ? 185.0 : 120.0
            points.append(.init(date: start.addingTimeInterval(Double(second)), value: value))
        }
        let sampled = WorkoutAnalysis.subsample(points, interval: 60)
        XCTAssertEqual(sampled.count, 5)
        XCTAssertEqual(sampled.map(\.date), sampled.map(\.date).sorted())
        XCTAssertEqual(sampled[2].value, 185, "el pico debe sobrevivir al submuestreo")
        XCTAssertTrue(WorkoutAnalysis.subsample([], interval: 60).isEmpty)
    }
}
