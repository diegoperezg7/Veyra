import Foundation
public enum HeartRateZoneEngine {
    public static func zone(heartRate: Double, resting: Double, maximum: Double) -> Int? {
        guard heartRate.isFinite, maximum > resting, resting > 0 else { return nil }
        let reserve = (heartRate - resting) / (maximum - resting)
        return reserve < 0.5 ? 0 : min(5, max(1, Int((reserve - 0.5) * 10) + 1))
    }
    public static func load(zoneMinutes: [Double]) -> Double { zoneMinutes.prefix(5).enumerated().reduce(0) { $0 + max(0, $1.element.isFinite ? $1.element : 0) * Double($1.offset + 1) } }
}
public enum StrainEngine {
    public static func score(rawLoad: Double, history: [Double]) -> Double {
        let observations = history.filter { $0.isFinite && $0 > 0 }
        // P75 represents a demanding, but still normal, personal day. The
        // previous log curve mapped that day to 100, which made ordinary
        // activity look like an extreme effort. This saturating curve maps it
        // to 63 and reserves the upper end for unusually large workloads.
        let scale = max(120, Statistics.percentile(observations, 0.75) ?? 150)
        let load = max(0, rawLoad.isFinite ? rawLoad : 0)
        return Statistics.clamp(100 * (1 - exp(-load / scale)))
    }
    public static func target(history: [Double], recovery: Double?, status: String = "active") -> ClosedRange<Double>? {
        guard let recovery, let base = Statistics.median(Array(history.suffix(14))) else { return nil }
        let factor = status == "active" ? 1.0 : status == "break" ? 0.7 : 0.5
        let target = Statistics.clamp(base * (0.65 + 0.7 * recovery / 100) * factor, 5, 120)
        return target * 0.9...target * 1.1
    }
    public static func deduplicate(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var result: [WorkoutSummary] = []
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            if result.contains(where: { other in
                if other.id == workout.id { return true }
                let overlap = min(other.end, workout.end).timeIntervalSince(max(other.start, workout.start))
                return other.activity == workout.activity && overlap > 0 && overlap / max(1, min(other.minutes, workout.minutes) * 60) > 0.85
            }) { continue }
            result.append(workout)
        }
        return result
    }
}
public struct CardioLoad: Sendable { public var acute: Double; public var chronic: Double; public var ratio: Double?; public var status: String }
public enum CardioLoadEngine {
    public static func calculate(_ dailyLoads: [Double]) -> CardioLoad {
        var acute = 0.0, chronic = 0.0
        for value in dailyLoads { let v = max(0, value.isFinite ? value : 0); acute += (v - acute) * (1 - exp(-1 / 7.0)); chronic += (v - chronic) * (1 - exp(-1 / 42.0)) }
        let ratio = chronic > 0.01 ? acute / chronic : nil
        let status = dailyLoads.count < 14 ? "calibrating" : (ratio ?? 0) < 0.8 ? "detraining" : (ratio ?? 0) > 1.5 ? "highLoad" : (ratio ?? 0) > 1.1 ? "productive" : "maintaining"
        return .init(acute: acute, chronic: chronic, ratio: ratio, status: status)
    }
}
public enum StressEngine {
    /// Physiological activation from heart-rate reserve.
    ///
    /// The previous version compared the day's heart rate against the *resting*
    /// heart-rate baseline. Awake, you are always above your resting rate, so
    /// the deviation saturated at its ±3 bound and the result sat at
    /// `30 + 3 × 22 = 96` all day — and, because energy drains on stress, it
    /// emptied the body battery along with it.
    ///
    /// Reserve is the standard framing (Karvonen): where the current rate sits
    /// between resting and maximum. It is bounded by construction, so it cannot
    /// pin, and it means the same thing for a trained and an untrained heart.
    ///
    /// - Parameters:
    ///   - movement: 0–1 activity in the interval. An elevated rate that
    ///     movement explains is not activation, so it is discounted.
    public static func calculate(hr: Double?, resting: Double?, maximum: Double, hrv: Double?, hrvBaseline: Baseline?, movement: Double, workout: Bool) -> Double? {
        guard !workout, let hr, hr.isFinite, let resting, resting.isFinite,
              maximum.isFinite, maximum > resting + 20 else { return nil }
        let reserve = Statistics.clamp((hr - resting) / (maximum - resting), 0, 1)
        // 45% of reserve is treated as full activation; beyond that the
        // interval is effort rather than stress and is excluded anyway.
        let activation = Statistics.clamp(reserve / 0.45 * 100)

        // Suppressed variability adds to the reading, but only once the
        // personal baseline has something to say.
        let variability = hrv.flatMap { current in
            hrvBaseline.flatMap { baseline in
                baseline.count >= 3 ? Statistics.clamp(50 - baseline.z(current, epsilon: 3) * 20) : nil
            }
        }
        let explained = Statistics.clamp(movement.isFinite ? movement : 0, 0, 1)
        return ScoreMath.weighted([
            .init("hr", value: hr, score: activation, weight: 60, unit: "bpm"),
            .init("hrv", value: hrv, score: variability, weight: 30, unit: "ms"),
            // Movement is context: it pulls the reading down, because a raised
            // rate you can account for is not the same signal.
            .init("movement", value: explained, score: Statistics.clamp(activation - explained * 55), weight: 10)
        ], confidence: .low).value
    }

    /// Five bands for the day chart, low to high.
    public static func band(_ value: Double) -> String {
        switch value {
        case ..<25: "veryLow"
        case ..<40: "low"
        case ..<60: "moderate"
        case ..<78: "high"
        default: "veryHigh"
        }
    }
}
public enum EnergyBankEngine {
    /// Level the night starts from. Unlike the previous version this is the
    /// level *before* sleeping, so the simulation can show the night's recharge
    /// instead of jumping straight to a woken-up value.
    public static func nightStart(previousEvening: Double?, recovery: Double?, sleep: Double?) -> Double {
        if let previousEvening, previousEvening.isFinite { return Statistics.clamp(previousEvening) }
        // No prior day: start from the lower end of whatever the day's own
        // signals suggest, so the first night still shows a recharge.
        let seed = [recovery, sleep].compactMap { $0 }.filter(\.isFinite)
        guard let mean = Statistics.mean(seed) else { return 35 }
        return Statistics.clamp(mean * 0.45, 5, 55)
    }
    /// Level a night of sleep recharges to, used as the ceiling of the
    /// overnight ramp. Sleep alone gives a provisional estimate while the
    /// personal baseline calibrates.
    public static func morning(previous: Double?, recovery: Double?, sleep: Double?) -> Double? {
        guard let sleep, sleep.isFinite else {
            // Without a scored night the day continues from the prior evening
            // rather than disappearing entirely.
            guard let previous, previous.isFinite else { return nil }
            return Statistics.clamp(previous)
        }
        guard let recovery, recovery.isFinite else { return Statistics.clamp(sleep) }
        if let previous, previous.isFinite { return Statistics.clamp(0.3 * previous + 0.45 * recovery + 0.25 * sleep) }
        return Statistics.clamp(0.65 * recovery + 0.35 * sleep)
    }
    /// One simulation step, returning the breakdown so the battery view can
    /// explain what charged and what drained it.
    ///
    /// Waking time can never net positive. Resting quietly *slows* the drain;
    /// it does not reverse it. The previous version granted a flat restoration
    /// whenever observed activation was low, which was harmless while stress
    /// was pinned high but, once activation read correctly, applied for most of
    /// a calm day and walked the level up to 100. Only sleep and naps add.
    public static func step(energy: Double, stress: Double?, load: Double, resting: Bool, minutes: Double = 15, napMinutes: Double = 0, asleepMinutes: Double = 0, sleepRate: Double = 0) -> EnergyStep {
        let energy = energy.isFinite ? Statistics.clamp(energy) : 0
        guard minutes.isFinite, minutes > 0 else { return .init(value: energy) }
        let stress = stress.flatMap { $0.isFinite ? Statistics.clamp($0) : nil }
        let load = load.isFinite ? max(0, load) : 0
        let napMinutes = napMinutes.isFinite ? min(minutes, max(0, napMinutes)) : 0
        let asleepMinutes = asleepMinutes.isFinite ? min(minutes, max(0, asleepMinutes)) : 0
        let factor = minutes / 15
        let asleep = asleepMinutes >= minutes * 0.5

        // Activation above a calm baseline costs energy. The threshold sits at
        // 25 because heart-rate reserve puts an ordinary calm waking interval
        // in the low twenties; measuring from 35 left most of the day free.
        let stressDrain = asleep ? 0 : pow(max(0, (stress ?? 30) - 25) / 75, 1.5) * 3.0 * factor
        let loadDrain = load * 0.1
        // Sleeping suspends the waking cost; resting quietly reduces it.
        let calm = resting && (stress ?? 100) < 25
        let baselineDrain = asleep ? 0 : (calm ? 0.12 : 0.35) * factor
        // Only real sleep restores: the overnight ramp, and naps.
        let restoration = asleepMinutes * max(0, sleepRate) + min(12, napMinutes * 0.15)

        let value = Statistics.clamp(energy + restoration - stressDrain - loadDrain - baselineDrain)
        return .init(value: value, restoration: restoration, stressDrain: stressDrain,
                     loadDrain: loadDrain, baselineDrain: baselineDrain, asleep: asleep)
    }

    /// Points per asleep minute needed to climb from `start` to `target` across
    /// `minutes` of sleep. Keeps the overnight ramp tied to the scored night
    /// instead of inventing a fixed recharge speed.
    public static func sleepRate(start: Double, target: Double, minutes: Double) -> Double {
        guard minutes > 0, start.isFinite, target.isFinite, target > start else { return 0 }
        return (target - start) / minutes
    }
}
public struct EnergyStep: Sendable, Equatable {
    public var value: Double
    public var restoration: Double = 0
    public var stressDrain: Double = 0
    public var loadDrain: Double = 0
    public var baselineDrain: Double = 0
    public var asleep: Bool = false
}
public enum StrengthEngine {
    public static func estimated1RM(weight: Double, reps: Int) -> Double? { guard weight > 0, (1...12).contains(reps) else { return nil }; return reps == 1 ? weight : weight * (1 + Double(reps) / 30) }
    public static func load(_ set: StrengthSet, estimated1RM: Double?) -> Double {
        guard set.completed, set.reps > 0 else { return 0 }
        let intensity = estimated1RM.flatMap { $0 > 0 ? set.weightKg / $0 : nil } ?? 0.5
        return Double(set.reps) * pow(Statistics.clamp(intensity, 0.1, 1.5), 1.5) * Statistics.clamp(set.rpe, 1, 10) / 10
    }
    public static func plates(total: Double, bar: Double = 20, available: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) -> (plates: [Double], remainder: Double) {
        var remaining = max(0, (total - bar) / 2), plates: [Double] = []
        for weight in available.filter({ $0 > 0 }).sorted(by: >) { while remaining + 0.0001 >= weight { plates.append(weight); remaining -= weight } }
        return (plates, max(0, remaining * 2))
    }
}
public struct HabitObservation: Sendable { public var present: Bool; public var outcome: Double; public init(present: Bool, outcome: Double) { self.present = present; self.outcome = outcome } }
public struct HabitInsight: Sendable { public var difference: Double; public var yesCount: Int; public var noCount: Int; public var lower: Double; public var upper: Double }
public enum JournalInsightEngine {
    public static func calculate(_ observations: [HabitObservation]) -> HabitInsight? {
        let yes = observations.filter { $0.present && $0.outcome.isFinite }.map(\.outcome)
        let no = observations.filter { !$0.present && $0.outcome.isFinite }.map(\.outcome)
        guard yes.count >= 5, no.count >= 5, let a = Statistics.mean(yes), let b = Statistics.mean(no) else { return nil }
        var state: UInt64 = 42
        func next(_ n: Int) -> Int { state = state &* 6364136223846793005 &+ 1; return Int((state >> 32) % UInt64(n)) }
        var differences: [Double] = []
        for _ in 0..<1000 {
            let ya = (0..<yes.count).reduce(0.0) { sum, _ in sum + yes[next(yes.count)] } / Double(yes.count)
            let na = (0..<no.count).reduce(0.0) { sum, _ in sum + no[next(no.count)] } / Double(no.count)
            differences.append(ya - na)
        }
        return .init(difference: a - b, yesCount: yes.count, noCount: no.count, lower: Statistics.percentile(differences, 0.025) ?? 0, upper: Statistics.percentile(differences, 0.975) ?? 0)
    }
}
public enum NutritionScoreEngine {
    public static func calculate(nutrients: [String: Double], targets: [String: Double]) -> ScoreResult {
        let weights = ["protein": 25.0, "fiber": 25, "water": 15, "sodium": 15, "sugar": 10, "saturatedFat": 10]
        let contributors = weights.keys.sorted().map { key -> Contributor in
            let value = nutrients[key], goal = targets[key]
            let score: Double? = value.flatMap { value in goal.flatMap { target in
                guard target > 0 else { return nil }
                if ["sodium", "sugar", "saturatedFat"].contains(key) { return Statistics.clamp(100 - max(0, value / target - 1) * 70) }
                return Statistics.clamp(value / target * 100)
            } }
            return .init(key, value: value, baseline: goal, score: score, weight: weights[key] ?? 0)
        }
        return ScoreMath.weighted(contributors, confidence: .low)
    }
}
public enum CycleEngine {
    public static func nextPeriod(starts: [Date], calendar: Calendar = .current) -> Date? {
        let dates = starts.sorted(); guard dates.count >= 3, let last = dates.last else { return nil }
        let lengths = zip(dates, dates.dropFirst()).compactMap { calendar.dateComponents([.day], from: $0, to: $1).day }.filter { (15...60).contains($0) }.map(Double.init)
        guard lengths.count >= 2, let typical = Statistics.median(lengths) else { return nil }
        return calendar.date(byAdding: .day, value: Int(typical.rounded()), to: last)
    }
}
public enum TrendEngine {
    public static func projection(_ points: [TimelinePoint], days: Double = 30) -> Double? {
        guard points.count >= 14, let first = points.first, let last = points.last, last.date.timeIntervalSince(first.date) >= 14 * 86400 else { return nil }
        let x = points.map { $0.date.timeIntervalSince(first.date) / 86400 }, y = points.map(\.value)
        guard let mx = Statistics.mean(x), let my = Statistics.mean(y) else { return nil }
        let denominator = x.reduce(0) { $0 + pow($1 - mx, 2) }; guard denominator > 0 else { return nil }
        let slope = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / denominator
        return max(0, my + slope * ((x.last ?? 0) + days - mx))
    }
}
