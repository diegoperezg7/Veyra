import Foundation
public enum SleepEngine {
    public static func sessions(_ input: [SleepSegment], preferredSource: String? = nil, splitMinutes: Double = 90) -> [SleepSession] {
        let valid = input.filter { $0.end > $0.start }
        let sources = Dictionary(grouping: valid, by: \.source)
        // Source selection is scoped to the queried night; never combine stage estimates from trackers.
        let source = preferredSource.flatMap { sources[$0] != nil ? $0 : nil }
            ?? sources.keys.filter { $0.localizedCaseInsensitiveContains("watch") || $0.localizedCaseInsensitiveContains("apple") }.sorted().first
            ?? sources.max(by: { $0.value.reduce(0) { $0 + ($1.stage.asleep ? $1.minutes : 0) } < $1.value.reduce(0) { $0 + ($1.stage.asleep ? $1.minutes : 0) } })?.key
        let selected = source.flatMap { sources[$0] } ?? []
        let boundaries = Set(selected.flatMap { [$0.start, $0.end] }).sorted()
        var normalized: [SleepSegment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let covering = selected.filter { $0.start < end && $0.end > start }
            guard let segment = covering.sorted(by: { priority($0.stage) > priority($1.stage) }).first else { continue }
            if let last = normalized.last, last.stage == segment.stage, last.end == start {
                normalized[normalized.count - 1].end = end
            } else { normalized.append(.init(start: start, end: end, stage: segment.stage, source: segment.source)) }
        }
        var groups: [[SleepSegment]] = []
        for segment in normalized {
            if let last = groups.last?.last, segment.start.timeIntervalSince(last.end) <= splitMinutes * 60 { groups[groups.count - 1].append(segment) }
            else { groups.append([segment]) }
        }
        return groups.map { SleepSession(segments: $0) }.filter { $0.asleepMinutes >= 15 }
    }
    private static func priority(_ stage: SleepStage) -> Int { switch stage { case .awake: 6; case .deep, .rem, .core: 5; case .unspecified: 2; case .inBed: 1 } }
    /// - Parameter regularity: Sleep Regularity Index, 0–100, when enough
    ///   consecutive days exist. Preferred over the circular deviation of
    ///   bedtimes, which only measures spread around your own average.
    public static func score(_ session: SleepSession?, need: Double, stageHistory: [Double] = [], onsetHistory: [Double] = [], hrDip: Double? = nil, regularity: Double? = nil) -> ScoreResult {
        guard let session, session.asleepMinutes > 0, need > 0 else { return .unavailable }
        let duration = Statistics.clamp(session.asleepMinutes / need * 100)
        let efficiency = Statistics.clamp(session.asleepMinutes / max(1, session.bedMinutes) * 100)
        let awake = session.segments.filter { $0.stage == .awake }.reduce(0) { $0 + $1.minutes }
        let continuity = Statistics.clamp(100 - max(0, awake - 10) * 0.8)
        let restorative = session.segments.filter { $0.stage == .deep || $0.stage == .rem }.reduce(0) { $0 + $1.minutes } / session.asleepMinutes
        let stageScore: Double? = BaselineEngine.calculate(stageHistory).flatMap { $0.count >= 7 && restorative > 0 ? Statistics.clamp(85 - abs($0.z(restorative, epsilon: 0.03)) * 15) : nil }
        // The regularity index where it exists; the spread of bedtimes only as
        // a stand-in until there are enough consecutive days for the index.
        let consistency = regularity ?? Statistics.circularDeviation(onsetHistory).map { Statistics.clamp(100 - $0 * 0.6) }
        let contributors: [Contributor] = [
            .init("duration", value: session.asleepMinutes, score: duration, weight: 35, unit: "min"),
            .init("efficiency", value: efficiency, score: efficiency, weight: 20, unit: "%"),
            .init("continuity", value: awake, score: continuity, weight: 15, unit: "min"),
            .init("stages", score: stageScore, weight: 15), .init("consistency", score: consistency, weight: 10),
            .init("hrDip", value: hrDip, score: hrDip.map { Statistics.clamp($0 * 5) }, weight: 5, unit: "%")
        ]
        // A scored night needs no long baseline for duration and efficiency, so
        // maturity is driven by the stage/consistency history behind it.
        let observations = max(stageHistory.count, onsetHistory.count)
        let report = ConfidenceEngine.evaluate(contributors: contributors, observations: max(observations, 7), target: 14)
        var result = ScoreMath.weighted(contributors, confidence: report.level)
        result.report = report
        return result
    }
    /// Overnight heart-rate dip as a percentage of the waking reference. A
    /// deeper dip indicates stronger parasympathetic recovery during sleep.
    public static func heartRateDip(nightly: [Double], waking: [Double]) -> Double? {
        guard let low = Statistics.percentile(nightly.filter(\.isFinite), 0.10),
              let reference = Statistics.median(waking.filter(\.isFinite)),
              reference > 0, low > 0, low < reference else { return nil }
        return Statistics.clamp((reference - low) / reference * 100, 0, 40)
    }
    public static func need(base: Double = 480, debt: Double, previousStrain: Double) -> Double { Statistics.clamp(base + min(120, max(0, debt) * 0.35) + min(60, max(0, previousStrain) * 0.4), 360, 600) }
    public static func debt(previous: Double, need: Double, restorative: Double) -> Double { Statistics.clamp(0.85 * previous + need - restorative, 0, 240) }
    public static func latency(_ session: SleepSession) -> Double? {
        guard let bed = session.segments.first(where: { $0.stage == .inBed }), let asleep = session.segments.first(where: { $0.stage.asleep }), bed.start <= asleep.start else { return nil }
        return asleep.start.timeIntervalSince(bed.start) / 60
    }
}
public enum RecoveryEngine {
    public static let weights: [String: Double] = ["hrv": 30, "rhr": 20, "sleep": 25, "respiratory": 10, "temperature": 10, "oxygen": 5]
    /// Three observations are enough for a provisional personal reference. The
    /// result is reported with a correspondingly low confidence percentage
    /// rather than withheld, which previously left the app silent for a week.
    public static let minimumObservations = 3
    public static func calculate(values: [String: Double], histories: [String: [Double]], sleep: ScoreResult, customWeights: [String: Double] = weights, dataAgeInDays: Double = 0) -> ScoreResult {
        let keys = ["hrv", "rhr", "sleep", "respiratory", "temperature", "oxygen"]
        let contributors = keys.map { key -> Contributor in
            let weight = customWeights[key] ?? weights[key] ?? 0
            if key == "sleep" { return .init(key, value: sleep.value, score: sleep.value, weight: weight) }
            let baseline = BaselineEngine.calculate(histories[key] ?? [])
            let value = values[key]
            let score: Double? = value.flatMap { current in
                guard current.isFinite, let baseline, baseline.count >= minimumObservations else { return nil }
                let z = baseline.z(current, epsilon: key == "temperature" ? 0.1 : key == "oxygen" ? 1 : 1)
                switch key {
                case "hrv": return Statistics.clamp(70 + z * 15)
                case "rhr": return Statistics.clamp(70 - z * 15)
                case "oxygen": return Statistics.clamp(85 + min(0, z) * 15)
                default: return Statistics.clamp(85 - abs(z) * 15)
                }
            }
            return .init(key, value: value, baseline: baseline?.median, score: score, weight: weight, unit: key == "hrv" ? "ms" : key == "temperature" ? "°C" : key == "oxygen" ? "%" : "/min")
        }
        let count = ["hrv", "rhr"].map { histories[$0]?.count ?? 0 }.max() ?? 0
        let report = ConfidenceEngine.evaluate(contributors: contributors, observations: count, ageInDays: dataAgeInDays)
        guard count >= minimumObservations, contributors.contains(where: { $0.id != "sleep" && $0.score != nil }) else {
            return .init(value: nil, contributors: contributors, report: report)
        }
        var result = ScoreMath.weighted(contributors, confidence: report.level)
        result.report = report
        return result
    }
}
