import SwiftUI
import Charts
import PulseCore

/// A trend line over time. Contiguous runs share one series so a gap in the
/// data is a real gap; the previous version emitted one series per *pair* of
/// points, which meant 364 overlapping series for a year of history.
struct HealthTrendChart: View {
    var points: [TimelinePoint]
    var metric: Metric
    var height: CGFloat = 170
    var onScene = false
    var maximumGap: TimeInterval = 1800
    var yDomain: ClosedRange<Double>? = nil
    /// Draws the personal typical range behind the line.
    var showsReferenceBand = true
    /// Draws a seven-point moving average over the raw line.
    var showsAverage = false

    @State private var selection: Date?

    private var tint: Color { onScene ? AppColors.accentVivid : AppColors.metric(metric) }
    private var caption: Color { onScene ? .white.opacity(0.72) : .secondary }
    private var data: [TimelinePoint] { points.filter { $0.value.isFinite }.sorted { $0.date < $1.date } }

    private var selected: TimelinePoint? {
        guard let selection else { return nil }
        return data.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }
    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let upper = max(100, ceil((data.map(\.value).max() ?? 100) / 25) * 25)
        return 0...upper
    }
    /// Runs of points close enough in time to be joined.
    private var runs: [Run] {
        var result: [Run] = [], current: [TimelinePoint] = []
        for point in data {
            if let last = current.last, point.date.timeIntervalSince(last.date) > maximumGap {
                if current.count > 1 { result.append(Run(points: current)) }
                current = []
            }
            current.append(point)
        }
        if current.count > 1 { result.append(Run(points: current)) }
        return result
    }
    /// Centred seven-point mean, only where a full window exists.
    private var average: [TimelinePoint] {
        guard showsAverage, data.count >= 7 else { return [] }
        return (3..<(data.count - 3)).compactMap { index in
            let window = data[(index - 3)...(index + 3)].map(\.value)
            return Statistics.mean(window).map { TimelinePoint(date: data[index].date, value: $0) }
        }
    }
    private var reference: ClosedRange<Double>? {
        guard showsReferenceBand, data.count >= 7,
              let low = Statistics.percentile(data.map(\.value), 0.25),
              let high = Statistics.percentile(data.map(\.value), 0.75), high > low else { return nil }
        return low...high
    }
    /// Axis granularity follows the window rather than being fixed.
    private var xFormat: Date.FormatStyle {
        let span = (data.last?.date.timeIntervalSince(data.first?.date ?? Date()) ?? 0)
        if span <= 36 * 3600 { return .dateTime.hour() }
        if span <= 40 * 86400 { return .dateTime.day().month(.abbreviated) }
        return .dateTime.month(.abbreviated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.isEmpty {
                ChartWaitingState(tint: tint, onScene: onScene).frame(height: height)
            } else {
                header
                chart.frame(height: height)
                legend
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(selected.map { $0.date.formatted(xFormat) } ?? L("chartDayRange"))
            Spacer()
            Text(selected.map { number($0.value) }
                 ?? "\(number(data.map(\.value).min())) – \(number(data.map(\.value).max()))")
                .fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(caption)
    }

    @ChartContentBuilder private var band: some ChartContent {
        if let reference {
            RectangleMark(yStart: .value("low", reference.lowerBound),
                          yEnd: .value("high", reference.upperBound))
                .foregroundStyle(tint.opacity(onScene ? 0.16 : 0.08))
        }
    }
    @ChartContentBuilder private var lines: some ChartContent {
        ForEach(runs) { run in
            ForEach(run.points) { point in
                AreaMark(x: .value("t", point.date),
                         yStart: .value("zero", domain.lowerBound),
                         yEnd: .value("v", point.value),
                         series: .value("run", run.id))
                    .foregroundStyle(areaFill)
                    .interpolationMethod(.monotone)
            }
        }
        ForEach(runs) { run in
            ForEach(run.points) { point in
                LineMark(x: .value("t", point.date),
                         y: .value("v", point.value),
                         series: .value("run", run.id))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
    }
    @ChartContentBuilder private var averageLine: some ChartContent {
        ForEach(average) { point in
            LineMark(x: .value("t", point.date),
                     y: .value("avg", point.value),
                     series: .value("run", "average"))
                .foregroundStyle(tint.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                .interpolationMethod(.monotone)
        }
    }
    @ChartContentBuilder private var markers: some ChartContent {
        if let last = data.last, selected == nil {
            PointMark(x: .value("t", last.date), y: .value("v", last.value))
                .foregroundStyle(tint).symbolSize(42)
        }
        if let selected {
            RuleMark(x: .value("t", selected.date))
                .foregroundStyle(caption.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            PointMark(x: .value("t", selected.date), y: .value("v", selected.value))
                .foregroundStyle(tint).symbolSize(70)
        }
    }
    private var areaFill: LinearGradient {
        LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom)
    }
    private var chart: some View {
        Chart {
            band
            lines
            averageLine
            markers
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [domain.lowerBound, (domain.lowerBound + domain.upperBound) / 2, domain.upperBound]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(caption.opacity(0.18))
                // Without an explicit precision the axis prints the raw domain
                // bound, e.g. "21,9357" on a body-fat chart.
                // Fully qualified: a global `number(_:digits:)` helper makes the
                // bare `.number` shorthand ambiguous here.
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
                    .font(.caption2).foregroundStyle(caption)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: xFormat).font(.caption2).foregroundStyle(caption)
            }
        }
        .chartXSelection(value: $selection)
        .accessibilityLabel(L(metric.rawValue) + ": " + number(data.last?.value))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if reference != nil {
                Label(L("typicalRange"), systemImage: "rectangle.fill").foregroundStyle(tint.opacity(0.55))
            }
            if !average.isEmpty {
                Label(L("movingAverage"), systemImage: "minus").foregroundStyle(tint.opacity(0.55))
            }
            if data.contains(where: \.predicted) {
                Label(L("estimate"), systemImage: "circle.dotted").foregroundStyle(caption)
            }
            Spacer()
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
    }
}

private struct Run: Identifiable {
    let points: [TimelinePoint]
    var id: Date { points.first?.date ?? .distantPast }
}

struct ChartWaitingState: View {
    var tint: Color
    var onScene = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line").font(.title3).foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 15, style: .continuous))
            Text(L("chartWaiting")).font(.subheadline.weight(.medium))
            Text(L("chartWaitingDetail")).font(.caption)
                .foregroundStyle(onScene ? Color.white.opacity(0.7) : .secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(14)
    }
}

/// An open-bottom dial drawn as radial ticks rather than a solid band. Each
/// tick takes its colour from its own position on the scale, and ticks past the
/// value fall back to the track, so the instrument shows the whole range and
/// where you sit on it at once. A single filled arc showed only the latter.
struct MetricGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double?
    var size: CGFloat = 128
    /// Colour for a position on the scale, 0 (low) to 1 (high).
    var colour: (Double) -> Color = AppColors.stressLevel
    var caption: String?

    @State private var sweep: Double = 0

    private let count = 44
    private let span = 268.0
    private let start = 136.0
    private var fraction: Double { min(1, max(0, (value ?? 0) / 100)) }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let position = Double(index) / Double(count - 1)
                let lit = value != nil && position <= sweep
                Capsule()
                    .fill(lit ? colour(position) : AppColors.border)
                    .frame(width: size * 0.022, height: size * 0.085)
                    .offset(y: -size * 0.40)
                    .rotationEffect(.degrees(start + span * position + 90))
            }
            VStack(spacing: 0) {
                Text(number(value))
                    .font(.system(size: size * 0.26, weight: .semibold))
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(AppColors.ink)
                if let caption {
                    Text(L(caption))
                        .font(.system(size: size * 0.10, weight: .semibold))
                        .foregroundStyle(colour(fraction))
                }
            }
        }
        .frame(width: size, height: size)
        // The dial is open at the bottom, so the lower eighth of a square frame
        // is empty. Reclaiming it stops the card growing around nothing.
        .padding(.bottom, -size * 0.13)
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(value.map { number($0) } ?? L("noData"))
    }

    private func animate() {
        guard value != nil else { sweep = 0; return }
        guard !reduceMotion else { sweep = fraction; return }
        sweep = 0
        withAnimation(.smooth(duration: 0.7)) { sweep = fraction }
    }
}

#Preview("Chart and gauge") {
    let start = Calendar.current.startOfDay(for: Date())
    let points = (0..<40).map { index in
        TimelinePoint(date: start.addingTimeInterval(Double(index) * 900),
                      value: 62 + sin(Double(index) * 0.35) * 18,
                      predicted: (14...20).contains(index))
    }
    ScrollView {
        VStack(spacing: 20) {
            HealthTrendChart(points: points, metric: .energy, showsAverage: true)
            HStack {
                MetricGauge(value: 39, caption: "moderate")
                MetricGauge(value: 82, caption: "veryHigh")
            }
            HealthTrendChart(points: [], metric: .stress)
        }.padding()
    }
}
