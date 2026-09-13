import SwiftUI
import Charts
import PulseCore

/// The day's activation, minute by minute, coloured by the value itself:
/// green while low, amber through the middle, red at the top. A single purple
/// line said what the metric was but never how the day had gone.
struct StressDayChart: View {
    var points: [TimelinePoint]
    var height: CGFloat = 210
    @State private var selection: Date?

    private var data: [TimelinePoint] { points.filter { $0.value.isFinite }.sorted { $0.date < $1.date } }
    private var selected: TimelinePoint? {
        guard let selection else { return nil }
        return data.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }
    /// Colour by height on the scale, so the chart reads before the axis does.
    private var fill: LinearGradient {
        LinearGradient(stops: [
            .init(color: AppColors.scale(1.0).opacity(0.85), location: 0),
            .init(color: AppColors.scale(0.72).opacity(0.75), location: 0.24),
            .init(color: AppColors.scale(0.42).opacity(0.6), location: 0.52),
            .init(color: AppColors.scale(0.0).opacity(0.45), location: 0.80),
            .init(color: AppColors.scale(0.0).opacity(0.12), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.isEmpty {
                ChartWaitingState(tint: AppColors.metric(.stress)).frame(height: height)
            } else {
                header
                chart.frame(height: height)
                scale
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let selected {
                Text(selected.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(number(selected.value)).font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(AppColors.scale(selected.value / 100))
                Text(L(StressEngine.band(selected.value)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.scale(selected.value / 100))
            } else {
                statistic("min", data.map(\.value).min())
                Spacer()
                statistic("average", Statistics.mean(data.map(\.value)))
                Spacer()
                statistic("max", data.map(\.value).max())
            }
        }
    }
    private func statistic(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L(title)).font(.caption2).foregroundStyle(.secondary)
            Text(number(value)).font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(value.map { AppColors.scale($0 / 100) } ?? .secondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data) { point in
                AreaMark(x: .value("t", point.date), y: .value("v", point.value))
                    .foregroundStyle(fill)
                    .interpolationMethod(.monotone)
            }
            ForEach(data) { point in
                LineMark(x: .value("t", point.date), y: .value("v", point.value))
                    .foregroundStyle(AppColors.ink.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .interpolationMethod(.monotone)
            }
            if let selected {
                RuleMark(x: .value("t", selected.date))
                    .foregroundStyle(AppColors.ink.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                PointMark(x: .value("t", selected.date), y: .value("v", selected.value))
                    .foregroundStyle(AppColors.scale(selected.value / 100))
                    .symbolSize(80)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.border)
                AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.border.opacity(0.6))
                AxisValueLabel(format: .dateTime.hour()).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartXSelection(value: $selection)
    }

    /// Names the colours, so the gradient is information rather than decoration.
    private var scale: some View {
        HStack(spacing: 0) {
            ForEach(Array(["veryLow", "low", "moderate", "high", "veryHigh"].enumerated()), id: \.offset) { index, key in
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(AppColors.scale(Double(index) / 4))
                        .frame(height: 4)
                    Text(L(key)).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
