import SwiftUI
import Charts
import PulseCore

/// A short horizontal strip of segments spanning the card. The lit segments all
/// take the colour of the *current level*, the way a real battery indicator
/// does: a two-thirds-full battery is green, not green fading into orange.
/// Colouring each segment by its own position made 66% end in orange and read
/// as a warning.
struct BatteryStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double?
    var segments = 28
    var height: CGFloat = 16
    /// Faint tick showing the level on waking.
    var morning: Double? = nil

    private var fraction: Double { min(1, max(0, (value ?? 0) / 100)) }

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2.5
            let width = max(1, (proxy.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments))
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { index in
                        let position = (Double(index) + 0.5) / Double(segments)
                        let lit = value != nil && position <= fraction
                        RoundedRectangle(cornerRadius: width / 2.2, style: .continuous)
                            .fill(lit ? AppColors.battery(fraction) : AppColors.border)
                            .frame(width: width)
                    }
                }
                if let morning, morning.isFinite, value != nil {
                    Capsule().fill(AppColors.ink.opacity(0.35))
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: proxy.size.width * min(1, max(0, morning / 100)))
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("bodyBattery"))
        .accessibilityValue(value.map { number($0) + "%" } ?? L("noData"))
    }
}

/// The compact home-screen battery: the same height as the stress and health
/// cards, with the strip doing the work. The curve and the breakdown live in
/// the detail view, which is where there is room for them.
struct BodyBatteryCompactCard: View {
    let snapshot: DailySnapshot
    private var detail: [EnergyPoint] { (snapshot.energyDetail ?? []).sorted { $0.date < $1.date } }
    private var value: Double? { snapshot.score(.energy).value }
    private var morning: Double? {
        detail.last(where: \.asleep).flatMap { last in detail.first { $0.date > last.date }?.value }
    }
    var body: some View {
        Card {
            HStack {
                Label {
                    Text(L("bodyBattery")).font(AppTypography.cardTitle)
                } icon: {
                    Image(systemName: "bolt.heart.fill").foregroundStyle(AppColors.metric(.energy))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value {
                    Text(number(value)).font(.system(size: 34, weight: .bold))
                        .monospacedDigit().contentTransition(.numericText())
                    Text("%").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    ConfidenceBadge(percent: snapshot.score(.energy).confidencePercent, compact: true)
                } else {
                    // A dash followed by a percent sign reads as a broken value.
                    Text(L("calibrating")).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            BatteryStrip(value: value, morning: morning)
            if value != nil, !detail.isEmpty {
                Text(L("batteryRechargedSpent")
                        .replacingOccurrences(of: "{0}", with: number(detail.reduce(0) { $0 + $1.restoration }))
                        .replacingOccurrences(of: "{1}", with: number(detail.reduce(0) { $0 + $1.stressDrain + $1.loadDrain + $1.baselineDrain })))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L("batteryWaiting")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The expanded battery, split into a scene header and plain surfaces for the
/// chart and the method. Drawing a chart straight onto a photograph made both
/// unreadable: the scene now stops where the data begins.
struct BodyBatteryCard: View {
    let snapshot: DailySnapshot
    var expanded = false
    @State private var selectedTime: Date?

    private var detail: [EnergyPoint] { (snapshot.energyDetail ?? []).filter { $0.value.isFinite }.sorted { $0.date < $1.date } }
    private var points: [TimelinePoint] {
        detail.isEmpty ? snapshot.energy.filter { $0.value.isFinite }.sorted { $0.date < $1.date } : detail.map(\.timeline)
    }
    private var selected: TimelinePoint? {
        guard let selectedTime else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedTime)) < abs($1.date.timeIntervalSince(selectedTime)) }
    }
    private var morning: Double? {
        detail.last(where: \.asleep).flatMap { last in detail.first { $0.date > last.date }?.value } ?? detail.first?.value
    }
    private var breakdown: (sleep: Double, rest: Double, stress: Double, load: Double, waking: Double) {
        detail.reduce((0.0, 0.0, 0.0, 0.0, 0.0)) { total, point in
            (total.0 + (point.asleep ? point.restoration : 0),
             total.1 + (point.asleep ? 0 : point.restoration),
             total.2 + point.stressDrain,
             total.3 + point.loadDrain,
             total.4 + point.baselineDrain)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            hero
            if points.count > 1 {
                Card {
                    HStack {
                        Text(L("todayCurve")).font(AppTypography.cardTitle)
                        Spacer()
                        Text(selected.map { $0.date.formatted(date: .omitted, time: .shortened) } ?? "")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    EnergyCurve(detail: detail, points: points, height: 190, selection: $selectedTime)
                    EnergyLegend(hasPredicted: points.contains(where: \.predicted))
                }
                Card {
                    Text(L("batteryBalance")).font(AppTypography.cardTitle)
                    balanceRows
                }
            }
            if expanded {
                Card {
                    Label(L("aboutMetric"), systemImage: "info.circle").font(.subheadline.weight(.medium))
                    Text(L("batteryMethod")).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("algorithmVersion") + " \(snapshot.score(.energy).algorithmVersion)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var hero: some View {
        Card(scene: .energy, accent: AppColors.metric(.energy)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(L("bodyBattery"), systemImage: "bolt.heart.fill").font(.caption.weight(.semibold))
                    Text(selected.map { $0.date.formatted(date: .omitted, time: .shortened) } ?? L("batteryWaiting"))
                        .font(.caption2).opacity(0.78)
                }
                Spacer(minLength: 10)
                ConfidenceBadge(percent: snapshot.score(.energy).confidencePercent, compact: true, onScene: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(number(selected?.value)).font(.system(size: 54, weight: .semibold))
                    .monospacedDigit().contentTransition(.numericText())
                Text("%").font(.title3.weight(.medium)).opacity(0.75)
                Spacer()
            }
            BatteryStrip(value: selected?.value, segments: 24, height: 14, morning: morning)
            if points.count <= 1 {
                Text(L("batteryEmptyDetail")).font(.caption).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Named sources rather than one gross gain and one gross drain: knowing it
    /// was stress and not exercise is the point of the breakdown.
    private var balanceRows: some View {
        let parts = breakdown
        return VStack(spacing: 9) {
            if parts.sleep > 0.5 { row("batterySleep", parts.sleep, positive: true, symbol: "moon.zzz.fill") }
            if parts.rest > 0.5 { row("batteryRest", parts.rest, positive: true, symbol: "leaf.fill") }
            if parts.stress > 0.5 { row("batteryStress", parts.stress, positive: false, symbol: "waveform.path.ecg") }
            if parts.load > 0.5 { row("batteryExercise", parts.load, positive: false, symbol: "figure.run") }
            if parts.waking > 0.5 { row("batteryWaking", parts.waking, positive: false, symbol: "sun.max.fill") }
        }
    }
    private func row(_ title: String, _ value: Double, positive: Bool, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.caption)
                .foregroundStyle(positive ? AppColors.accent : AppColors.warn)
                .frame(width: 20)
            Text(L(title)).font(.subheadline)
            Spacer(minLength: 4)
            Text((positive ? "+" : "−") + number(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// Says what the colours on the curve mean. Without this the tinted points are
/// decoration rather than information.
private struct EnergyLegend: View {
    let hasPredicted: Bool
    var body: some View {
        HStack(spacing: 14) {
            item("legendAsleep", AppColors.metric(.sleep))
            item("legendExercise", AppColors.metric(.strain))
            item("legendStress", AppColors.warn)
            if hasPredicted {
                HStack(spacing: 5) {
                    Image(systemName: "circle.dotted").font(.caption2).foregroundStyle(.secondary)
                    Text(L("estimate"))
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
    private func item(_ key: String, _ colour: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(L(key))
        }
    }
}

/// The day's curve. Intervals are tinted by what dominated them — asleep,
/// exercising, or under stress — so the shape explains itself.
private struct EnergyCurve: View {
    let detail: [EnergyPoint]
    let points: [TimelinePoint]
    var height: CGFloat
    @Binding var selection: Date?

    private func tint(_ point: EnergyPoint) -> Color {
        if point.asleep { return AppColors.metric(.sleep) }
        if point.exercise || point.loadDrain > 0.2 { return AppColors.metric(.strain) }
        if point.stressDrain > 0.4 { return AppColors.warn }
        return AppColors.metric(.energy)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value(L("time"), point.date), y: .value(L("energy"), point.value))
                    .foregroundStyle(LinearGradient(colors: [AppColors.metric(.energy).opacity(0.35), AppColors.metric(.energy).opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(detail) { point in
                PointMark(x: .value(L("time"), point.date), y: .value(L("energy"), point.value))
                    .foregroundStyle(tint(point))
                    .symbolSize(point.asleep || point.exercise ? 16 : 8)
                    .opacity(point.predicted ? 0.45 : 1)
            }
            ForEach(points) { point in
                LineMark(x: .value(L("time"), point.date), y: .value(L("energy"), point.value))
                    .foregroundStyle(AppColors.metric(.energy))
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let selection, let nearest = points.min(by: { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }) {
                RuleMark(x: .value(L("time"), nearest.date))
                    .foregroundStyle(AppColors.ink.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.ink.opacity(0.15))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()).font(.caption2) } }
        .chartXSelection(value: $selection)
        .frame(height: height)
    }
}

/// "Stress today": the numbers on the left, the arc on the right sitting in its
/// own raised well so it reads as an instrument rather than a flat drawing.
struct StressTodayCard: View {
    let snapshot: DailySnapshot
    private var values: [Double] { snapshot.stress.map(\.value).filter(\.isFinite) }
    var body: some View {
        Card(accent: AppColors.metric(.stress)) {
            HStack {
                Label {
                    Text(L("stressToday")).font(AppTypography.cardTitle)
                } icon: {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(AppColors.metric(.stress))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(snapshot.stress.last.map { L("updatedAt") + " " + $0.date.formatted(date: .omitted, time: .shortened) } ?? L("calibrating"))
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 0) {
                        statistic("min", values.min())
                        statistic("average", Statistics.mean(values))
                        statistic("max", values.max())
                    }
                }
                Spacer(minLength: 0)
                MetricGauge(value: snapshot.score(.stress).value, size: 112,
                            caption: snapshot.score(.stress).value.map(MetricNarrator.band))
            }
        }
    }
    /// Equal columns so min, average and max line up instead of drifting with
    /// the width of their numbers.
    private func statistic(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(title)).font(.caption2).foregroundStyle(.secondary)
            Text(number(value)).font(.title3.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
