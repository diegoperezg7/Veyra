import Foundation
public enum Statistics {
    public static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 100) -> Double { value.isFinite ? min(upper, max(lower, value)) : lower }
    public static func median(_ values: [Double]) -> Double? { percentile(values, 0.5) }
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        let v = values.filter(\.isFinite).sorted(); guard !v.isEmpty else { return nil }
        let position = clamp(p, 0, 1) * Double(v.count - 1)
        let lo = Int(floor(position)), hi = Int(ceil(position))
        return v[lo] + (v[hi] - v[lo]) * (position - Double(lo))
    }
    public static func mean(_ values: [Double]) -> Double? { let v = values.filter(\.isFinite); return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    public static func deviation(_ values: [Double]) -> Double { guard let mean = mean(values), values.count > 1 else { return 0 }; return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)) }
    public static func rmssd(_ rr: [Double]) -> Double? {
        let pairs = zip(rr, rr.dropFirst()).filter { (300...2000).contains($0.0) && (300...2000).contains($0.1) && abs($0.0 - $0.1) < 300 }
        guard pairs.count >= 20 else { return nil }
        return sqrt(pairs.reduce(0) { $0 + pow($1.1 - $1.0, 2) } / Double(pairs.count))
    }
    public static func circularDeviation(_ minutes: [Double]) -> Double? {
        guard minutes.count >= 2 else { return nil }
        let angles = minutes.map { $0 / 1440 * 2 * .pi }
        let s = angles.map { sin($0) }.reduce(0, +) / Double(angles.count)
        let c = angles.map { cos($0) }.reduce(0, +) / Double(angles.count)
        return sqrt(-2 * log(max(0.0001, min(1, hypot(s, c))))) * 1440 / (2 * .pi)
    }
}
public struct Baseline: Codable, Sendable {
    public var median: Double
    public var mad: Double
    public var count: Int
    public var confidence: Confidence { count < 7 ? .insufficient : count < 14 ? .low : count < 28 ? .medium : .high }
    public func z(_ value: Double, epsilon: Double = 0.01) -> Double { Statistics.clamp((value - median) / max(mad * 1.4826, epsilon), -3, 3) }
}
public enum BaselineEngine {
    public static func calculate(_ history: [Double], window: Int = 42) -> Baseline? {
        let values = Array(history.filter(\.isFinite).suffix(max(1, window)))
        guard let median = Statistics.median(values) else { return nil }
        return Baseline(median: median, mad: Statistics.median(values.map { abs($0 - median) }) ?? 0, count: values.count)
    }
}
public enum ScoreMath {
    public static func weighted(_ contributors: [Contributor], confidence: Confidence) -> ScoreResult {
        let valid = contributors.filter { ($0.score?.isFinite ?? false) && $0.weight.isFinite && $0.weight > 0 }
        let total = valid.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return .init(value: nil, contributors: contributors) }
        let value = valid.reduce(0) { $0 + ($1.score ?? 0) * $1.weight } / total
        let quality: DataQuality = confidence == .insufficient ? .poor : valid.count == contributors.count ? .excellent : valid.count >= 3 ? .good : .partial
        return .init(value: Statistics.clamp(value), confidence: confidence, contributors: contributors, quality: quality)
    }
}
public enum DayBoundary {
    public static func biologicalDay(for date: Date, wakes: [Date], calendar: Calendar = .current) -> Date {
        wakes.filter { $0 <= date }.max() ?? calendar.startOfDay(for: date)
    }
    public static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = [], day = calendar.startOfDay(for: start)
        while day <= end { result.append(day); guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }; day = next }
        return result
    }
}
