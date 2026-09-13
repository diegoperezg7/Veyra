import Foundation

/// What a strength session actually worked, and how much of it.
public enum MuscleTensionEngine {

    /// A muscle's share of a session, with the working sets behind it.
    public struct Share: Sendable, Equatable, Identifiable {
        /// Localisation key: "lats", "biceps"…
        public var muscle: String
        /// Percentage of the session's total tension, 0–100.
        public var percent: Double
        /// Effective sets, primary counting whole and secondary counting half.
        public var sets: Double
        /// Kilograms moved on the sets that named this muscle as primary.
        public var volume: Double
        public var id: String { muscle }
    }

    /// Weight a set contributes to a muscle it does not directly target.
    ///
    /// Hypertrophy research counts training volume in **working sets per muscle
    /// per week** rather than in kilograms — kilograms are not comparable
    /// between a squat and a curl, and they exclude bodyweight work entirely.
    /// Secondary involvement is real but smaller, and half a set is the
    /// convention most trackers settle on. The half is a **design decision**;
    /// counting in sets is not.
    public static let secondaryWeight = 0.5

    /// Tension per muscle across a set of completed sets, largest first.
    public static func shares(sets: [StrengthSet], catalogue: [ExerciseDefinition]) -> [Share] {
        let byID = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var effective: [String: Double] = [:]
        var volume: [String: Double] = [:]

        for set in sets where set.completed {
            guard let exercise = byID[set.exerciseID] else { continue }
            let work = Double(set.reps) * max(0, set.weightKg)
            for muscle in exercise.primaryMuscles {
                effective[muscle, default: 0] += 1
                volume[muscle, default: 0] += work
            }
            for muscle in exercise.secondaryMuscles where !exercise.primaryMuscles.contains(muscle) {
                effective[muscle, default: 0] += secondaryWeight
            }
        }
        let total = effective.values.reduce(0, +)
        guard total > 0 else { return [] }
        return effective
            .map { Share(muscle: $0.key, percent: $0.value / total * 100,
                         sets: $0.value, volume: volume[$0.key] ?? 0) }
            .sorted { ($0.percent, $0.muscle) > ($1.percent, $1.muscle) }
    }

    /// Totals a training log shows at the top: kilograms moved and repetitions
    /// performed. Only completed sets count — an untouched placeholder is not
    /// work that happened.
    public struct Totals: Sendable, Equatable {
        public var volume: Double
        public var repetitions: Int
        public var sets: Int
        public var exercises: Int
    }

    public static func totals(_ sets: [StrengthSet]) -> Totals {
        let done = sets.filter(\.completed)
        return Totals(volume: done.reduce(0) { $0 + Double($1.reps) * max(0, $1.weightKg) },
                      repetitions: done.reduce(0) { $0 + max(0, $1.reps) },
                      sets: done.count,
                      exercises: Set(done.map(\.exerciseID)).count)
    }

    /// How a session divides between lifting and cardiovascular work.
    ///
    /// Both sides are already part of how Veyra scores a day: strain is built
    /// from cardiac zone load plus strength load. This is that same split,
    /// expressed as a share, so it introduces no new arithmetic and cannot
    /// disagree with the strain score.
    public struct Split: Sendable, Equatable {
        public var muscular: Double
        public var cardio: Double
    }

    public static func split(strengthLoad: Double, cardiacLoad: Double) -> Split? {
        let strength = max(0, strengthLoad.isFinite ? strengthLoad : 0)
        let cardiac = max(0, cardiacLoad.isFinite ? cardiacLoad : 0)
        let total = strength + cardiac
        guard total > 0 else { return nil }
        return Split(muscular: strength / total * 100, cardio: cardiac / total * 100)
    }

    /// Sets grouped the way they were performed: consecutive sets of different
    /// exercises sharing a superset tag belong together.
    public static func groups(_ sets: [StrengthSet]) -> [[String]] {
        var result: [[String]] = []
        var seen: Set<String> = []
        for set in sets {
            let tag = set.superset.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty else {
                if !seen.contains(set.exerciseID) {
                    seen.insert(set.exerciseID)
                    result.append([set.exerciseID])
                }
                continue
            }
            if let index = result.firstIndex(where: { group in
                sets.contains { $0.superset == tag && group.contains($0.exerciseID) }
            }) {
                if !result[index].contains(set.exerciseID) { result[index].append(set.exerciseID) }
            } else if !seen.contains(set.exerciseID) {
                result.append([set.exerciseID])
            }
            seen.insert(set.exerciseID)
        }
        return result
    }
}
