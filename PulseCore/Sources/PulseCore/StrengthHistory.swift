import Foundation

/// What the app knows about how you last trained each exercise.
///
/// This is the part that makes logging bearable: the next session starts from
/// the numbers of the previous one, so a normal day is a few taps to confirm
/// rather than typing every weight again.
public enum StrengthHistoryEngine {
    /// Completed sets of one exercise in the most recent session that contains
    /// it, oldest set first. Sessions still in progress are ignored, and so are
    /// sets that were never ticked off — an untouched placeholder is not a
    /// record of anything.
    public static func lastSets(exercise: String, in sessions: [StrengthSession], before: Date = .distantFuture) -> [StrengthSet] {
        let candidates = sessions
            .filter { $0.end != nil && $0.start < before && $0.sets.contains { $0.exerciseID == exercise && $0.completed } }
            .sorted { $0.start > $1.start }
        guard let session = candidates.first else { return [] }
        return session.sets.filter { $0.exerciseID == exercise && $0.completed }
    }

    /// The set to pre-fill when the exercise is added again: the last session's
    /// set at that position, or its final set once you go past it. Returns nil
    /// when the exercise has never been logged, because inventing a starting
    /// weight for someone would be worse than leaving the field empty.
    public static func suggestion(exercise: String, position: Int = 0, in sessions: [StrengthSession]) -> StrengthSet? {
        let previous = lastSets(exercise: exercise, in: sessions)
        guard !previous.isEmpty else { return nil }
        var set = previous[min(position, previous.count - 1)]
        set.id = UUID()
        set.completed = false
        return set
    }

    /// Total load moved, in kilograms: the arithmetic every training log calls
    /// volume. Bodyweight sets contribute nothing, since the app does not know
    /// what share of your weight a given movement lifts.
    public static func volume(_ sets: [StrengthSet]) -> Double {
        sets.filter(\.completed).reduce(0) { $0 + Double($1.reps) * max(0, $1.weightKg) }
    }

    /// The heaviest single effort by estimated one-rep max, which is the
    /// comparison that survives different rep counts.
    public static func best(exercise: String, in sessions: [StrengthSession]) -> StrengthSet? {
        sessions.flatMap(\.sets)
            .filter { $0.exerciseID == exercise && $0.completed && $0.weightKg > 0 }
            .max { (StrengthEngine.estimated1RM(weight: $0.weightKg, reps: $0.reps) ?? 0) < (StrengthEngine.estimated1RM(weight: $1.weightKg, reps: $1.reps) ?? 0) }
    }

    /// Today's version of a previous workout: the same exercises and the same
    /// numbers, with nothing ticked off yet.
    public static func repeated(_ session: StrengthSession, named name: String? = nil, now: Date = Date()) -> StrengthSession {
        let sets = session.sets.map { set -> StrengthSet in
            var copy = set
            copy.id = UUID()
            copy.completed = false
            return copy
        }
        return StrengthSession(start: now, name: name ?? session.name, sets: sets)
    }

    /// Completed volume per muscle group over a window, for the weekly summary.
    /// A set counts fully for the primary group and not at all for secondary
    /// ones: splitting it would imply a precision the catalogue does not have.
    public static func volumeByGroup(sessions: [StrengthSession], catalogue: [ExerciseDefinition], from: Date, to: Date) -> [String: Double] {
        let groups = Dictionary(catalogue.map { ($0.id, $0.group) }, uniquingKeysWith: { a, _ in a })
        var totals: [String: Double] = [:]
        for session in sessions where session.start >= from && session.start < to {
            for set in session.sets where set.completed {
                let group = groups[set.exerciseID] ?? "other"
                totals[group, default: 0] += Double(set.reps) * max(0, set.weightKg)
            }
        }
        return totals
    }
}
