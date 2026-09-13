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

        // Duration peaks at the estimated need and is not improved by
        // exceeding it. Long sleep is associated with worse outcomes and
        // usually signals debt or illness, so past 115% of need the score eases
        // back rather than sitting at a flat hundred.
        let ratio = session.asleepMinutes / need
        let duration = ratio <= 1
            ? Statistics.clamp(ratio * 100)
            : Statistics.clamp(100 - max(0, ratio - 1.15) * 150)

        // Efficiency stretched across the band that carries meaning. Mapping
        // the percentage straight through gave 80 points — a pass — to 80%,
        // which is the *lower edge* of normal.
        let efficiency = Statistics.clamp(session.asleepMinutes / max(1, session.bedMinutes) * 100)
        let efficiencyScore = Statistics.clamp((efficiency - 65) / 30 * 100)

        // Wake after sleep onset. Normative WASO for healthy adults runs to
        // about 30 minutes and rises with age, so 20 minutes is forgiven and
        // the scale then falls at a rate that separates a settled night from a
        // broken one.
        let awake = session.segments.filter { $0.stage == .awake }.reduce(0) { $0 + $1.minutes }
        let continuity = Statistics.clamp(100 - max(0, awake - 20) * 1.2)

        let stageScore = architectureScore(session)
        // The regularity index where it exists; the spread of bedtimes only as
        // a stand-in until there are enough consecutive days for the index.
        let consistency = regularity ?? Statistics.circularDeviation(onsetHistory).map { Statistics.clamp(100 - $0 * 0.6) }

        let contributors: [Contributor] = [
            .init("duration", value: session.asleepMinutes, score: duration, weight: 35, unit: "min"),
            .init("efficiency", value: efficiency, score: efficiencyScore, weight: 20, unit: "%"),
            .init("continuity", value: awake, score: continuity, weight: 15, unit: "min"),
            .init("stages", value: stageScore.deepPercent, score: stageScore.score, weight: 15, unit: "%"),
            .init("consistency", value: regularity, score: consistency, weight: 10),
            .init("hrDip", value: hrDip, score: hrDip.map { Statistics.clamp(($0 - 5) / 15 * 100) }, weight: 5, unit: "%")
        ]
        let observations = max(stageHistory.count, onsetHistory.count)
        let report = ConfidenceEngine.evaluate(contributors: contributors, observations: max(observations, 7), target: 14)
        var result = ScoreMath.weighted(contributors, confidence: report.level)
        result.report = report
        return result
    }

    /// Published adult sleep architecture: N3 (deep) 15–25% of total sleep time
    /// and REM 20–25%. Scoring against these instead of against the sleeper's
    /// own median matters: the previous version returned 85 points simply for
    /// being typical *for you*, so consistently poor architecture scored well.
    ///
    /// Returns nil when the source reports no staging at all, because a night
    /// recorded as undifferentiated sleep says nothing about architecture.
    public static func architectureScore(_ session: SleepSession) -> (score: Double?, deepPercent: Double?, remPercent: Double?) {
        let asleep = session.asleepMinutes
        guard asleep > 0 else { return (nil, nil, nil) }
        func minutes(_ stage: SleepStage) -> Double {
            session.segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
        }
        let deep = minutes(.deep), rem = minutes(.rem)
        guard deep > 0 || rem > 0 else { return (nil, nil, nil) }
        let deepPercent = deep / asleep * 100, remPercent = rem / asleep * 100
        // Deep and REM weigh equally: both are restorative and both are
        // reported by the watch.
        let score = (band(deepPercent, low: 15, high: 25) + band(remPercent, low: 20, high: 25)) / 2
        return (Statistics.clamp(score), deepPercent, remPercent)
    }

    /// Full marks inside the reference band. Below it the penalty is steep —
    /// half the lower bound scores zero — because a shortfall of restorative
    /// sleep is the thing worth flagging. Above it the penalty is gentle, since
    /// extra deep or REM sleep is not itself a problem.
    private static func band(_ value: Double, low: Double, high: Double) -> Double {
        if value < low { return Statistics.clamp(100 - (low - value) / low * 200) }
        if value > high { return Statistics.clamp(100 - (value - high) / high * 100) }
        return 100
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
