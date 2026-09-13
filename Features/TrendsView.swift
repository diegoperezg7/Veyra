import SwiftUI
import PulseCore

/// Everything that only makes sense over time lives here: how each score has
/// moved, how the wellness-age estimate is converging, and which logged habits
/// precede better recovery. These existed before but were buried inside metric
/// details and a journal section.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 30
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    Picker(L("range"), selection: $range) {
                        ForEach([7, 30, 90, 365], id: \.self) { days in
                            Text(days == 365 ? "1Y" : days == 90 ? "3M" : "\(days)D").tag(days)
                        }
                    }.pickerStyle(.segmented)
                    WeekComparison(history: model.history, range: range)
                }

                ForEach(Metric.allCases) { metric in
                    Button { model.route = metric.rawValue } label: {
                        Card(accent: AppColors.metric(metric)) {
                            HStack {
                                Label(L(metric.rawValue), systemImage: metricSymbol(metric)).font(AppTypography.cardTitle)
                                Spacer()
                                Text(number(latest(metric))).font(.title3.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(AppColors.metric(metric))
                            }
                            HealthTrendChart(points: points(metric), metric: metric, height: 120, maximumGap: 26 * 3600)
                        }
                    }.buttonStyle(.plain)
                }

                NavigationLink { WellnessAgeView() } label: {
                    Card(accent: .purple) {
                        SectionTitle(title: "wellnessAge", symbol: "sparkles")
                        Text(L("wellnessAgeDetail")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)

                HabitInsightsCard(entries: model.entries, history: model.history)
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
        }
        .pulsePage().navigationTitle(L("trends")).navigationBarTitleDisplayMode(.inline)
    }

    private func days() -> [DailySnapshot] {
        Array(model.history.suffix(range))
    }
    private func points(_ metric: Metric) -> [TimelinePoint] {
        days().compactMap { day in day.score(metric).value.map { TimelinePoint(date: day.date, value: $0) } }
    }
    private func latest(_ metric: Metric) -> Double? {
        points(metric).last?.value
    }
    private func metricSymbol(_ metric: Metric) -> String {
        switch metric {
        case .recovery: "arrow.clockwise.heart"
        case .sleep: "moon.stars"
        case .strain: "flame"
        case .stress: "waveform.path.ecg"
        case .energy: "bolt.heart"
        }
    }
}

/// Compares the most recent half of the window against the previous half. With
/// fewer than four scored days on either side the comparison is not shown at
/// all rather than reported from one or two observations.
private struct WeekComparison: View {
    let history: [DailySnapshot]
    let range: Int
    var body: some View {
        let rows = Metric.allCases.compactMap { metric -> (Metric, Double, Double)? in
            let values = Array(history.suffix(range)).compactMap { $0.score(metric).value }
            guard values.count >= 8 else { return nil }
            let half = values.count / 2
            guard let recent = Statistics.mean(Array(values.suffix(half))),
                  let earlier = Statistics.mean(Array(values.prefix(values.count - half))) else { return nil }
            return (metric, recent, recent - earlier)
        }
        if rows.isEmpty {
            EmptyMetricState(title: "trendsCalibrating", detail: "trendsCalibratingDetail")
        } else {
            ForEach(rows, id: \.0) { metric, value, delta in
                HStack(spacing: 12) {
                    Circle().fill(AppColors.metric(metric)).frame(width: 8, height: 8)
                    Text(L(metric.rawValue)).font(.subheadline)
                    Spacer()
                    Text(number(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    DeltaBadge(delta: delta, higherIsBetter: metric.higherIsBetter)
                }
            }
        }
    }
}

/// The arrow states direction; the colour states whether that direction is an
/// improvement *for this metric*. Rising stress is not good news, and a green
/// up-arrow next to it said the opposite.
struct DeltaBadge: View {
    let delta: Double
    var higherIsBetter = true
    /// Below this the two halves are treated as the same, rather than dressing
    /// up noise as a trend.
    var threshold: Double = 1.5

    var body: some View {
        let flat = abs(delta) < threshold
        let rising = delta >= 0
        let good = rising == higherIsBetter
        let tint: Color = flat ? .secondary : (good ? AppColors.accent : AppColors.warn)
        return HStack(spacing: 3) {
            Image(systemName: flat ? "equal" : (rising ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption2.weight(.bold))
            if !flat { Text(number(abs(delta), digits: 1)).monospacedDigit() }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .frame(width: 68, alignment: .trailing)
    }
}

extension Metric {
    /// Whether a rising score is an improvement. Stress is the exception.
    var higherIsBetter: Bool { self != .stress }
}

/// Reuses `JournalInsightEngine`, which already refuses to report anything
/// below five explicitly logged yes and five explicitly logged no days.
private struct HabitInsightsCard: View {
    let entries: [LogEntry]
    let history: [DailySnapshot]
    private let habits = ["alcohol", "caffeine", "lateMeal", "meditation", "sunlight", "screenTime", "sauna", "travel", "sickness", "supplements", "pain", "mood"]
    var body: some View {
        Card {
            SectionTitle(title: "habitInsights", symbol: "list.bullet.clipboard")
            let found = habits.compactMap { habit in insight(habit).map { (habit, $0) } }
            if found.isEmpty {
                EmptyMetricState(title: "insightsMinimum", detail: "associationDisclaimer")
            } else {
                ForEach(found, id: \.0) { habit, insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L(habit)).font(.subheadline.weight(.medium))
                            Spacer()
                            DeltaBadge(delta: insight.difference)
                        }
                        Text("95%: \(number(insight.lower, digits: 1)) … \(number(insight.upper, digits: 1)) · n=\(insight.yesCount + insight.noCount)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(L("associationDisclaimer")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func insight(_ habit: String) -> HabitInsight? {
        let wakes = history.flatMap(\.sleepSessions).map(\.end).sorted()
        var byDay: [Date: LogEntry] = [:]
        for entry in entries.filter({ $0.kind == "journal" && $0.tags[habit] != nil }).sorted(by: { $0.date < $1.date }) {
            byDay[DayBoundary.biologicalDay(for: entry.date, wakes: wakes)] = entry
        }
        let observations = byDay.compactMap { day, entry -> HabitObservation? in
            guard let next = history.first(where: { $0.date > day }), let score = next.score(.recovery).value, let present = entry.tags[habit] else { return nil }
            return .init(present: present, outcome: score)
        }
        return JournalInsightEngine.calculate(observations)
    }
}
