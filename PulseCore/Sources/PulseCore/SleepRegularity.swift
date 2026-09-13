import Foundation

/// The Sleep Regularity Index: the probability of being in the same state —
/// asleep or awake — at two points exactly 24 hours apart, rescaled so that a
/// perfectly repeated schedule scores 100 and a random one scores 0.
///
///     SRI = −100 + 200 × P(state at t equals state at t + 24 h)
///
/// Phillips et al. introduced it; the UK Biobank analysis of 60,000 people
/// found it a **stronger predictor of all-cause mortality than sleep duration**,
/// which is why it replaces the circular standard deviation of bedtimes that
/// this app used before. A standard deviation only measures spread around your
/// own average, and so cannot see a run of alternating early and late nights;
/// the index compares consecutive days directly.
///
/// References are listed in Documentation/ALGORITHMS.md.
public enum SleepRegularityEngine {
    /// Resolution of the state series. Five minutes is fine enough for wearable
    /// stage data and keeps the comparison cheap.
    public static let epochMinutes = 5.0
    /// Days below which the index is not reported. With two or three days a
    /// single unusual night dominates the result.
    public static let minimumDays = 7

    /// - Returns: 0–100, or nil when there are too few consecutive days.
    public static func index(sessions: [SleepSession], calendar: Calendar = .current, now: Date = Date()) -> Double? {
        let asleep = sessions.flatMap(\.segments).filter { $0.stage.asleep && $0.end > $0.start }
        guard let first = asleep.map(\.start).min(), let last = asleep.map(\.end).max() else { return nil }

        let start = calendar.startOfDay(for: first)
        let end = min(now, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last)
        let span = end.timeIntervalSince(start)
        let days = Int(span / 86_400)
        guard days >= minimumDays else { return nil }

        let step = epochMinutes * 60
        let epochs = Int(span / step)
        guard epochs > 0 else { return nil }

        // Sleep state per epoch, resolved once so the day-to-day comparison is
        // a lookup rather than a search.
        var state = [Bool](repeating: false, count: epochs)
        for segment in asleep {
            let from = max(0, Int(segment.start.timeIntervalSince(start) / step))
            let to = min(epochs, Int(ceil(segment.end.timeIntervalSince(start) / step)))
            guard from < to else { continue }
            for index in from..<to { state[index] = true }
        }

        let dayEpochs = Int(86_400 / step)
        guard epochs > dayEpochs else { return nil }
        var matches = 0, comparisons = 0
        for index in 0..<(epochs - dayEpochs) {
            comparisons += 1
            if state[index] == state[index + dayEpochs] { matches += 1 }
        }
        guard comparisons > 0 else { return nil }
        return Statistics.clamp(-100 + 200 * Double(matches) / Double(comparisons))
    }
}

/// Heart-rate recovery one minute after exercise, as a score.
///
/// A fall of 12 bpm or less in the first minute is the classic abnormal cut-off
/// (Cole et al., *NEJM* 1999), associated with roughly four times the mortality
/// risk over six years. Above that, larger falls indicate better vagal
/// reactivation and better cardiorespiratory fitness.
public enum HeartRateRecoveryEngine {
    /// The clinical abnormality threshold, in beats per minute.
    public static let abnormalThreshold = 12.0

    public static func band(_ drop: Double) -> String {
        switch drop {
        case ..<12: "hrrPoor"
        case ..<20: "hrrFair"
        case ..<30: "hrrGood"
        default: "hrrExcellent"
        }
    }

    /// 0–100. The abnormal threshold sits at 25, so a value there or below
    /// reads unambiguously as a concern rather than as a middling result.
    public static func score(_ drop: Double) -> Double? {
        guard drop.isFinite, drop >= 0 else { return nil }
        if drop <= abnormalThreshold { return Statistics.clamp(drop / abnormalThreshold * 25) }
        return Statistics.clamp(25 + (drop - abnormalThreshold) / 24 * 75)
    }
}
