import Foundation

/// A band on a published reference scale, with the value that produced it.
public struct BodyBand: Sendable, Equatable, Identifiable {
    public var id: String { key }
    /// Localisation key of the measure: "bmi", "bodyFat", "leanMass"…
    public var key: String
    public var value: Double
    public var unit: String
    /// Localisation key of the band: "bandLow", "bandHealthy", "bandHigh"…
    public var band: String
    /// 0–1 position within the scale, for drawing a marker.
    public var position: Double
    /// The band boundaries being used, so the scale can be labelled.
    public var thresholds: [Double]
}

public struct BodyAssessment: Sendable, Equatable {
    public var bands: [BodyBand]
    /// Change over the window, per measure key, in the measure's own unit.
    public var changes: [String: Double]
    public var report: ConfidenceReport
}

/// Interprets what a scale reports, using published population scales.
///
/// These are population references, not personal targets, and BMI in particular
/// cannot tell muscle from fat — which is exactly why it is shown next to body
/// fat rather than on its own.
public enum BodyCompositionEngine {
    /// WHO adult BMI categories.
    public static let bmiThresholds: [Double] = [18.5, 25, 30]

    /// ACE body-fat ranges. Sex-specific; without a declared sex nothing is
    /// banded, because applying the male scale to everyone would be wrong.
    public static func bodyFatThresholds(sex: String?) -> [Double]? {
        switch sex {
        case "male": [6, 14, 18, 25]
        case "female": [14, 21, 25, 32]
        default: nil
        }
    }

    public static func assess(weight: [Double], bodyFat: [Double], leanMass: [Double], bmi: [Double], sex: String?, observations: Int) -> BodyAssessment {
        var bands: [BodyBand] = []

        if let value = bmi.last, value.isFinite {
            bands.append(.init(key: "bmi", value: value, unit: "",
                               band: band(value, bmiThresholds, ["bandLow", "bandHealthy", "bandHigh", "bandVeryHigh"]),
                               position: position(value, lower: 15, upper: 35),
                               thresholds: bmiThresholds))
        }
        if let value = bodyFat.last, value.isFinite, let thresholds = bodyFatThresholds(sex: sex) {
            bands.append(.init(key: "bodyFat", value: value, unit: "%",
                               band: band(value, thresholds, ["bandVeryLow", "bandAthletic", "bandFit", "bandAverage", "bandHigh"]),
                               position: position(value, lower: 3, upper: 40),
                               thresholds: thresholds))
        }

        var changes: [String: Double] = [:]
        for (key, series) in ["weight": weight, "bodyFat": bodyFat, "leanMass": leanMass, "bmi": bmi] {
            let finite = series.filter(\.isFinite)
            guard let first = finite.first, let last = finite.last, finite.count >= 2 else { continue }
            changes[key] = last - first
        }

        // Confidence here is about how much the scale has actually been used.
        let contributors = [
            Contributor("weight", score: weight.last, weight: 40, unit: "kg"),
            Contributor("bodyFat", score: bodyFat.last, weight: 30, unit: "%"),
            Contributor("leanMass", score: leanMass.last, weight: 20, unit: "kg"),
            Contributor("bmi", score: bmi.last, weight: 10, unit: "")
        ]
        return .init(bands: bands, changes: changes,
                     report: ConfidenceEngine.evaluate(contributors: contributors, observations: observations, target: 12))
    }

    private static func band(_ value: Double, _ thresholds: [Double], _ labels: [String]) -> String {
        for (index, threshold) in thresholds.enumerated() where value < threshold { return labels[index] }
        return labels[min(labels.count - 1, thresholds.count)]
    }
    private static func position(_ value: Double, lower: Double, upper: Double) -> Double {
        Statistics.clamp((value - lower) / max(0.001, upper - lower), 0, 1)
    }
}
