import SwiftUI
import Charts
import PulseCore

/// The night, laid out the way Apple Health lays it out: one row per stage in
/// the order Awake / REM / Core / Deep, rounded bars sized to the real periods,
/// an hour axis that actually reads, and a legend giving each stage's duration
/// and share of the night. The previous chart put six rows in alphabetical-ish
/// order with an unlabelled axis and no durations, which made it unreadable.
struct SleepStageTimeline: View {
    let segments: [SleepSegment]
    @State private var selection: Date?

    /// Top to bottom, lightest sleep first — Apple's ordering.
    private let rows: [SleepStage] = [.awake, .rem, .core, .deep]

    private var visible: [SleepSegment] {
        segments.filter { $0.end > $0.start && $0.stage != .inBed }.sorted { $0.start < $1.start }
    }
    private var start: Date { visible.map(\.start).min() ?? Date() }
    private var end: Date { visible.map(\.end).max() ?? start.addingTimeInterval(3600) }
    private var asleepMinutes: Double { visible.filter { $0.stage.asleep }.reduce(0) { $0 + $1.minutes } }
    private var selected: SleepSegment? {
        guard let selection else { return nil }
        return visible.first { $0.start <= selection && $0.end >= selection }
    }
    private func minutes(_ stage: SleepStage) -> Double {
        visible.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }
    /// One tick per hour while the night is short, every two hours otherwise,
    /// so the labels never collide.
    private var hourStride: Int {
        let hours = end.timeIntervalSince(start) / 3600
        return hours > 9 ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(duration(asleepMinutes)).fontWeight(.semibold).monospacedDigit()
                Spacer()
                Text(end.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()

            Chart {
                ForEach(visible) { segment in
                    RectangleMark(
                        xStart: .value("start", segment.start),
                        xEnd: .value("end", segment.end),
                        y: .value("stage", label(segment.stage)),
                        height: .fixed(22)
                    )
                    .foregroundStyle(color(segment.stage))
                    .clipShape(.rect(cornerRadius: 4))
                }
                if let selection {
                    RuleMark(x: .value("time", selection))
                        .foregroundStyle(AppColors.ink.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: rows.map(label))
            .chartYAxis {
                AxisMarks(position: .leading, values: rows.map(label)) { value in
                    AxisValueLabel {
                        if let raw = value.as(String.self) {
                            Text(L(raw)).font(.caption2.weight(.medium))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.border)
                    AxisValueLabel(format: .dateTime.hour()).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selection)
            .frame(height: 168)

            if let selected {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(color(selected.stage)).frame(width: 9, height: 9)
                    Text(L(label(selected.stage))).font(.caption.weight(.medium))
                    Spacer()
                    Text(selected.start.formatted(date: .omitted, time: .shortened) + " – " + selected.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text(duration(selected.minutes)).font(.caption.weight(.semibold)).monospacedDigit()
                }
            }

            // Legend with duration and share, which is the part that was missing.
            VStack(spacing: 7) {
                ForEach(rows, id: \.rawValue) { stage in
                    let value = minutes(stage)
                    if value > 0 {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2).fill(color(stage)).frame(width: 9, height: 9)
                            Text(L(label(stage))).font(.caption)
                            Spacer(minLength: 6)
                            if stage.asleep, asleepMinutes > 0 {
                                Text(number(value / asleepMinutes * 100) + "%")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            } else {
                                Text("").frame(width: 42)
                            }
                            Text(duration(value)).font(.caption.weight(.semibold)).monospacedDigit()
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("sleepStages"))
    }

    private func label(_ stage: SleepStage) -> String {
        switch stage { case .inBed: "inBed"; case .unspecified: "core"; case .awake: "awake"; case .core: "core"; case .deep: "deep"; case .rem: "rem" }
    }
    /// Apple Health's stage palette, adapted so it holds contrast on pure white
    /// and pure black.
    private func color(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: .adaptive(light: 0xE08A2B, dark: 0xFFB454)
        case .rem: .adaptive(light: 0x2E9FD4, dark: 0x5FC8F5)
        case .core: .adaptive(light: 0x2F5BD0, dark: 0x6E93FF)
        case .deep: .adaptive(light: 0x3B2FA8, dark: 0x8B7BFF)
        case .inBed, .unspecified: .adaptive(light: 0x8A9491, dark: 0x6B7572)
        }
    }
}

/// A metric's own screen: illustrated header, the plain-language read of the
/// day, the history, the components, and the honest limits. This is what
/// replaced the conversational coach.
struct MetricDetailView: View {
    @Environment(AppModel.self) private var model
    var metric: Metric
    @State private var range = 30

    private var snapshot: DailySnapshot { model.today }
    private var score: ScoreResult { snapshot.score(metric) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if metric == .energy {
                    BodyBatteryCard(snapshot: snapshot, expanded: true)
                } else {
                    MetricHeroCard(metric: metric, score: score, snapshot: snapshot, date: model.selectedDate)
                }

                NarrativeCard(metric: metric, snapshot: snapshot, history: model.history)

                Card {
                    HStack {
                        Text(L("trends")).font(AppTypography.cardTitle)
                        Spacer()
                    }
                    Picker(L("range"), selection: $range) {
                        ForEach([7, 30, 90, 180, 365], id: \.self) { days in
                            Text(days == 365 ? "1Y" : days == 180 ? "6M" : days == 90 ? "3M" : "\(days)D").tag(days)
                        }
                    }.pickerStyle(.segmented)
                    HealthTrendChart(points: historyPoints, metric: metric, height: 185,
                                     maximumGap: 26 * 3600, showsAverage: range >= 30)
                }

                if metric == .sleep { sleepDetails }
                if metric == .strain { strainDetails }
                if metric == .stress { stressDetails }

                if !score.contributors.isEmpty { ContributorsCard(metric: metric, score: score) }
                LimitationsCard(score: score)
            }
            .padding(18)
        }
        .pulsePage()
        .navigationTitle(L(metric.rawValue))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyPoints: [TimelinePoint] {
        Array(model.history.filter { $0.date <= model.selectedDate }.sorted { $0.date < $1.date }.suffix(range))
            .compactMap { day in day.score(metric).value.map { TimelinePoint(date: day.date, value: $0) } }
    }

    private var strainDetails: some View {
        Card {
            Text(L("dailyLoad")).font(AppTypography.cardTitle)
            ValueRow(title: "targetStrain", value: number(snapshot.targetStrain))
            ValueRow(title: "rawLoad", value: number(snapshot.rawLoad, digits: 1))
            ValueRow(title: "activeEnergy", value: number(snapshot.vital("activeEnergy")?.value) + " kcal")
            ForEach(snapshot.workouts) { workout in
                ValueRow(title: workout.activity, value: duration(workout.minutes), symbol: "figure.run")
            }
        }
    }

    private var stressDetails: some View {
        Card {
            Text(L("timeline")).font(AppTypography.cardTitle)
            MetricTimeline(points: snapshot.stress, metric: .stress, height: 200)
            if snapshot.stress.isEmpty {
                Label(L("stressCalibrating"), systemImage: "clock.badge.checkmark").font(.subheadline.weight(.medium))
                Text(L("stressCalibrationDetail")).font(.footnote).foregroundStyle(.secondary)
            }
            Text(L("stressExplanation")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var sleepDetails: some View {
        VStack(spacing: 18) {
            Card {
                Text(L("sleepBalance")).font(AppTypography.cardTitle)
                ValueRow(title: "sleepNeed", value: duration(snapshot.sleepNeed))
                ValueRow(title: "sleepDebt", value: duration(snapshot.sleepDebt))
                ValueRow(title: "sleepDuration", value: duration(snapshot.sleepSessions.reduce(0) { $0 + $1.asleepMinutes }))
            }
            ForEach(snapshot.sleepSessions) { session in
                Card {
                    Text(L(session.id == snapshot.sleepSessions.max(by: { $0.asleepMinutes < $1.asleepMinutes })?.id ? "mainSleep" : "nap"))
                        .font(AppTypography.cardTitle)
                    Text(session.start.formatted(date: .omitted, time: .shortened) + " – " + session.end.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                    SleepStageTimeline(segments: session.segments)
                    ValueRow(title: "latency", value: SleepEngine.latency(session).map(duration) ?? L("unavailable"))
                }
            }
        }
    }
}

/// Illustrated header. Every metric gets the same structure and its own scene,
/// so sleep is no longer the only screen with a picture behind it.
private struct MetricHeroCard: View {
    let metric: Metric
    let score: ScoreResult
    let snapshot: DailySnapshot
    let date: Date

    private var baseline: Double? { nil }

    var body: some View {
        Card(scene: MetricScene(metric), accent: AppColors.metric(metric)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(L("todayReading"), systemImage: symbol).font(.caption.weight(.semibold))
                    Text(L(metric.rawValue)).font(.system(.title, weight: .bold))
                    Text(date.formatted(date: .complete, time: .omitted)).font(.caption).opacity(0.75)
                }
                Spacer(minLength: 8)
                if metric == .stress {
                    MetricGauge(value: score.value, size: 112, caption: score.value.map(MetricNarrator.band))
                } else {
                    ScoreRing(metric: metric, value: score.value, size: 104, onScene: true)
                }
            }
            if metric == .sleep, let main = snapshot.sleepSessions.max(by: { $0.asleepMinutes < $1.asleepMinutes }) {
                HStack(spacing: 10) {
                    pill("time.zzz", duration(main.asleepMinutes))
                    pill("bed.double", duration(snapshot.sleepNeed))
                    Spacer()
                }
            }
            if score.value == nil {
                Text(L("calibrationDetail")).font(.footnote).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var symbol: String {
        switch metric {
        case .recovery: "arrow.clockwise.heart"
        case .sleep: "moon.stars.fill"
        case .strain: "flame.fill"
        case .stress: "waveform.path.ecg"
        case .energy: "bolt.heart.fill"
        }
    }
    private func pill(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Replaces the removed chat: a short, deterministic read of the day built from
/// what was actually measured, with no network and no generated prose.
struct NarrativeCard: View {
    let metric: Metric
    let snapshot: DailySnapshot
    let history: [DailySnapshot]
    var body: some View {
        let narrative = MetricNarrator.describe(metric, snapshot: snapshot, history: history)
        Card {
            HStack {
                Label(L("whatThisMeans"), systemImage: "text.alignleft").font(AppTypography.cardTitle)
                Spacer()
            }
            Text(localized(narrative.headline)).font(.headline).fixedSize(horizontal: false, vertical: true)
            ForEach(narrative.detail) { line in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(AppColors.metric(metric)).frame(width: 5, height: 5).padding(.top, 7)
                    Text(localized(line)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Applies the narrator's arguments to the localised format string. Contributor
/// names are themselves keys, so they get localised before substitution.
func localized(_ line: NarrativeLine) -> String {
    let format = L(line.key)
    return line.arguments.enumerated().reduce(format) { text, pair in
        let value = pair.element.rangeOfCharacter(from: .decimalDigits) == nil ? L(pair.element) : pair.element
        return text.replacingOccurrences(of: "{\(pair.offset)}", with: value)
    }
}

private struct ContributorsCard: View {
    let metric: Metric
    let score: ScoreResult
    var body: some View {
        Card {
            Text(L("contributors")).font(AppTypography.cardTitle)
            ForEach(score.contributors) { contributor in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(L(contributor.id)).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(contributor.value.map { number($0, digits: 1) + " " + contributor.unit } ?? L("unavailable"))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    if let value = contributor.score {
                        ProgressView(value: min(100, max(0, value)), total: 100).tint(AppColors.metric(metric))
                    } else {
                        // An absent component is shown as absent, never as zero.
                        Capsule().fill(AppColors.border).frame(height: 4)
                    }
                    HStack {
                        if let baseline = contributor.baseline {
                            Text(L("baseline") + ": " + number(baseline, digits: 1) + " " + contributor.unit)
                        }
                        Spacer()
                        Text(L("weight") + " " + number(contributor.weight) + "%")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct LimitationsCard: View {
    let score: ScoreResult
    var body: some View {
        Card {
            HStack {
                Label(L("aboutMetric"), systemImage: "info.circle").font(.subheadline.weight(.medium))
                Spacer()
            }
            if let report = score.report, !report.limitations.isEmpty {
                ForEach(report.limitations, id: \.self) { limitation in
                    Label(L(limitation), systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text(L("metricExplanation")).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L("algorithmVersion") + " \(score.algorithmVersion)").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
