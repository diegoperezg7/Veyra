import SwiftUI
import Charts
import PulseCore

/// A month of training at a glance: one mark per day, darker the more you did.
/// Reading "did I train this week" off a list of sessions takes counting; this
/// does not.
struct ActivityCalendarCard: View {
    var history: [DailySnapshot]
    var days: Int = 30
    private let calendar = Calendar.current

    private var window: [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = history.first { calendar.isDate($0.date, inSameDayAs: date) }?.workouts.count ?? 0
            return (date, count)
        }
    }

    /// Leading blanks so the first column is a Monday.
    private var leadingBlanks: Int {
        guard let first = window.first?.date else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        // Calendar weekdays start on Sunday; Veyra's grid starts on Monday.
        return (weekday + 5) % 7
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        Card(spacing: 12) {
            HStack {
                Label(L("activityCalendar"), systemImage: "calendar").font(AppTypography.cardTitle)
                Spacer()
                Text(L("lastDays").replacingOccurrences(of: "{0}", with: "\(days)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(.clear).frame(height: 20)
                }
                ForEach(window, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(fill(day.count))
                        .frame(height: 20)
                        .overlay {
                            if calendar.isDateInToday(day.date) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(AppColors.ink.opacity(0.45), lineWidth: 1.5)
                            }
                        }
                }
            }
            HStack(spacing: 14) {
                legend(1, "oneActivity")
                legend(2, "twoActivities")
                legend(3, "threeOrMore")
            }
            .padding(.top, 2)
        }
    }

    private func fill(_ count: Int) -> Color {
        switch count {
        case 0: AppColors.surfaceRaised
        case 1: AppColors.accentVivid.opacity(0.45)
        case 2: AppColors.accentVivid.opacity(0.75)
        default: AppColors.accentVivid
        }
    }

    private func legend(_ count: Int, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(fill(count)).frame(width: 8, height: 8)
            Text(L(title)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Minutes trained over the window, as a running total. A month of training is
/// a slope, not a number.
struct ActivitySummaryCard: View {
    var history: [DailySnapshot]
    var days: Int = 30
    private let calendar = Calendar.current

    private var points: [TimelinePoint] {
        let today = calendar.startOfDay(for: Date())
        var running = 0.0
        return (0..<days).reversed().compactMap { offset -> TimelinePoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let minutes = history.first { calendar.isDate($0.date, inSameDayAs: date) }?
                .workouts.reduce(0) { $0 + $1.minutes } ?? 0
            running += minutes
            return TimelinePoint(date: date, value: running)
        }
    }
    private var total: Double { points.last?.value ?? 0 }

    var body: some View {
        Card(spacing: 10) {
            Label(L("activitySummary"), systemImage: "chart.line.uptrend.xyaxis").font(AppTypography.cardTitle)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(duration(total)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                Spacer()
                if let first = points.first?.date, let last = points.last?.date {
                    Text(first.formatted(.dateTime.day().month(.abbreviated)) + " – "
                         + last.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart(points) { point in
                AreaMark(x: .value("d", point.date), y: .value("min", point.value))
                    .foregroundStyle(LinearGradient(colors: [AppColors.metric(.strain).opacity(0.28), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("d", point.date), y: .value("min", point.value))
                    .foregroundStyle(AppColors.metric(.strain))
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(AppColors.border)
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
        }
    }
}

/// Volume per muscle group, laid out as a body rather than as a list: the
/// point is to see at a glance what is being neglected.
struct StrengthVolumeCard: View {
    var sessions: [StrengthSession]
    var catalogue: [ExerciseDefinition]
    var days: Int = 30

    private var totals: [String: Double] {
        let end = Date()
        return StrengthHistoryEngine.volumeByGroup(
            sessions: sessions, catalogue: catalogue,
            from: end.addingTimeInterval(-Double(days) * 86400), to: end)
    }
    private var peak: Double { max(1, totals.values.max() ?? 1) }
    /// Ordered the way a body reads: chest and shoulders at the top, arms at
    /// the sides, core and legs below.
    private let order = ["chest", "arms", "back", "core", "legs", "shoulders"]

    var body: some View {
        Card(spacing: 14) {
            HStack {
                Label(L("totalVolumeTitle"), systemImage: "scalemass").font(AppTypography.cardTitle)
                Spacer()
                Text(L("lastDays").replacingOccurrences(of: "{0}", with: "\(days)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(order, id: \.self) { group in
                    let volume = totals[group] ?? 0
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .frame(height: 86)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(volume > 0 ? AppColors.accentVivid : AppColors.border)
                                .frame(height: max(volume > 0 ? 6 : 3, 86 * volume / peak))
                        }
                        Image(systemName: ExerciseVocabulary.groupSymbol(group))
                            .font(.caption2)
                            .foregroundStyle(volume > 0 ? AnyShapeStyle(AppColors.accent) : AnyShapeStyle(.tertiary))
                        Text(L("group." + group)).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(compact(volume)).font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(volume > 0 ? AnyShapeStyle(AppColors.ink) : AnyShapeStyle(.tertiary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(L("totalVolumeDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 5.980 kg reads worse than 5,98 K at this size.
    private func compact(_ value: Double) -> String {
        value >= 1000 ? number(value / 1000, digits: 1) + " t" : number(value) + " kg"
    }
}

/// Which exercises you are actually progressing on, newest session last.
struct StrengthProgressCard: View {
    var sessions: [StrengthSession]
    var catalogue: [ExerciseDefinition]

    private struct Row: Identifiable {
        var id: String
        var name: String
        var equipment: String
        var sessions: Int
        var points: [TimelinePoint]
    }

    private var rows: [Row] {
        let finished = sessions.filter { $0.end != nil }.sorted { $0.start < $1.start }
        let byID = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var grouped: [String: [(Date, Double)]] = [:]
        for session in finished {
            for id in Set(session.sets.filter(\.completed).map(\.exerciseID)) {
                // One point per session: the best estimated one-rep max in it,
                // which is what makes different rep counts comparable.
                let best = session.sets
                    .filter { $0.exerciseID == id && $0.completed }
                    .compactMap { StrengthEngine.estimated1RM(weight: $0.weightKg, reps: $0.reps) }
                    .max()
                guard let best, best > 0 else { continue }
                grouped[id, default: []].append((session.start, best))
            }
        }
        return grouped
            .map { id, values in
                Row(id: id,
                    name: byID[id]?.name ?? id,
                    equipment: byID[id].map { L("equipment." + $0.equipment) } ?? "",
                    sessions: values.count,
                    points: values.map { TimelinePoint(date: $0.0, value: $0.1) })
            }
            .sorted { ($0.sessions, $0.name) > ($1.sessions, $1.name) }
    }

    var body: some View {
        Card(spacing: 12) {
            Label(L("strengthProgress"), systemImage: "chart.line.uptrend.xyaxis").font(AppTypography.cardTitle)
            ForEach(rows.prefix(6)) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(row.equipment + " · " + "\(row.sessions) "
                             + L(row.sessions == 1 ? "sessionSingular" : "sessionPlural"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if row.points.count > 1 {
                        Chart(row.points) { point in
                            LineMark(x: .value("d", point.date), y: .value("kg", point.value))
                                .foregroundStyle(AppColors.accentVivid)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(width: 88, height: 30)
                    }
                    if let last = row.points.last {
                        Text(number(last.value) + " kg")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                if row.id != rows.prefix(6).last?.id { Divider().overlay(AppColors.divider) }
            }
            Text(L("strengthProgressDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Strain against the target the app set for the day. Training harder than
/// planned is not automatically good and not automatically bad — what matters
/// is whether it is a pattern, so the card shows the run, not just today.
struct StrainPerformanceCard: View {
    var history: [DailySnapshot]
    var days: Int = 30

    private struct Day: Identifiable {
        var date: Date
        var strain: Double
        var target: Double?
        var id: Date { date }
    }

    private var window: [Day] {
        history.suffix(days).compactMap { snapshot in
            guard let strain = snapshot.score(.strain).value else { return nil }
            return Day(date: snapshot.date, strain: strain, target: snapshot.targetStrain)
        }
    }
    /// How far the last week sat from its targets, as a percentage. Only days
    /// that had a target count: before the app has a baseline there is none.
    private var deviation: Double? {
        let recent = window.suffix(7).filter { $0.target != nil }
        guard recent.count >= 3 else { return nil }
        let strain = recent.reduce(0) { $0 + $1.strain }
        let target = recent.reduce(0) { $0 + ($1.target ?? 0) }
        guard target > 0 else { return nil }
        return (strain - target) / target * 100
    }

    var body: some View {
        Card(spacing: 12) {
            Label(L("strainPerformance"), systemImage: "target").font(AppTypography.cardTitle)
            if let deviation {
                // Inside the band is the thing worth marking green. Training
                // under target is not automatically good and over target is not
                // automatically bad, so the colour says in-or-out, not
                // better-or-worse.
                let inside = abs(deviation) <= 15
                let above = deviation >= 0
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text((above ? "+" : "−") + number(abs(deviation)) + "%")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(inside ? AppColors.accent : AppColors.metric(.strain))
                    Text(L(inside ? "onTarget" : above ? "aboveTarget" : "belowTarget"))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label(L("calibrating"), systemImage: "hourglass")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(window) { day in
                    if let target = day.target {
                        // The target band: a corridor, not a line, because
                        // hitting a number exactly is not the goal.
                        AreaMark(x: .value("d", day.date),
                                 yStart: .value("from", target * 0.85),
                                 yEnd: .value("to", target * 1.15))
                            .foregroundStyle(AppColors.accentSoft)
                    }
                }
                ForEach(window) { day in
                    LineMark(x: .value("d", day.date), y: .value("strain", day.strain))
                        .foregroundStyle(AppColors.metric(.strain))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(AppColors.border)
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            Text(L("strainPerformanceDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
