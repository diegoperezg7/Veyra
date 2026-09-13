import Foundation

/// Why a score should or should not be trusted, expressed as a percentage
/// instead of a four-step enum. The enum is kept and derived from the
/// percentage so existing screens and stored snapshots keep working.
public struct ConfidenceReport: Codable, Sendable, Equatable {
    /// 0–100. The product of the three factors below.
    public var percent: Double
    /// Share of the score's weight that had real data behind it.
    public var coverage: Double
    /// How far the personal baseline has calibrated, 0–1.
    public var maturity: Double
    /// How recent the newest observation is, 0–1.
    public var recency: Double
    /// Localization keys naming what is holding the confidence down.
    public var limitations: [String]
    public var level: Confidence { ConfidenceEngine.level(for: percent) }

    public init(percent: Double, coverage: Double, maturity: Double, recency: Double, limitations: [String]) {
        self.percent = percent; self.coverage = coverage; self.maturity = maturity; self.recency = recency; self.limitations = limitations
    }
}

public enum ConfidenceEngine {
    /// Days of personal history after which a baseline is considered mature.
    public static let maturityTarget = 28.0
    /// Nothing here is ever certain: these are estimates from consumer sensors,
    /// so the reported confidence is capped short of 100%.
    public static let ceiling = 95.0

    public static func level(for percent: Double) -> Confidence {
        switch percent {
        case ..<20: .insufficient
        case ..<45: .low
        case ..<70: .medium
        default: .high
        }
    }

    /// - Parameters:
    ///   - contributors: the score's components; those without a `score` count
    ///     as missing weight rather than as a zero.
    ///   - observations: days of personal baseline behind the score.
    ///   - ageInDays: age of the newest observation.
    public static func evaluate(contributors: [Contributor],
                                observations: Int,
                                target: Double = maturityTarget,
                                ageInDays: Double = 0,
                                staleAfterDays: Double = 3) -> ConfidenceReport {
        let usable = contributors.filter { ($0.score?.isFinite ?? false) && $0.weight.isFinite && $0.weight > 0 }
        let total = contributors.filter { $0.weight.isFinite && $0.weight > 0 }.reduce(0) { $0 + $1.weight }
        let coverage = total > 0 ? Statistics.clamp(usable.reduce(0) { $0 + $1.weight } / total, 0, 1) : 0

        // Saturating curve: a full target window reaches ~0.95, three days ~0.27.
        // Linear growth would overstate a two-day baseline.
        let n = max(0, Double(observations))
        let maturity = target > 0 ? Statistics.clamp(1 - exp(-3 * n / target), 0, 1) : 0

        let age = ageInDays.isFinite ? max(0, ageInDays) : 0
        let recency = staleAfterDays > 0 ? Statistics.clamp(1 - max(0, age - 1) / staleAfterDays, 0.25, 1) : 1

        var limitations: [String] = []
        if coverage < 0.999 { limitations.append("confidenceMissingSignals") }
        if maturity < 0.8 { limitations.append("confidenceShortHistory") }
        if recency < 0.999 { limitations.append("confidenceStaleData") }

        return .init(percent: Statistics.clamp(ceiling * coverage * maturity * recency),
                     coverage: coverage, maturity: maturity, recency: recency, limitations: limitations)
    }
}
