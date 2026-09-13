import SwiftUI
import WidgetKit
import AppIntents
import PulseCore
#if os(iOS)
import ActivityKit
#endif

enum MetricChoice: String, AppEnum {
    case recovery, sleep, strain, stress, energy
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [MetricChoice: DisplayRepresentation] = [.recovery: "Recovery", .sleep: "Sleep", .strain: "Strain", .stress: "Stress", .energy: "Energy"]
}
struct MetricConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Veyra metric"
    @Parameter(title: "Metric", default: .recovery) var metric: MetricChoice
}
struct MetricEntry: TimelineEntry { let date: Date; let snapshot: DailySnapshot?; let configuration: MetricConfiguration }
struct MetricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MetricEntry { .init(date: Date(), snapshot: nil, configuration: MetricConfiguration()) }
    func snapshot(for configuration: MetricConfiguration, in context: Context) async -> MetricEntry { .init(date: Date(), snapshot: SharedSnapshotStore.read(), configuration: configuration) }
    func timeline(for configuration: MetricConfiguration, in context: Context) async -> Timeline<MetricEntry> { Timeline(entries: [.init(date: Date(), snapshot: SharedSnapshotStore.read(), configuration: configuration)], policy: .after(Date().addingTimeInterval(1800))) }
    func recommendations() -> [AppIntentRecommendation<MetricConfiguration>] {
        [AppIntentRecommendation(intent: MetricConfiguration(), description: "Recovery")]
    }
}
struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MetricEntry
    private var metric: Metric { Metric(rawValue: entry.configuration.metric.rawValue) ?? .recovery }
    private var score: ScoreResult? { entry.snapshot?.score(metric) }
    private var value: Double? { score?.value }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(L(metric.rawValue) + " " + number(value))
            case .accessoryCircular:
                Gauge(value: min(100, value ?? 0), in: 0...100) {
                    Image(systemName: symbol)
                } currentValueLabel: {
                    Text(number(value))
                }.gaugeStyle(.accessoryCircular)
            case .accessoryCorner:
                Text(number(value)).widgetLabel { Text(L(metric.rawValue)) }
            case .accessoryRectangular:
                rectangular
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .containerBackground(WidgetColors.background, for: .widget)
        .widgetURL(URL(string: "pulselab://" + metric.rawValue))
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

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(L(metric.rawValue), systemImage: symbol).font(.caption2.weight(.semibold))
            Text(number(value)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            if metric == .energy { WidgetBattery(value: value, height: 8) }
        }
    }

    /// The small widget leads with the number and, for energy, the battery
    /// itself; the previous version showed a bare figure for every metric.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L(metric.rawValue), systemImage: symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if metric == .energy {
                Text(number(value) + "%").font(.system(size: 38, weight: .semibold)).monospacedDigit()
                WidgetBattery(value: value, height: 14)
            } else {
                WidgetRing(value: value, tint: WidgetColors.metric(metric), size: 74)
            }
            Spacer(minLength: 0)
            Text(updated).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three headline scores at a glance, which is what a medium widget is for.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Veyra").font(.caption.weight(.bold)).foregroundStyle(WidgetColors.accent)
                Spacer()
                Text(updated).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                ForEach([Metric.recovery, .sleep, .strain]) { item in
                    VStack(spacing: 6) {
                        WidgetRing(value: entry.snapshot?.score(item).value, tint: WidgetColors.metric(item), size: 52)
                        Text(L(item.rawValue)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                }
            }
            if let energy = entry.snapshot?.score(.energy).value {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill").font(.caption2).foregroundStyle(WidgetColors.accent)
                    WidgetBattery(value: energy, height: 10)
                    Text(number(energy) + "%").font(.caption.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }

    private var updated: String {
        entry.snapshot.map { $0.updatedAt.formatted(date: .omitted, time: .shortened) } ?? "—"
    }
}

enum WidgetColors {
    static let background = Color.adaptiveWidget(light: 0xFFFFFF, dark: 0x000000)
    static let accent = Color.adaptiveWidget(light: 0x0A7F68, dark: 0x27F6CC)
    static let track = Color.adaptiveWidget(light: 0xE2E8E6, dark: 0x232A27)
    static func metric(_ metric: Metric) -> Color {
        switch metric {
        case .recovery: accent
        case .sleep: .adaptiveWidget(light: 0x3F55B8, dark: 0x8FA5FF)
        case .strain: .adaptiveWidget(light: 0xBE5411, dark: 0xFF9E52)
        case .stress: .adaptiveWidget(light: 0x8A3FB8, dark: 0xC98CF5)
        case .energy: .adaptiveWidget(light: 0x8A6A00, dark: 0xFFD666)
        }
    }
}
extension Color {
    /// Mirrors the app's adaptive tokens. Widgets cannot import the app target,
    /// so the two hex pairs are repeated here deliberately.
    static func adaptiveWidget(light: UInt32, dark: UInt32) -> Color {
        #if os(watchOS)
        return Color(red: Double((dark >> 16) & 0xFF) / 255, green: Double((dark >> 8) & 0xFF) / 255, blue: Double(dark & 0xFF) / 255)
        #else
        return Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        #endif
    }
}

struct WidgetRing: View {
    var value: Double?
    var tint: Color
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(WidgetColors.track, lineWidth: size * 0.11)
            Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(number(value)).font(.system(size: size * 0.33, weight: .semibold)).monospacedDigit()
        }.frame(width: size, height: size)
    }
}

struct WidgetBattery: View {
    var value: Double?
    var height: CGFloat
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetColors.track)
                Capsule().fill(WidgetColors.accent)
                    .frame(width: proxy.size.width * min(1, max(0, (value ?? 0) / 100)))
            }
        }.frame(height: height)
    }
}

struct PulseMetricWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PulseMetric", intent: MetricConfiguration.self, provider: MetricProvider()) { PulseWidgetView(entry: $0) }.configurationDisplayName("Veyra").description("Recovery, sleep, strain, stress and energy.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}
#if os(iOS)
struct StrengthActivityWidget: Widget {
    var body: some WidgetConfiguration { ActivityConfiguration(for: StrengthAttributes.self) { context in HStack { Image(systemName: "dumbbell.fill").foregroundStyle(.green); VStack(alignment: .leading) { Text(context.state.exercise).font(.headline); Text("\(context.state.completedSets)/\(context.state.totalSets) " + L("sets")).font(.caption) }; Spacer(); Text(context.attributes.start, style: .timer).monospacedDigit() }.padding().widgetURL(URL(string: "pulselab://activeStrength")) } dynamicIsland: { context in DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Image(systemName: "dumbbell.fill").foregroundStyle(.green) }
        DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.start, style: .timer) }
        DynamicIslandExpandedRegion(.bottom) { Text(context.state.exercise) }
    } compactLeading: { Image(systemName: "dumbbell.fill") } compactTrailing: { Text("\(context.state.completedSets)/\(context.state.totalSets)") } minimal: { Image(systemName: "dumbbell.fill") }.widgetURL(URL(string: "pulselab://activeStrength")) } }
}
#endif
@main struct PulseWidgetBundle: WidgetBundle { var body: some Widget { PulseMetricWidget(); #if os(iOS)
    StrengthActivityWidget()
    #endif
} }
