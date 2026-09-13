import XCTest
@testable import PulseCore

final class MuscleTensionTests: XCTestCase {
    private var catalogue: [ExerciseDefinition] {
        var row = ExerciseDefinition(id: "row", name: "Remo")
        row.primaryMuscles = ["lats"]; row.secondaryMuscles = ["biceps", "forearms"]; row.group = "back"
        var curl = ExerciseDefinition(id: "curl", name: "Curl")
        curl.primaryMuscles = ["biceps"]; curl.secondaryMuscles = ["forearms"]; curl.group = "arms"
        var pullup = ExerciseDefinition(id: "pullup", name: "Dominada")
        pullup.primaryMuscles = ["lats"]; pullup.secondaryMuscles = ["biceps"]; pullup.group = "back"
        return [row, curl, pullup]
    }
    private func set(_ id: String, reps: Int = 10, kg: Double = 50, done: Bool = true) -> StrengthSet {
        .init(exerciseID: id, reps: reps, weightKg: kg, completed: done)
    }

    /// Counted in sets, not kilograms: kilograms are not comparable between a
    /// row and a curl, and bodyweight work would count as nothing.
    func testTensionCountsSetsSoBodyweightWorkStillCounts() {
        let shares = MuscleTensionEngine.shares(
            sets: [set("pullup", reps: 8, kg: 0), set("pullup", reps: 8, kg: 0)],
            catalogue: catalogue)
        XCTAssertEqual(shares.first?.muscle, "lats")
        // Two sets: lats 2 whole, biceps 2 halves. 2 / 3 and 1 / 3.
        XCTAssertEqual(shares.first?.percent ?? 0, 66.67, accuracy: 0.1)
        XCTAssertEqual(shares.last?.muscle, "biceps")
        XCTAssertEqual(shares.last?.percent ?? 0, 33.33, accuracy: 0.1)
        XCTAssertEqual(shares.map(\.percent).reduce(0, +), 100, accuracy: 0.001)
    }

    func testSecondaryInvolvementCountsHalf() {
        let shares = MuscleTensionEngine.shares(sets: [set("row")], catalogue: catalogue)
        let byMuscle = Dictionary(shares.map { ($0.muscle, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byMuscle["lats"]?.sets, 1)
        XCTAssertEqual(byMuscle["biceps"]?.sets, 0.5)
        XCTAssertEqual(byMuscle["forearms"]?.sets, 0.5)
        // Volume in kilograms is attributed to the primary only.
        XCTAssertEqual(byMuscle["lats"]?.volume, 500)
        XCTAssertEqual(byMuscle["biceps"]?.volume, 0)
    }

    func testUntickedSetsAndUnknownExercisesAreIgnored() {
        XCTAssertTrue(MuscleTensionEngine.shares(sets: [set("row", done: false)], catalogue: catalogue).isEmpty)
        XCTAssertTrue(MuscleTensionEngine.shares(sets: [set("mystery")], catalogue: catalogue).isEmpty)
        XCTAssertTrue(MuscleTensionEngine.shares(sets: [], catalogue: catalogue).isEmpty)
    }

    func testTotalsCountOnlyCompletedWork() {
        let totals = MuscleTensionEngine.totals([
            set("row", reps: 10, kg: 60), set("row", reps: 8, kg: 60),
            set("curl", reps: 12, kg: 20), set("curl", reps: 12, kg: 20, done: false)
        ])
        let expected: Double = 600 + 480 + 240
        XCTAssertEqual(totals.volume, expected)
        XCTAssertEqual(totals.repetitions, 30)
        XCTAssertEqual(totals.sets, 3)
        XCTAssertEqual(totals.exercises, 2)
    }

    /// The split is the same arithmetic strain already uses, so the two can
    /// never disagree.
    func testSplitIsTheStrainComponentsAsShares() {
        let split = MuscleTensionEngine.split(strengthLoad: 53, cardiacLoad: 47)!
        XCTAssertEqual(split.muscular, 53, accuracy: 0.001)
        XCTAssertEqual(split.cardio, 47, accuracy: 0.001)
        XCTAssertNil(MuscleTensionEngine.split(strengthLoad: 0, cardiacLoad: 0))
        // A pure cardio session is all cardio, not half of nothing.
        XCTAssertEqual(MuscleTensionEngine.split(strengthLoad: 0, cardiacLoad: 80)!.cardio, 100)
    }

    func testSupersetsGroupTheExercisesPerformedTogether() {
        var a = set("row"); a.superset = "A"
        var b = set("curl"); b.superset = "A"
        let c = set("pullup")
        let groups = MuscleTensionEngine.groups([a, b, c, a, b])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups[0]), ["row", "curl"])
        XCTAssertEqual(groups[1], ["pullup"])
        // Without tags every exercise stands alone, in the order performed.
        XCTAssertEqual(MuscleTensionEngine.groups([set("curl"), set("row"), set("curl")]), [["curl"], ["row"]])
    }
}
