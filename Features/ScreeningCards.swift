import SwiftUI
import Charts
import PulseCore
#if canImport(HealthKit)
import HealthKit
#endif

/// One reading the watch records and Veyra can interpret against a published
/// reference. Kept deliberately flat: a title, the number, and what the number
/// means, because that is all any of these deserve on a summary card.
struct ScreeningSignal: Identifiable {
    var id: String
    var symbol: String
    var value: String
    /// Localisation key of the band, never display text.
    var band: String
    var severity: Int
    var detail: String?

    var tint: Color {
        switch severity {
        case 0: AppColors.accent
        case 1: AppColors.warn
        default: AppColors.danger
        }
    }
}

/// Builds the signals from whatever the history actually contains. Anything
/// without enough data is simply absent rather than shown as a blank, because
/// an empty row reads as a broken feature.
enum ScreeningSignals {
    /// Apple's own thresholds, read from HealthKit where the platform publishes
    /// them. On a platform without HealthKit the signals that depend on them
    /// are skipped rather than guessed.
    static var breathingThreshold: Double? {
        #if canImport(HealthKit)
        HealthCatalog.breathingDisturbanceThreshold
        #else
        nil
        #endif
    }
    static var steadinessThresholds: (low: Double, veryLow: Double)? {
        #if canImport(HealthKit)
        HealthCatalog.walkingSteadinessThresholds
        #else
        nil
        #endif
    }

    static func build(history: [DailySnapshot], birthDate: Date?, sex: String?, now: Date = Date()) -> [ScreeningSignal] {
        var signals: [ScreeningSignal] = []
        let vitals = history.flatMap(\.vitals)
        func series(_ key: String) -> [Vital] { vitals.filter { $0.id == key }.sorted { $0.date < $1.date } }

        // Wrist temperature, as a deviation from the wearer's own nights.
        let temperature = series("temperature")
        if let result = TemperatureDeviationEngine.calculate(nightly: temperature.map(\.value)) {
            let sign = result.deviation >= 0 ? "+" : "−"
            signals.append(.init(id: "wristTemperature", symbol: "thermometer.medium",
                                 value: sign + number(abs(result.deviation), digits: 2) + " °C",
                                 band: result.band, severity: result.unusual ? 1 : 0,
                                 detail: L("baseline") + " " + number(result.baseline, digits: 1) + " °C"))
        }

        // Sleeping breathing disturbances — Apple's apnoea screening.
        let breathing = series("breathingDisturbances")
        if let threshold = breathingThreshold, let latest = breathing.last,
           let band = BreathingDisturbanceEngine.classify(latest.value, elevatedFrom: threshold) {
            let month = BreathingDisturbanceEngine.monthly(nightly: breathing.suffix(30).map(\.value), elevatedFrom: threshold)
            signals.append(.init(id: "breathingDisturbances", symbol: "lungs",
                                 value: L(band), band: band,
                                 severity: (month?.persistent ?? false) ? 1 : 0,
                                 detail: month.map { "\($0.elevatedNights)/\($0.nights) " + L("nightsElevated") }))
        }

        // Chronotype, from the mid-sleep point.
        let sessions = history.flatMap(\.sleepSessions)
        if let chronotype = ChronotypeEngine.calculate(sessions: Array(sessions.suffix(28))) {
            signals.append(.init(id: "chronotype", symbol: "moon.stars",
                                 value: clockTime(chronotype.midSleep), band: chronotype.band, severity: 0,
                                 detail: L("midSleepPoint")))
        }

        // Atrial fibrillation burden, and the notifications that precede it.
        let afib = series("afibBurden")
        if let burden = AtrialFibrillationEngine.weekly(afib.suffix(7).map(\.value)), let band = AtrialFibrillationEngine.band(burden) {
            signals.append(.init(id: "afibBurden", symbol: "waveform.path.ecg",
                                 value: number(burden, digits: 1) + " %", band: band.key,
                                 severity: band.severity, detail: L("afibWeeklyAverage")))
        }
        let irregular = series("irregularRhythm").filter { now.timeIntervalSince($0.date) < 90 * 86400 }
        if !irregular.isEmpty {
            signals.append(.init(id: "irregularRhythm", symbol: "heart.text.square",
                                 value: "\(irregular.count)", band: "irregularRhythmDetected", severity: 1,
                                 detail: irregular.last.map { L("lastOne") + " " + $0.date.formatted(date: .abbreviated, time: .omitted) }))
        }

        // Walking steadiness.
        let steadiness = series("steadiness")
        if let thresholds = steadinessThresholds, let latest = steadiness.last,
           let band = WalkingSteadinessEngine.classify(latest.value, lowFrom: thresholds.low, veryLowFrom: thresholds.veryLow) {
            signals.append(.init(id: "walkingSteadiness", symbol: "figure.walk.motion",
                                 value: number(latest.value, digits: 0) + " %", band: band,
                                 severity: band == "steadinessOK" ? 0 : band == "steadinessLow" ? 1 : 2,
                                 detail: nil))
        }

        // Blood pressure, averaged over separate readings as both guidelines require.
        let systolic = series("systolic").suffix(7).map(\.value)
        let diastolic = series("diastolic").suffix(7).map(\.value)
        if let reading = BloodPressureEngine.average(systolic: systolic, diastolic: diastolic) {
            signals.append(.init(id: "bloodPressure", symbol: "heart.circle",
                                 value: number(reading.systolic, digits: 0) + "/" + number(reading.diastolic, digits: 0),
                                 band: reading.band,
                                 severity: reading.severity == 0 ? 0 : reading.severity <= 2 ? 1 : 2,
                                 detail: L(reading.europeanBand) + " · ESC/ESH"))
        }
        return signals
    }

    /// Minutes after midnight as a wall-clock time.
    static func clockTime(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The screening card on the Biology tab. Absent when there is nothing to say.
struct ScreeningCard: View {
    var signals: [ScreeningSignal]
    var body: some View {
        Card {
            Label(L("screening"), systemImage: "stethoscope").font(AppTypography.cardTitle)
            Text(L("screeningDetail")).font(.caption).foregroundStyle(.secondary).padding(.bottom, 2)
            ForEach(signals) { signal in
                ScreeningRow(signal: signal)
                if signal.id != signals.last?.id { Divider().overlay(AppColors.divider) }
            }
        }
    }
}

struct ScreeningRow: View {
    var signal: ScreeningSignal
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: signal.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(signal.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(signal.id)).font(.subheadline.weight(.medium))
                Text(L(signal.band)).font(.caption).foregroundStyle(signal.severity == 0 ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(signal.tint))
                if let detail = signal.detail {
                    Text(detail).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(signal.value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 5)
    }
}

/// VO2max against the population, and the week's activity against the WHO
/// guideline. Both belong on Fitness: they answer "how am I doing", not
/// "what happened today".
struct FitnessStandardsCard: View {
    var vo2: Double?
    var percentile: Double?
    var activity: WeeklyActivityEngine.Result
    var body: some View {
        Card {
            Label(L("standards"), systemImage: "chart.bar.doc.horizontal").font(AppTypography.cardTitle)
            if let vo2, let percentile {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("vo2max")).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(number(vo2, digits: 1)).font(.title3.weight(.semibold)).monospacedDigit()
                        Text("ml/kg/min").font(.caption2).foregroundStyle(.tertiary)
                    }
                    PercentileBar(percentile: percentile)
                    Text(L(VO2MaxNorms.band(percentile: percentile)) + " · " + L("percentileOf").replacingOccurrences(of: "%@", with: number(percentile, digits: 0)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider().overlay(AppColors.divider).padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("weeklyActivity")).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(number(activity.equivalentMinutes, digits: 0)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(L("minutesShort")).font(.caption2).foregroundStyle(.tertiary)
                }
                GuidelineBar(value: activity.equivalentMinutes, target: WeeklyActivityEngine.moderateTarget, upper: WeeklyActivityEngine.upperTarget)
                Text(L(activity.band)).font(.caption).foregroundStyle(activity.meetsGuideline ? AnyShapeStyle(AppColors.accent) : AnyShapeStyle(Color.secondary))
                Text(L("whoGuideline")).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Where the measurement sits in the population, drawn as a position on a
/// scale rather than a bar that fills — a percentile is a place, not an amount.
private struct PercentileBar: View {
    var percentile: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.surfaceRaised)
                Capsule().fill(AppColors.accentSoft)
                    .frame(width: proxy.size.width * 0.4)
                    .offset(x: proxy.size.width * 0.3)
                Capsule().fill(AppColors.accentVivid)
                    .frame(width: 4, height: 18)
                    .offset(x: max(0, min(proxy.size.width - 4, proxy.size.width * percentile / 100 - 2)), y: -3)
            }
        }
        .frame(height: 12)
    }
}

/// Progress towards the WHO minimum, with the upper end of the recommended
/// range marked so exceeding it does not read as simply "more is better".
private struct GuidelineBar: View {
    var value: Double
    var target: Double
    var upper: Double
    var body: some View {
        GeometryReader { proxy in
            let scale = max(upper, value) * 1.05
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.surfaceRaised)
                Capsule().fill(AppColors.accentVivid)
                    .frame(width: proxy.size.width * min(1, value / scale))
                Rectangle().fill(AppColors.ink.opacity(0.35))
                    .frame(width: 2)
                    .offset(x: proxy.size.width * (target / scale))
            }
        }
        .frame(height: 12)
    }
}
