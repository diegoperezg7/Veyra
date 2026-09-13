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

public enum EnergySummaryEngine {
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
