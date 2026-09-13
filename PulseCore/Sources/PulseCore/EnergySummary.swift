import Foundation

/// The day's charge account, read off the simulated timeline.
public struct EnergySummary: Sendable, Equatable {
    /// Everything gained across the day, as a percentage of the scale.
    public var charged: Double
    /// Everything lost, as a positive number.
    public var spent: Double
    /// Level at the top of the most recent charging run, and when it happened.
    public var lastChargePeak: Double?
    public var lastChargeAt: Date?
    /// Contiguous stretches where the level was rising, for the charge strip.
    public var chargingSpans: [ClosedRange<Date>]
    /// The main sleep window inside the timeline, if the night is in it.
    public var sleepSpan: ClosedRange<Date>?

    public init(charged: Double = 0, spent: Double = 0, lastChargePeak: Double? = nil, lastChargeAt: Date? = nil, chargingSpans: [ClosedRange<Date>] = [], sleepSpan: ClosedRange<Date>? = nil) {
        self.charged = charged; self.spent = spent
        self.lastChargePeak = lastChargePeak; self.lastChargeAt = lastChargeAt
        self.chargingSpans = chargingSpans; self.sleepSpan = sleepSpan
    }
}

/// How the current level compares with the same time of day on other days.
public struct EnergyComparison: Sendable, Equatable {
    public var current: Double
    /// The median level at this time of day across the compared days.
    public var typical: Double
    /// Signed percentage difference against that median.
    public var percent: Double
    public var time: Date
    public var days: Int
}

public enum EnergySummaryEngine {
    /// Minimum past days before a "higher than usual" claim is made at all.
    public static let comparisonMinimumDays = 5

    /// Compares the level now with the level at the same clock time on previous
    /// days. Without this the screen can say what the number is but not whether
    /// it is unusual, which is the part a person actually asks about.
    public static func compare(detail: [EnergyPoint], history: [[EnergyPoint]], now: Date, calendar: Calendar = .current) -> EnergyComparison? {
        guard let current = detail.filter({ $0.date <= now }).max(by: { $0.date < $1.date }) else { return nil }
        let minutes = calendar.component(.hour, from: current.date) * 60 + calendar.component(.minute, from: current.date)

        // The value closest to the same clock time on each past day, within
        // half an hour; a day that was not being recorded then is skipped.
        let past = history.compactMap { day -> Double? in
            let candidates = day.compactMap { point -> (Double, Double)? in
                let stamp = calendar.component(.hour, from: point.date) * 60 + calendar.component(.minute, from: point.date)
                let distance = abs(Double(stamp - minutes))
                return distance <= 30 ? (distance, point.value) : nil
            }
            return candidates.min { $0.0 < $1.0 }?.1
        }
        guard past.count >= comparisonMinimumDays, let typical = Statistics.median(past), typical > 1 else { return nil }
        return .init(current: current.value, typical: typical,
                     percent: (current.value - typical) / typical * 100,
                     time: current.date, days: past.count)
    }

    /// Totals are taken from the level actually reached between consecutive
    /// points, not from the modelled restoration and drain terms. Those two
    /// differ whenever the level clamps at 0 or 100, and the figure on screen
    /// should be the one the chart shows.
    public static func summarise(_ detail: [EnergyPoint]) -> EnergySummary {
        let points = detail.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard points.count > 1 else { return .init() }

        var charged = 0.0, spent = 0.0
        var spans: [ClosedRange<Date>] = []
        var runStart: Date?
        var lastPeak: Double?
        var lastPeakAt: Date?

        for (previous, current) in zip(points, points.dropFirst()) {
            let delta = current.value - previous.value
            if delta > 0 {
                charged += delta
                if runStart == nil { runStart = previous.date }
            } else {
                spent += -delta
                if let from = runStart {
                    // A run ends at the point before the fall: that peak is the
                    // level the charge reached.
                    if previous.date > from { spans.append(from...previous.date) }
                    lastPeak = previous.value
                    lastPeakAt = previous.date
                    runStart = nil
                }
            }
        }
        // A run still open at the end of the day is the current charge.
        if let from = runStart, let last = points.last, last.date > from {
            spans.append(from...last.date)
            lastPeak = last.value
            lastPeakAt = last.date
        }

        let asleep = points.filter(\.asleep)
        let sleepSpan: ClosedRange<Date>? = {
            guard let first = asleep.first?.date, let last = asleep.last?.date, last > first else { return nil }
            return first...last
        }()

        return .init(charged: charged, spent: spent,
                     lastChargePeak: lastPeak, lastChargeAt: lastPeakAt,
                     chargingSpans: spans, sleepSpan: sleepSpan)
    }
}
