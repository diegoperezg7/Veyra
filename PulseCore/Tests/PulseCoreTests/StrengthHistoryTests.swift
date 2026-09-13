import XCTest
@testable import PulseCore

final class StrengthHistoryTests: XCTestCase {
    private let day = 86400.0
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(daysAgo: Double, _ sets: [StrengthSet], finished: Bool = true) -> StrengthSession {
        let start = now.addingTimeInterval(-daysAgo * day)
        return StrengthSession(start: start, end: finished ? start.addingTimeInterval(3600) : nil,
                               name: "Espalda", sets: sets)
    }
    private func set(_ id: String, reps: Int, kg: Double, done: Bool = true) -> StrengthSet {
        .init(exerciseID: id, reps: reps, weightKg: kg, completed: done)
    }

    func testSuggestionComesFromTheLastFinishedSessionSetBySet() {
        let history = [
            session(daysAgo: 9, [set("row", reps: 10, kg: 50), set("row", reps: 10, kg: 50)]),
            session(daysAgo: 2, [set("row", reps: 10, kg: 60), set("row", reps: 8, kg: 65)])
        ]
        XCTAssertEqual(StrengthHistoryEngine.suggestion(exercise: "row", position: 0, in: history)?.weightKg, 60)
        XCTAssertEqual(StrengthHistoryEngine.suggestion(exercise: "row", position: 1, in: history)?.weightKg, 65)
        // Past the end of last time's sets, the final one repeats.
        XCTAssertEqual(StrengthHistoryEngine.suggestion(exercise: "row", position: 5, in: history)?.weightKg, 65)
        // A suggestion is never pre-ticked.
        XCTAssertEqual(StrengthHistoryEngine.suggestion(exercise: "row", in: history)?.completed, false)
        // Never trained: no invented starting weight.
        XCTAssertNil(StrengthHistoryEngine.suggestion(exercise: "squat", in: history))
    }

    func testUnfinishedSessionsAndUntickedSetsAreNotHistory() {
        let history = [
            session(daysAgo: 5, [set("bench", reps: 10, kg: 40)]),
            // In progress: today's own session must not become its own source.
            session(daysAgo: 0, [set("bench", reps: 10, kg: 90)], finished: false),
            // Finished, but the set was never completed.
            session(daysAgo: 1, [set("bench", reps: 10, kg: 200, done: false)])
        ]
        XCTAssertEqual(StrengthHistoryEngine.suggestion(exercise: "bench", in: history)?.weightKg, 40)
    }

    func testVolumeCountsOnlyCompletedWork() {
        let sets = [set("row", reps: 10, kg: 50), set("row", reps: 10, kg: 50, done: false),
                    set("pullup", reps: 8, kg: 0)]
        XCTAssertEqual(StrengthHistoryEngine.volume(sets), 500)
    }

    func testBestIsRankedByEstimatedOneRepMax() {
        let history = [session(daysAgo: 3, [set("bench", reps: 10, kg: 80), set("bench", reps: 1, kg: 100)])]
        // 80 × 10 estimates ~107 kg, which beats a true single of 100.
        XCTAssertEqual(StrengthHistoryEngine.best(exercise: "bench", in: history)?.reps, 10)
    }

    func testRepeatingAWorkoutKeepsTheNumbersAndClearsTheTicks() {
        let previous = session(daysAgo: 1, [set("row", reps: 10, kg: 60), set("curl", reps: 12, kg: 15)])
        let today = StrengthHistoryEngine.repeated(previous, now: now)
        XCTAssertEqual(today.sets.map(\.weightKg), [60, 15])
        XCTAssertTrue(today.sets.allSatisfy { !$0.completed })
        XCTAssertNil(today.end)
        XCTAssertEqual(today.start, now)
        XCTAssertNotEqual(today.id, previous.id)
        XCTAssertEqual(today.exerciseOrder, ["row", "curl"])
    }

    func testVolumeByGroupUsesThePrimaryGroupOnly() {
        var row = ExerciseDefinition(id: "row", name: "Remo"); row.group = "back"
        var curl = ExerciseDefinition(id: "curl", name: "Curl"); curl.group = "arms"
        let history = [session(daysAgo: 1, [set("row", reps: 10, kg: 60), set("curl", reps: 10, kg: 10)])]
        let totals = StrengthHistoryEngine.volumeByGroup(sessions: history, catalogue: [row, curl],
                                                        from: now.addingTimeInterval(-7 * day), to: now)
        XCTAssertEqual(totals["back"], 600)
        XCTAssertEqual(totals["arms"], 100)
        XCTAssertNil(totals["legs"])
    }
}
