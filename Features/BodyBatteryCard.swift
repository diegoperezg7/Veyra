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


/// A battery cell: thick bezel, terminal, gradient fill, hatched remainder and
/// the level inside it. Modelled on how a charge indicator is normally drawn,
/// because that is the vocabulary the number belongs to.
struct BatteryGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double?
    var height: CGFloat = 118

    @State private var filled: Double = 0
    private var fraction: Double { min(1, max(0, (value ?? 0) / 100)) }
    private var tint: Color { AppColors.battery(fraction) }

    var body: some View {
        HStack(spacing: height * 0.045) {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let radius = h * 0.26
                let bezel = h * 0.075
                let innerRadius = radius - bezel * 0.8
                let innerWidth = w - bezel * 2
                // Enough charge to hold the figure comfortably inside it.
                let fillCentred = filled >= 0.42
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(AppColors.surfaceRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(AppColors.border, lineWidth: bezel * 0.8)
                        )
                    // Remainder: hatched, so "empty" is visibly part of the cell.
                    DiagonalHatch(spacing: h * 0.11)
                        .stroke(AppColors.border, lineWidth: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                        .padding(bezel)
                        .opacity(0.9)
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.22), tint],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: max(0, innerWidth * filled))
                        .padding(bezel)
                    // Centred inside the charged portion rather than inside the
                    // cell: centred in the cell, the "%" spilled past the fill
                    // edge and went white on the near-white hatching.
                    label(height: h, onFill: fillCentred)
                        .frame(width: fillCentred ? innerWidth * filled : w, height: h)
                        .padding(.leading, fillCentred ? bezel : 0)
                }
            }
            .frame(height: height)
            RoundedRectangle(cornerRadius: height * 0.06, style: .continuous)
                .fill(AppColors.border)
                .frame(width: height * 0.06, height: height * 0.28)
        }
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("bodyBattery"))
        .accessibilityValue(value.map { number($0) + "%" } ?? L("noData"))
    }

    /// White once the fill has passed the middle, ink before that, so the
    /// figure always has contrast behind it.
    private func label(height h: CGFloat, onFill: Bool) -> some View {
        VStack(spacing: -h * 0.04) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(number(value))
                    .font(.system(size: h * 0.40, weight: .bold))
                    .monospacedDigit().contentTransition(.numericText())
                Text("%").font(.system(size: h * 0.18, weight: .semibold)).opacity(0.85)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            Image(systemName: "bolt.fill")
                .font(.system(size: h * 0.12, weight: .bold))
                .opacity(0.9)
        }
        .foregroundStyle(onFill ? Color.white : AppColors.ink)
    }

    private func animate() {
        guard value != nil else { filled = 0; return }
        guard !reduceMotion else { filled = fraction; return }
        withAnimation(.smooth(duration: 0.75)) { filled = fraction }
    }
}

/// The two totals under the cell: everything gained, everything lost.
struct EnergyTotals: View {
    let summary: EnergySummary
    var body: some View {
        HStack(spacing: 12) {
            total(summary.charged, positive: true, title: "batteryTotalCharged")
            total(summary.spent, positive: false, title: "batteryTotalSpent")
        }
    }
    private func total(_ value: Double, positive: Bool, title: String) -> some View {
        VStack(spacing: 4) {
            Text((positive ? "+" : "−") + number(value) + "%")
                .font(.title2.weight(.bold)).monospacedDigit()
                .foregroundStyle(positive ? AppColors.ageBetter : AppColors.danger)
            Text(L(title)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColors.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
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

/// The energy screen: the cell and its account at the top, then the day's level
/// with the activation that drove it underneath, sharing one time axis.
struct BodyBatteryCard: View {
    let snapshot: DailySnapshot
    var expanded = false
    @State private var selectedTime: Date?

    private var detail: [EnergyPoint] { (snapshot.energyDetail ?? []).filter { $0.value.isFinite }.sorted { $0.date < $1.date } }
    private var points: [TimelinePoint] {
        detail.isEmpty ? snapshot.energy.filter { $0.value.isFinite }.sorted { $0.date < $1.date } : detail.map(\.timeline)
    }
    private var summary: EnergySummary { EnergySummaryEngine.summarise(detail) }
    private var selected: TimelinePoint? {
        guard let selectedTime else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedTime)) < abs($1.date.timeIntervalSince(selectedTime)) }
    }
    /// One window for both charts, so the two line up hour for hour.
    private var window: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date, last > first else { return nil }
        return first...last
    }

    var body: some View {
        VStack(spacing: 18) {
            Card {
                BatteryGauge(value: selected?.value, height: 118).padding(.horizontal, 4)
                if let peak = summary.lastChargePeak, let at = summary.lastChargeAt {
                    Text(L("batteryLastCharge")
                            .replacingOccurrences(of: "{0}", with: number(peak))
                            .replacingOccurrences(of: "{1}", with: at.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            if points.count > 1 {
                EnergyTotals(summary: summary)
                Card {
                    Text(snapshot.date.formatted(date: .long, time: .omitted)).font(AppTypography.cardTitle)
                    EnergyLevelChart(points: points, summary: summary, window: window, selection: $selectedTime)
                    StressStripChart(points: snapshot.stress, window: window, selection: $selectedTime)
                    EnergyLegend(hasPredicted: points.contains(where: \.predicted))
                }
                Card {
                    Text(L("batteryBalance")).font(AppTypography.cardTitle)
                    balanceRows
                }
            } else {
                Card {
                    ChartWaitingState(tint: AppColors.metric(.energy)).frame(height: 120)
                    Text(L("batteryEmptyDetail")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var breakdown: (sleep: Double, rest: Double, stress: Double, load: Double, waking: Double) {
        detail.reduce((0.0, 0.0, 0.0, 0.0, 0.0)) { total, point in
            (total.0 + (point.asleep ? point.restoration : 0),
             total.1 + (point.asleep ? 0 : point.restoration),
             total.2 + point.stressDrain,
             total.3 + point.loadDrain,
             total.4 + point.baselineDrain)
        }
    }
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
                .foregroundStyle(positive ? AppColors.ageBetter : AppColors.warn)
                .frame(width: 20)
            Text(L(title)).font(.subheadline)
            Spacer(minLength: 4)
            Text((positive ? "+" : "−") + number(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// Says what the shaded bands mean, in a sentence rather than as isolated
/// words. "Dormido · Ejercicio · Estimación" named the colours but never said
/// what the reader was looking at.
private struct EnergyLegend: View {
    let hasPredicted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 14) {
                item("legendAsleep", AppColors.metric(.sleep))
                item("legendExercise", AppColors.metric(.strain))
                Spacer(minLength: 0)
            }
            Text(L(hasPredicted ? "batteryBandsDetailEstimated" : "batteryBandsDetail"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
    private func item(_ key: String, _ colour: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(colour.opacity(0.3))
                .frame(width: 12, height: 8)
            Text(L(key))
        }
    }
}

/// The day's curve. A point per fifteen-minute step scattered dozens of dots
/// across the plot and hid the shape; the periods that matter are shown as
/// bands behind the line instead, which is what the dots were trying to say.
/// Energy across the day. The line is tinted by its own height — amber when
/// depleted, green when full — and the night is marked as a band so the
/// overnight climb is attributable at a glance.
private struct EnergyLevelChart: View {
    let points: [TimelinePoint]
    let summary: EnergySummary
    let window: ClosedRange<Date>?
    @Binding var selection: Date?

    private var nearest: TimelinePoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("energyLevel")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                if summary.sleepSpan != nil {
                    Image(systemName: "moon.stars.fill").font(.caption2).foregroundStyle(AppColors.metric(.sleep))
                }
                Spacer()
                if let nearest {
                    Text(number(nearest.value) + "%").font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(AppColors.energyLevel(nearest.value / 100))
                }
            }
            Chart {
                if let sleep = summary.sleepSpan {
                    RectangleMark(xStart: .value("from", sleep.lowerBound), xEnd: .value("to", sleep.upperBound))
                        .foregroundStyle(AppColors.metric(.sleep).opacity(0.14))
                }
                ForEach(points) { point in
                    AreaMark(x: .value("t", point.date), y: .value("v", point.value))
                        .foregroundStyle(AppColors.verticalScale({ AppColors.energyLevel($0).opacity(0.30) }, fade: true))
                        .interpolationMethod(.monotone)
                }
                ForEach(points) { point in
                    LineMark(x: .value("t", point.date), y: .value("v", point.value))
                        .foregroundStyle(AppColors.verticalScale(AppColors.energyLevel))
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last, selection == nil {
                    PointMark(x: .value("t", last.date), y: .value("v", last.value))
                        .foregroundStyle(AppColors.energyLevel(last.value / 100)).symbolSize(60)
                }
                if let nearest {
                    RuleMark(x: .value("t", nearest.date))
                        .foregroundStyle(AppColors.ink.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    PointMark(x: .value("t", nearest.date), y: .value("v", nearest.value))
                        .foregroundStyle(AppColors.energyLevel(nearest.value / 100)).symbolSize(80)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: window ?? Date()...Date().addingTimeInterval(1))
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(AppColors.border)
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartXSelection(value: $selection)
            .frame(height: 170)
        }
    }
}

/// Activation beneath the level, on the same time axis. Blue when unusually
/// calm, then green, yellow, orange and red — the low end needed a colour of
/// its own, which a scale starting at green could not give it.
private struct StressStripChart: View {
    let points: [TimelinePoint]
    let window: ClosedRange<Date>?
    @Binding var selection: Date?

    private var data: [TimelinePoint] { points.filter { $0.value.isFinite }.sorted { $0.date < $1.date } }
    private var nearest: TimelinePoint? {
        guard let selection else { return nil }
        return data.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("stressLevel")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if let nearest {
                    Text(number(nearest.value)).font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(AppColors.stressLevel(nearest.value / 100))
                }
            }
            if data.isEmpty {
                Text(L("stressCalibrationDetail")).font(.caption2).foregroundStyle(.tertiary)
                    .frame(height: 90, alignment: .center)
            } else {
                Chart {
                    ForEach(data) { point in
                        AreaMark(x: .value("t", point.date), y: .value("v", point.value))
                            .foregroundStyle(AppColors.verticalScale({ AppColors.stressLevel($0).opacity(0.34) }, fade: true))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(data) { point in
                        LineMark(x: .value("t", point.date), y: .value("v", point.value))
                            .foregroundStyle(AppColors.verticalScale(AppColors.stressLevel))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let nearest {
                        RuleMark(x: .value("t", nearest.date))
                            .foregroundStyle(AppColors.ink.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: window ?? Date()...Date().addingTimeInterval(1))
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(AppColors.border)
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.border.opacity(0.6))
                        AxisValueLabel(format: .dateTime.hour()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXSelection(value: $selection)
                .frame(height: 110)
            }
        }
    }
}

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
                            caption: snapshot.score(.stress).value.map(StressEngine.band))
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
