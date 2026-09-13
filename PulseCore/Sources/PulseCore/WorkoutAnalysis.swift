import Foundation

/// Everything the workout detail screen shows about a single session.
///
/// None of it is new measurement: it is the zone minutes the watch already
/// produced, read three different ways — as load, as a distribution, and as the
/// three-zone intensity model coaches actually talk in.
public enum WorkoutAnalysis {

    // MARK: - Zones

    /// Minutes per zone including zone 0, lowest first. Zone 0 is everything
    /// below 50% of heart-rate reserve: warm-up, recovery between efforts, and
    /// the walk to the machine.
    public static func zoneMinutes(_ workout: WorkoutSummary) -> [Double] {
        [workout.belowZoneMinutes ?? 0] + (0..<5).map { index in
            index < workout.zoneMinutes.count ? max(0, workout.zoneMinutes[index]) : 0
        }
    }

    /// Share of the measured time spent in each zone, 0–100, lowest first.
    /// Returns nil when the watch attributed no time at all, which is what
    /// happens for a workout recorded without a heart-rate sensor.
    public static func zoneShare(_ workout: WorkoutSummary) -> [Double]? {
        let minutes = zoneMinutes(workout)
        let total = minutes.reduce(0, +)
        guard total > 0 else { return nil }
        return minutes.map { $0 / total * 100 }
    }

    /// Heart-rate bounds of a zone as beats per minute, for drawing the bands
    /// behind the chart. Zone *n* spans (40 + 10n)% to (50 + 10n)% of reserve,
    /// with zone 0 starting at rest.
    public static func zoneBounds(_ zone: Int, resting: Double, maximum: Double) -> ClosedRange<Double>? {
        guard maximum > resting, resting > 0, (0...5).contains(zone) else { return nil }
        let reserve = maximum - resting
        let lower = zone == 0 ? resting : resting + reserve * (0.5 + Double(zone - 1) * 0.1)
        let upper = zone == 0 ? resting + reserve * 0.5 : resting + reserve * (0.5 + Double(zone) * 0.1)
        return lower...min(maximum, upper)
    }

    // MARK: - Cardiovascular focus

    /// The three-zone intensity model (Seiler): easy work below the first
    /// ventilatory threshold, tempo between the two, and hard work above the
    /// second. Mapped onto heart-rate reserve, VT1 sits around 70% and VT2
    /// around 90% — so zones 0–2 are low aerobic, 3–4 high aerobic and 5
    /// anaerobic. The thresholds are individual; these are population averages,
    /// which makes the split **derived**, not measured.
    public struct Focus: Sendable, Equatable {
        public var lowAerobic: Double
        public var highAerobic: Double
        public var anaerobic: Double
        /// Which of the three took most of the session.
        public var dominant: String {
            if anaerobic >= highAerobic && anaerobic >= lowAerobic { return "focusAnaerobic" }
            return highAerobic > lowAerobic ? "focusHighAerobic" : "focusLowAerobic"
        }
    }

    public static func focus(_ workout: WorkoutSummary) -> Focus? {
        guard let share = zoneShare(workout) else { return nil }
        return Focus(lowAerobic: share[0] + share[1] + share[2],
                     highAerobic: share[3] + share[4],
                     anaerobic: share[5])
    }

    // MARK: - Cardiac load

    /// Edwards' TRIMP for this session alone: minutes in each zone weighted by
    /// the zone number. Zone 0 contributes nothing, which is the point of the
    /// method — time spent not working is not load.
    public static func load(_ workout: WorkoutSummary) -> Double {
        HeartRateZoneEngine.load(zoneMinutes: workout.zoneMinutes)
    }

    /// This session's load against the median of previous ones, as a
    /// percentage. Needs a few sessions before it means anything, and says so
    /// by returning nil.
    public static let comparisonMinimum = 4
    public static func loadComparison(_ workout: WorkoutSummary, history: [WorkoutSummary]) -> Double? {
        let previous = history
            .filter { $0.id != workout.id && $0.start < workout.start }
            .map(load)
            .filter { $0 > 0 }
        guard previous.count >= comparisonMinimum, let median = Statistics.median(previous), median > 0 else { return nil }
        return (load(workout) - median) / median * 100
    }

    // MARK: - Effort

    /// The session's share of the day's total cardiac load, 0–100. It is what
    /// lets the screen say how much of today's strain this workout accounts
    /// for, rather than repeating the day's number.
    public static func shareOfDay(_ workout: WorkoutSummary, dayLoad: Double) -> Double? {
        let workoutLoad = load(workout)
        guard dayLoad > 0, workoutLoad > 0 else { return nil }
        return Statistics.clamp(workoutLoad / dayLoad * 100)
    }

    /// Average heart rate as a percentage of heart-rate reserve, which is the
    /// comparable way to say "how hard was it" across people and sessions.
    public static func intensity(_ workout: WorkoutSummary) -> Double? {
        guard let average = workout.averageHeartRate,
              let resting = workout.restingHeartRate,
              let maximum = workout.maximumHeartRateReference,
              maximum > resting else { return nil }
        return Statistics.clamp((average - resting) / (maximum - resting) * 100)
    }

    // MARK: - Heart-rate series

    /// Keeps the series small enough to store and draw: one point per interval,
    /// taking the maximum within it so peaks survive rather than being averaged
    /// away.
    public static func subsample(_ points: [TimelinePoint], interval: TimeInterval = 60) -> [TimelinePoint] {
        guard let first = points.map(\.date).min(), interval > 0 else { return [] }
        var buckets: [Int: TimelinePoint] = [:]
        for point in points where point.value.isFinite {
            let index = Int(point.date.timeIntervalSince(first) / interval)
            if let existing = buckets[index], existing.value >= point.value { continue }
            buckets[index] = .init(date: first.addingTimeInterval(Double(index) * interval), value: point.value)
        }
        return buckets.keys.sorted().compactMap { buckets[$0] }
    }
}
