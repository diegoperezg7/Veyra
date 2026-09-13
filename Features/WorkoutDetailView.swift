import SwiftUI
import Charts
import PulseCore

/// A single workout, in full. The previous version was four rows and a list of
/// zone minutes; what a session actually raises are the questions answered
/// here — how hard was it, where did the time go, and what did it cost.
struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    let workout: WorkoutSummary

    private var zoneShare: [Double]? { WorkoutAnalysis.zoneShare(workout) }
    private var tension: [MuscleTensionEngine.Share] {
        guard let session = loggedSession else { return [] }
        return MuscleTensionEngine.shares(sets: session.sets, catalogue: model.exercises)
    }
    private var totals: MuscleTensionEngine.Totals? {
        loggedSession.map { MuscleTensionEngine.totals($0.sets) }
    }
    /// Lifting against cardiovascular work. Both sides are the components
    /// strain is already built from, so this cannot disagree with it.
    private var split: MuscleTensionEngine.Split? {
        guard let session = loggedSession else { return nil }
        let strength = session.sets.filter(\.completed).reduce(0.0) { total, set in
            total + StrengthEngine.load(set, estimated1RM: StrengthHistoryEngine.best(exercise: set.exerciseID, in: model.sessions)
                .flatMap { StrengthEngine.estimated1RM(weight: $0.weightKg, reps: $0.reps) })
        }
        return MuscleTensionEngine.split(strengthLoad: strength, cardiacLoad: load)
    }
    private var focus: WorkoutAnalysis.Focus? { WorkoutAnalysis.focus(workout) }
    private var load: Double { WorkoutAnalysis.load(workout) }
    private var history: [WorkoutSummary] { model.allWorkouts }
    private var comparison: Double? { WorkoutAnalysis.loadComparison(workout, history: history) }
    /// The strength session logged for this workout, if there is one.
    private var loggedSession: StrengthSession? {
        model.sessions.first { session in
            session.end != nil
            && session.start >= workout.start.addingTimeInterval(-3600)
            && session.start <= workout.end.addingTimeInterval(3600)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline
                if split != nil || !tension.isEmpty { breakdownCard }
                if workout.heartRate?.isEmpty == false { heartRateCard }
                if zoneShare != nil { zonesCard }
                if let focus { focusCard(focus) }
                impactCard
                if let recovery = workout.heartRateRecovery { recoveryCard(recovery) }
                detailsCard
                sourceCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L(workout.activity))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadExercises() }
    }

    // MARK: - Headline

    private var headline: some View {
        Card(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: WorkoutStyle.symbol(workout.activity))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppColors.metric(.strain), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(workout.activity)).font(.title3.weight(.bold))
                    Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let intensity = WorkoutAnalysis.intensity(workout) {
                    // The ring is this session's own intensity — the share of
                    // heart-rate reserve it averaged — not the day's strain.
                    VStack(spacing: 3) {
                        ScoreRing(metric: .strain, value: intensity, size: 62)
                        Text(L("intensity")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Divider().overlay(AppColors.divider)
            HStack(spacing: 0) {
                figure(duration(workout.minutes), "duration")
                figure(workout.calories.map { number($0) } ?? "—", "calories", unit: "kcal")
                if let distance = workout.distanceMeters, distance > 0 {
                    figure(number(distance / 1000, digits: 2), "distance", unit: "km")
                }
                if let average = workout.averageHeartRate {
                    figure(number(average), "averageHeartRate", unit: "bpm")
                }
            }
            if let totals, totals.sets > 0 {
                Divider().overlay(AppColors.divider)
                HStack(spacing: 0) {
                    figure(number(totals.volume), "totalVolume", unit: "kg")
                    figure("\(totals.repetitions)", "totalRepetitions")
                    figure("\(totals.sets)", "series")
                    figure("\(totals.exercises)", "exercises")
                }
            }
        }
    }

    /// What the session was made of: lifting against cardiovascular work, and
    /// which muscles carried it.
    private var breakdownCard: some View {
        Card(spacing: 14) {
            Label(L("workoutBreakdown"), systemImage: "chart.pie").font(AppTypography.cardTitle)
            if let split {
                HStack(alignment: .top, spacing: 0) {
                    splitFigure(split.muscular, "muscularWork", AppColors.metric(.strain))
                    Divider().frame(height: 34).overlay(AppColors.divider)
                    splitFigure(split.cardio, "cardioWork", AppColors.metric(.stress))
                }
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Capsule().fill(AppColors.metric(.strain))
                            .frame(width: max(0, proxy.size.width * split.muscular / 100))
                        Capsule().fill(AppColors.metric(.stress))
                    }
                }
                .frame(height: 10)
            }
            if !tension.isEmpty {
                Divider().overlay(AppColors.divider)
                Text(L("muscleTension")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                MuscleTensionChart(shares: tension)
                Text(L("muscleTensionDetail")).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func splitFigure(_ percent: Double, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(number(percent) + "%").font(.title2.weight(.bold)).monospacedDigit()
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(L(title)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 10)
    }

    private func figure(_ value: String, _ title: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.bold)).monospacedDigit()
                if let unit { Text(unit).font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(L(title)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Heart rate

    private var heartRateCard: some View {
        Card(spacing: 12) {
            HStack {
                Label(L("heartRate"), systemImage: "heart.fill").font(AppTypography.cardTitle)
                Spacer()
                if let maximum = workout.maximumHeartRate {
                    Text(L("maximumShort") + " " + number(maximum) + " bpm")
                        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            WorkoutHeartRateChart(workout: workout)
            ZoneScale(resting: workout.restingHeartRate, maximum: workout.maximumHeartRateReference)
        }
    }

    // MARK: - Zones

    private var zonesCard: some View {
        Card(spacing: 12) {
            Label(L("timeInZones"), systemImage: "chart.bar.xaxis").font(AppTypography.cardTitle)
            let minutes = WorkoutAnalysis.zoneMinutes(workout)
            let share = zoneShare ?? []
            let peak = max(1, minutes.max() ?? 1)
            ForEach(Array(minutes.enumerated().reversed()), id: \.offset) { index, value in
                HStack(spacing: 10) {
                    Text("Z\(index)")
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(WorkoutStyle.zoneColor(index))
                        .frame(width: 24, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.surfaceRaised)
                            Capsule().fill(WorkoutStyle.zoneColor(index))
                                .frame(width: max(value > 0 ? 4 : 0, proxy.size.width * value / peak))
                        }
                    }
                    .frame(height: 10)
                    Text(duration(value)).font(.caption.weight(.medium)).monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                    Text(number(share.indices.contains(index) ? share[index] : 0) + "%")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            Text(L("zonesDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Focus

    private func focusCard(_ focus: WorkoutAnalysis.Focus) -> some View {
        Card(spacing: 12) {
            HStack {
                Label(L("cardioFocus"), systemImage: "target").font(AppTypography.cardTitle)
                Spacer()
                Text(L(focus.dominant)).font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(AppColors.accentSoft, in: Capsule())
                    .foregroundStyle(AppColors.accent)
            }
            // One bar, three parts: the split is a whole, not three numbers.
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    segment(focus.lowAerobic, proxy.size.width, WorkoutStyle.zoneColor(2))
                    segment(focus.highAerobic, proxy.size.width, WorkoutStyle.zoneColor(4))
                    segment(focus.anaerobic, proxy.size.width, WorkoutStyle.zoneColor(5))
                }
            }
            .frame(height: 12)
            focusRow("focusLowAerobic", focus.lowAerobic, WorkoutStyle.zoneColor(2))
            focusRow("focusHighAerobic", focus.highAerobic, WorkoutStyle.zoneColor(4))
            focusRow("focusAnaerobic", focus.anaerobic, WorkoutStyle.zoneColor(5))
            Text(L("cardioFocusDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func segment(_ share: Double, _ width: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: max(0, width * share / 100))
    }

    private func focusRow(_ title: String, _ share: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(L(title)).font(.caption)
            Spacer()
            Text(number(share) + "%").font(.caption.weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: - Impact

    private var impactCard: some View {
        Card(spacing: 10) {
            Label(L("cardiacImpact"), systemImage: "bolt.heart").font(AppTypography.cardTitle)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(load)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                Text(L("cardiacLoadUnit")).font(.caption).foregroundStyle(.secondary)
            }
            if let comparison {
                let above = comparison >= 0
                Label(L(above ? "loadAboveUsual" : "loadBelowUsual")
                        .replacingOccurrences(of: "{0}", with: number(abs(comparison))),
                      systemImage: above ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(above ? AppColors.metric(.strain) : AppColors.accent)
            } else {
                Label(L("calibrating"), systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let share = WorkoutAnalysis.shareOfDay(workout, dayLoad: dayLoad) {
                Text(L("shareOfDayStrain").replacingOccurrences(of: "{0}", with: number(share)))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("cardiacImpactDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dayLoad: Double {
        model.history.first { Calendar.current.isDate($0.date, inSameDayAs: workout.start) }?.rawLoad ?? 0
    }

    // MARK: - Recovery

    private func recoveryCard(_ recovery: Double) -> some View {
        Card(spacing: 8) {
            Label(L("heartRateRecovery"), systemImage: "arrow.down.heart").font(AppTypography.cardTitle)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(recovery)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L(HeartRateRecoveryEngine.band(recovery)))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(AppColors.accentSoft, in: Capsule())
                    .foregroundStyle(AppColors.accent)
            }
            Text(L("heartRateRecoveryDetail")).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Strength details

    private var detailsCard: some View {
        Card(spacing: 12) {
            Label(L("workoutDetails"), systemImage: "list.bullet.clipboard").font(AppTypography.cardTitle)
            if let session = loggedSession {
                // Every set, as performed. A summary line was not enough: the
                // point of logging is being able to look up what you lifted.
                ForEach(Array(MuscleTensionEngine.groups(session.sets).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 8) {
                        if group.count > 1 {
                            Label(L("superset"), systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption2.weight(.semibold)).foregroundStyle(AppColors.accent)
                        }
                        ForEach(group, id: \.self) { id in
                            LoggedExercise(exercise: model.exercise(id), fallbackName: id,
                                           sets: session.sets.filter { $0.exerciseID == id })
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(L("workoutDetailsEmpty")).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.startSession(name: L(workout.activity), at: workout.start)
                } label: {
                    Label(L("logExercises"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.activeSession != nil)
            }
        }
    }

    private var sourceCard: some View {
        Card(spacing: 6) {
            Label(L("source"), systemImage: "applewatch").font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(workout.source.isEmpty ? L("unknownSource") : workout.source).font(.subheadline)
            if workout.measuredMinutes > 0, workout.measuredMinutes < workout.minutes * 0.8 {
                // Worth saying: the zone split only covers part of the session.
                Text(L("partialHeartRateCoverage")
                        .replacingOccurrences(of: "{0}", with: duration(workout.measuredMinutes)))
                    .font(.caption2).foregroundStyle(AppColors.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Heart rate through the session, over the zone bands it was counted in.
private struct WorkoutHeartRateChart: View {
    let workout: WorkoutSummary
    @State private var selection: Date?

    private var points: [TimelinePoint] { workout.heartRate ?? [] }
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = min(values.min() ?? 60, workout.restingHeartRate ?? 60)
        let high = max(values.max() ?? 180, 100)
        return (low - 6)...(high + 6)
    }
    private var nearest: TimelinePoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nearest {
                HStack(spacing: 6) {
                    Text(number(nearest.value) + " bpm").font(.caption.weight(.bold)).monospacedDigit()
                    Text(nearest.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart {
                bands
                series
                if let nearest {
                    RuleMark(x: .value("t", nearest.date))
                        .foregroundStyle(AppColors.ink.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(AppColors.border)
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selection)
            .chartPlotStyle { $0.clipped() }
            .frame(height: 170)
        }
    }

    /// The zone bands behind the line, so a peak is read as "zone 4" rather
    /// than as a number.
    @ChartContentBuilder private var bands: some ChartContent {
        if let resting = workout.restingHeartRate, let maximum = workout.maximumHeartRateReference {
            ForEach(0..<6, id: \.self) { zone in
                if let bounds = WorkoutAnalysis.zoneBounds(zone, resting: resting, maximum: maximum) {
                    RectangleMark(yStart: .value("from", bounds.lowerBound),
                                  yEnd: .value("to", bounds.upperBound))
                        .foregroundStyle(WorkoutStyle.zoneColor(zone).opacity(0.13))
                }
            }
        }
    }

    @ChartContentBuilder private var series: some ChartContent {
        ForEach(points) { point in
            LineMark(x: .value("t", point.date), y: .value("bpm", point.value))
                .foregroundStyle(AppColors.metric(.strain))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
    }
}

/// The colour scale under the chart, with the heart rate each zone starts at.
/// A band of colour alone says which zone is which; it does not say what the
/// line has to reach to get there.
private struct ZoneScale: View {
    var resting: Double?
    var maximum: Double?

    private func lowerBound(_ zone: Int) -> Double? {
        guard let resting, let maximum else { return nil }
        return WorkoutAnalysis.zoneBounds(zone, resting: resting, maximum: maximum)?.lowerBound
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { zone in
                    Text("Z\(zone)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WorkoutStyle.zoneColor(zone))
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { zone in
                    Capsule().fill(WorkoutStyle.zoneColor(zone)).frame(height: 6)
                }
            }
            if resting != nil {
                HStack(spacing: 2) {
                    ForEach(0..<6, id: \.self) { zone in
                        Text(lowerBound(zone).map { number($0) } ?? "")
                            .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

enum WorkoutStyle {
    static func symbol(_ activity: String) -> String {
        switch activity {
        case "running": "figure.run"
        case "walking", "hiking": "figure.walk"
        case "cycling": "figure.outdoor.cycle"
        case "swimming": "figure.pool.swim"
        case "strength", "functionalStrength": "dumbbell.fill"
        case "yoga": "figure.yoga"
        case "rowing": "figure.rower"
        case "elliptical": "figure.elliptical"
        case "stairs": "figure.stair.stepper"
        case "hiit": "bolt.heart.fill"
        case "martialArts": "figure.martial.arts"
        case "coreTraining": "figure.core.training"
        default: "figure.mixed.cardio"
        }
    }
    /// Blue for the easy end through to red at the top, which is the
    /// convention every heart-rate display uses.
    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 0: .adaptive(light: 0x8A93A6, dark: 0x9AA3B5)
        case 1: .adaptive(light: 0x2E76C7, dark: 0x6BA6EC)
        case 2: .adaptive(light: 0x0E9C7F, dark: 0x27F6CC)
        case 3: .adaptive(light: 0xB08900, dark: 0xF5D65B)
        case 4: .adaptive(light: 0xBE5411, dark: 0xFF9E52)
        default: .adaptive(light: 0xB3261E, dark: 0xFF6B61)
        }
    }
}

/// The muscle split as a ring with its legend, which is how a training log
/// shows where a session went.
struct MuscleTensionChart: View {
    let shares: [MuscleTensionEngine.Share]

    /// Distinct hues around the wheel, ordered so neighbouring slices never
    /// share a colour. Not the metric palette: these are categories, not
    /// intensities, and reusing the accent would imply a meaning they lack.
    static func colour(_ index: Int) -> Color {
        let palette: [Color] = [
            .adaptive(light: 0x2E76C7, dark: 0x6BA6EC),
            .adaptive(light: 0x0E9C7F, dark: 0x27F6CC),
            .adaptive(light: 0x8A3FB8, dark: 0xC98CF5),
            .adaptive(light: 0xBE5411, dark: 0xFF9E52),
            .adaptive(light: 0xB3261E, dark: 0xFF6B61),
            .adaptive(light: 0x3F55B8, dark: 0x8FA5FF),
            .adaptive(light: 0xB08900, dark: 0xF5D65B),
            .adaptive(light: 0x00838F, dark: 0x4DD0E1),
            .adaptive(light: 0xAD1457, dark: 0xF06292),
            .adaptive(light: 0x5D6D7E, dark: 0x9AA3B5)
        ]
        return palette[index % palette.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Chart(Array(shares.enumerated()), id: \.element.id) { index, share in
                SectorMark(angle: .value("share", share.percent),
                           innerRadius: .ratio(0.62),
                           angularInset: 1)
                    .foregroundStyle(Self.colour(index))
                    .cornerRadius(2)
            }
            .frame(width: 112, height: 112)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(shares.prefix(8).enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 7) {
                        Circle().fill(Self.colour(index)).frame(width: 8, height: 8)
                        Text(L("muscle." + share.muscle)).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(number(share.percent) + "%")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
                if shares.count > 8 {
                    Text("+\(shares.count - 8)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}


/// One exercise of a logged session: its picture, how many sets, and the sets
/// themselves as a small table.
private struct LoggedExercise: View {
    var exercise: ExerciseDefinition?
    var fallbackName: String
    var sets: [StrengthSet]

    private var done: [StrengthSet] { sets.filter(\.completed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let exercise { ExerciseThumbnail(exercise: exercise, size: 38) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? fallbackName).font(.subheadline.weight(.medium)).lineLimit(2)
                    if let exercise {
                        Text(L("muscle." + (exercise.primaryMuscles.first ?? "other")))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                Text("\(done.count) " + L(done.count == 1 ? "setSingular" : "series").lowercased())
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(Array(done.enumerated()), id: \.element.id) { index, set in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.tertiary).frame(width: 20, alignment: .leading)
                        Text(set.weightKg > 0 ? number(set.weightKg, digits: 1) + " kg" : L("equipment.bodyweight"))
                            .font(.caption).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("×\(set.reps)")
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    if set.id != done.last?.id { Divider().overlay(AppColors.divider) }
                }
            }
            .padding(.horizontal, 10)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
