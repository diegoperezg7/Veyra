import Foundation

/// A localisable sentence: a key plus its already-formatted arguments. The
/// narrator never builds display strings itself, so Spanish and English come
/// from the string catalogue rather than from engine code.
public struct NarrativeLine: Sendable, Equatable, Identifiable {
    public var key: String
    public var arguments: [String]
    public var id: String { key + arguments.joined(separator: "|") }
    public init(_ key: String, _ arguments: [String] = []) { self.key = key; self.arguments = arguments }
}

public struct MetricNarrative: Sendable, Equatable {
    /// One-line verdict.
    public var headline: NarrativeLine
    /// Why the score landed where it did.
    public var detail: [NarrativeLine]
    public var confidencePercent: Double
    public var limitations: [String]
}

/// Replaces the removed conversational coach. Deterministic, local, and derived
/// only from what was actually measured.
public enum MetricNarrator {
    public static func describe(_ metric: Metric, snapshot: DailySnapshot, history: [DailySnapshot], calendar: Calendar = .current) -> MetricNarrative {
        let score = snapshot.score(metric)
        let report = score.report
        guard let value = score.value else {
            return .init(headline: .init("narrative.\(metric.rawValue).calibrating"),
                         detail: [.init("narrative.needsData")],
                         confidencePercent: report?.percent ?? 0,
                         limitations: report?.limitations ?? ["confidenceShortHistory"])
        }

        var detail: [NarrativeLine] = []

        // Which component moved the score most, relative to a neutral 50.
        let ranked = score.contributors
            .compactMap { contributor -> (Contributor, Double)? in
                guard let componentScore = contributor.score, componentScore.isFinite, contributor.weight > 0 else { return nil }
                return (contributor, (componentScore - 50) * contributor.weight / 100)
            }
            .sorted { abs($0.1) > abs($1.1) }
        if let (leader, impact) = ranked.first {
            detail.append(.init(impact >= 0 ? "narrative.leadingPositive" : "narrative.leadingNegative",
                                [leader.id, format(leader.value, unit: leader.unit)]))
        }

        // Movement against the personal baseline of recent comparable days.
        let past = history.filter { $0.date < snapshot.date }.compactMap { $0.score(metric).value }
        if let baseline = BaselineEngine.calculate(Array(past.suffix(28))), baseline.count >= 5 {
            let delta = value - baseline.median
            if abs(delta) >= 4 {
                detail.append(.init(delta > 0 ? "narrative.aboveBaseline" : "narrative.belowBaseline",
                                    [format(abs(delta), unit: ""), format(baseline.median, unit: "")]))
            } else {
                detail.append(.init("narrative.atBaseline", [format(baseline.median, unit: "")]))
            }
        }

        // Seven-day direction, only once there is a full week to compare.
        let week = Array(past.suffix(7))
        if week.count >= 7, let recent = Statistics.mean(Array(week.suffix(3))), let earlier = Statistics.mean(Array(week.prefix(3))) {
            let slope = recent - earlier
            if abs(slope) >= 3 {
                detail.append(.init(slope > 0 ? "narrative.trendUp" : "narrative.trendDown", [format(abs(slope), unit: "")]))
            }
        }

        detail.append(contentsOf: metricSpecific(metric, snapshot: snapshot))

        return .init(headline: .init("narrative.\(metric.rawValue).\(band(value))"),
                     detail: detail,
                     confidencePercent: score.confidencePercent,
                     limitations: report?.limitations ?? [])
    }

    private static func metricSpecific(_ metric: Metric, snapshot: DailySnapshot) -> [NarrativeLine] {
        switch metric {
        case .sleep:
            guard let main = snapshot.sleepSessions.max(by: { $0.asleepMinutes < $1.asleepMinutes }) else { return [] }
            var lines = [NarrativeLine("narrative.sleep.duration", [minutes(main.asleepMinutes), minutes(snapshot.sleepNeed)])]
            if snapshot.sleepDebt >= 30 { lines.append(.init("narrative.sleep.debt", [minutes(snapshot.sleepDebt)])) }
            return lines
        case .strain:
            guard let target = snapshot.targetStrain, let value = snapshot.score(.strain).value else { return [] }
            if value < target * 0.9 { return [.init("narrative.strain.belowTarget", [format(target, unit: "")])] }
            if value > target * 1.1 { return [.init("narrative.strain.aboveTarget", [format(target, unit: "")])] }
            return [.init("narrative.strain.onTarget", [format(target, unit: "")])]
        case .energy:
            let detail = snapshot.energyDetail ?? []
            guard !detail.isEmpty else { return [] }
            let recharged = detail.reduce(0) { $0 + $1.restoration }
            let spent = detail.reduce(0) { $0 + $1.stressDrain + $1.loadDrain + $1.baselineDrain }
            return [.init("narrative.energy.balance", [format(recharged, unit: ""), format(spent, unit: "")])]
        case .stress:
            let values = snapshot.stress.map(\.value)
            guard let peak = values.max(), let average = Statistics.mean(values) else { return [] }
            return [.init("narrative.stress.range", [format(average, unit: ""), format(peak, unit: "")])]
        case .recovery:
            return []
        }
    }

    /// The day read as a whole rather than metric by metric. The useful
    /// sentence is usually a contrast — poor sleep but strong recovery, good
    /// recovery but no training — because that is what a single score cannot
    /// say. Deterministic, local, and derived only from what was measured.
    public static func briefing(snapshot: DailySnapshot, history: [DailySnapshot]) -> MetricNarrative {
        func score(_ metric: Metric) -> Double? { snapshot.score(metric).value }
        let sleep = score(.sleep), recovery = score(.recovery)
        let strain = score(.strain), stress = score(.stress), energy = score(.energy)

        var headline = NarrativeLine("briefing.learning")
        var lines: [NarrativeLine] = []

        // Ordered by how much the pairing changes what you would do today.
        if let sleep, let recovery, sleep < 45, recovery >= 65 {
            headline = .init("briefing.sleepPoorRecoveryGood", [number(sleep), number(recovery)])
        } else if let sleep, let recovery, sleep >= 65, recovery < 45 {
            headline = .init("briefing.sleepGoodRecoveryPoor", [number(sleep), number(recovery)])
        } else if let recovery, let strain, recovery < 45, strain >= 60 {
            headline = .init("briefing.recoveryPoorStrainHigh", [number(recovery), number(strain)])
        } else if let recovery, let strain, recovery >= 65, strain < 35 {
            headline = .init("briefing.recoveryGoodStrainLow", [number(recovery)])
        } else if let stress, stress >= 65 {
            headline = .init("briefing.stressHigh", [number(stress)])
        } else if let energy, energy < 35 {
            headline = .init("briefing.energyLow", [number(energy)])
        } else if let recovery, let sleep, recovery >= 60, sleep >= 60 {
            headline = .init("briefing.balanced")
        }

        // One thing to do about it, chosen from the same observations.
        if snapshot.sleepDebt >= 60 {
            lines.append(.init("briefing.actionEarlyNight", [minutes(snapshot.sleepDebt)]))
        } else if let stress, stress >= 65 {
            lines.append(.init("briefing.actionDownregulate"))
        } else if let strain, let target = snapshot.targetStrain, strain > target * 1.15 {
            lines.append(.init("briefing.actionEaseOff", [number(target)]))
        } else if let strain, let target = snapshot.targetStrain, strain < target * 0.75 {
            lines.append(.init("briefing.actionRoomToTrain", [number(target)]))
        } else if recovery != nil || sleep != nil {
            lines.append(.init("briefing.actionKeepGoing"))
        }

        // Confidence of the weakest score the headline leans on, so the card
        // never looks surer than the numbers under it.
        let used = [sleep != nil ? snapshot.score(.sleep) : nil,
                    recovery != nil ? snapshot.score(.recovery) : nil].compactMap { $0 }
        let percent = used.map(\.confidencePercent).min() ?? 0
        return .init(headline: headline, detail: lines, confidencePercent: percent,
                     limitations: used.flatMap { $0.report?.limitations ?? [] })
    }

    /// Five bands. Stress reads the opposite way round: a high number is bad.
    public static func band(_ value: Double) -> String {
        switch value {
        case ..<20: "veryLow"
        case ..<40: "low"
        case ..<60: "moderate"
        case ..<80: "high"
        default: "veryHigh"
        }
    }

    private static func format(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "—" }
        // Minutes are read as hours and minutes by people, never as "499.1 min".
        if unit == "min" { return minutes(value) }
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return unit.isEmpty ? text : text + " " + unit
    }
    private static func number(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
    private static func minutes(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let total = max(0, Int(value.rounded()))
        return "\(total / 60)h \(total % 60)m"
    }
}
