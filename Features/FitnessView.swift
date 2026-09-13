import SwiftUI
import Charts
import PulseCore

/// Training seen over time rather than as four loose figures. The load card
/// now plots acute against chronic, which is the whole point of the ratio, and
/// workouts are listed with what they actually contained.
struct FitnessView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 42

    private var ordered: [DailySnapshot] { model.history }
    private var load: CardioLoad { CardioLoadEngine.calculate(ordered.map { $0.rawLoad ?? 0 }) }

    /// Acute and chronic averages recomputed day by day, so the chart shows how
    /// the ratio got where it is instead of only its final value.
    private var loadSeries: (acute: [TimelinePoint], chronic: [TimelinePoint]) {
        var acute = 0.0, chronic = 0.0
        var a: [TimelinePoint] = [], c: [TimelinePoint] = []
        for day in ordered {
            let value = max(0, day.rawLoad ?? 0)
            acute += (value - acute) * (1 - exp(-1 / 7.0))
            chronic += (value - chronic) * (1 - exp(-1 / 42.0))
            a.append(.init(date: day.date, value: acute))
            c.append(.init(date: day.date, value: chronic))
        }
        return (Array(a.suffix(range)), Array(c.suffix(range)))
    }
    private var loggedSessions: [StrengthSession] {
        model.sessions.filter { $0.end != nil }
    }
    private var workouts: [WorkoutSummary] {
        model.history.flatMap(\.workouts).sorted { $0.start > $1.start }
    }

    private var vo2: Double? { model.latestVital("vo2")?.value }
    /// Percentile against adults of the same age and sex; nil when either is
    /// unknown, since the comparison has no meaning without them.
    private var vo2Percentile: Double? {
        guard let vo2, let age = WellnessAgeEngine.age(from: model.preferences.birthDate) else { return nil }
        return VO2MaxNorms.percentile(vo2: vo2, age: age, sex: model.preferences.biologicalSex)
    }
    /// The trailing seven days, not the calendar week: the guideline is a
    /// weekly volume, and a Monday should not reset it to zero.
    private var weeklyActivity: WeeklyActivityEngine.Result {
        let end = Date()
        return WeeklyActivityEngine.calculate(workouts: model.history.flatMap(\.workouts),
                                              from: end.addingTimeInterval(-7 * 86400), to: end)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    tile("steps", model.today.vital("steps")?.value, "", "shoeprints.fill", AppColors.accent)
                    tile("activeEnergy", model.today.vital("activeEnergy")?.value, "kcal", "flame.fill", AppColors.metric(.strain))
                }
                ActivityCalendarCard(history: model.history)
                ActivitySummaryCard(history: model.history)

                Card {
                    HStack {
                        Text(L("cardioLoad")).font(AppTypography.cardTitle)
                        Spacer()
                        Text(L(load.status)).font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(AppColors.accentSoft, in: Capsule())
                            .foregroundStyle(AppColors.accent)
                    }
                    LoadChart(acute: loadSeries.acute, chronic: loadSeries.chronic)
                    HStack(spacing: 0) {
                        loadFigure("acuteLoad", load.acute, AppColors.metric(.strain))
                        loadFigure("chronicLoad", load.chronic, AppColors.metric(.sleep))
                        // The ratio is not a series on the chart, so it carries no swatch.
                        loadFigure("ratio", load.ratio, nil, digits: 2)
                    }
                    Text(L("loadExplanation")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FitnessStandardsCard(vo2: vo2, percentile: vo2Percentile, activity: weeklyActivity)
                if !loggedSessions.isEmpty {
                    StrengthVolumeCard(sessions: loggedSessions, catalogue: model.exercises)
                    StrengthProgressCard(sessions: loggedSessions, catalogue: model.exercises)
                }

                Card {
                    Text(L("activity")).font(AppTypography.cardTitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(["distance", "exercise", "restingEnergy", "vo2", "walkingHR", "hrRecovery"], id: \.self) { key in
                            let vital = model.today.vital(key)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(key)).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(vital.map { number($0.value, digits: key == "vo2" ? 1 : 0) } ?? "—")
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                Text(vital?.unit ?? "").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(AppColors.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                Button { model.route = "strength" } label: {
                    Card { SectionTitle(title: "strengthBuilder", symbol: "dumbbell")
                        Text(L("strengthDetail")).font(.subheadline).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
                Button { model.route = "plan" } label: {
                    Card { SectionTitle(title: "trainingPlan", symbol: "calendar")
                        Text(L("planDetail")).font(.subheadline).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)

                Card {
                    Text(L("workouts")).font(AppTypography.cardTitle)
                    if workouts.isEmpty {
                        EmptyMetricState()
                    } else {
                        ForEach(Array(workouts.prefix(20))) { workout in
                            NavigationLink { WorkoutDetailView(workout: workout) } label: { WorkoutRow(workout: workout) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
        }
        .pulsePage().navigationTitle(L("fitness")).navigationBarTitleDisplayMode(.inline)
        // The strength cards name exercises and group them by muscle, so this
        // screen needs the catalogue too.
        .task { await model.loadExercises() }
    }

    private func tile(_ key: String, _ value: Double?, _ unit: String, _ symbol: String, _ tint: Color) -> some View {
        Card {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(number(value)).font(.title2.weight(.semibold)).monospacedDigit()
            Text(unit.isEmpty ? L(key) : L(key) + " · " + unit)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private func loadFigure(_ key: String, _ value: Double?, _ tint: Color?, digits: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                Text(L(key)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(number(value, digits: digits)).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Acute (7-day) against chronic (42-day) load. Two lines on one scale, because
/// the relationship between them is the information.
private struct LoadChart: View {
    let acute: [TimelinePoint]
    let chronic: [TimelinePoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if acute.count < 2 {
                ChartWaitingState(tint: AppColors.metric(.strain)).frame(height: 140)
            } else {
                Chart {
                    ForEach(chronic) { point in
                        AreaMark(x: .value("t", point.date), y: .value("v", point.value))
                            .foregroundStyle(LinearGradient(colors: [AppColors.metric(.sleep).opacity(0.22), AppColors.metric(.sleep).opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(chronic) { point in
                        LineMark(x: .value("t", point.date), y: .value("v", point.value), series: .value("s", "chronic"))
                            .foregroundStyle(AppColors.metric(.sleep))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(acute) { point in
                        LineMark(x: .value("t", point.date), y: .value("v", point.value), series: .value("s", "acute"))
                            .foregroundStyle(AppColors.metric(.strain))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AppColors.border)
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    /// The figures that exist for this session, in a row of their own. Packed
    /// onto the same line as the duration they wrapped mid-unit — "602" on one
    /// line and "kcal" on the next.
    private var figures: [String] {
        var values: [String] = []
        if let distance = workout.distanceMeters, distance > 0 {
            values.append(number(distance / 1000, digits: 1) + " km")
        }
        if let calories = workout.calories, calories > 0 { values.append(number(calories) + " kcal") }
        if let average = workout.averageHeartRate { values.append(number(average) + " bpm") }
        return values
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(AppColors.metric(.strain), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L(workout.activity)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(duration(workout.minutes))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                if !figures.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(figures.enumerated()), id: \.offset) { index, value in
                            if index > 0 {
                                Circle().fill(AppColors.border).frame(width: 3, height: 3)
                            }
                            Text(value)
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary).padding(.top, 3)
        }
        .padding(.vertical, 7)
    }

    private var symbol: String { WorkoutStyle.symbol(workout.activity) }
}

