import Foundation
import PulseCore

/// Synthetic history used only for UI review and the UI test suite, and only
/// when the app is launched with `--uitesting --seed`. It is generated into the
/// in-memory store, so it can never reach a real installation.
///
/// The numbers are plausible rather than random: a weekly rhythm, a slow weight
/// trend, nights with real stage structure and workouts on some days. Random
/// noise would make charts that look busy but tell you nothing about layout.
enum SampleData {
    static func history(days: Int = 90, calendar: Calendar = .current, now: Date = Date()) -> [DailySnapshot] {
        var state = Generator(seed: 20_260_913)
        let today = calendar.startOfDay(for: now)
        var result: [DailySnapshot] = []
        var weight = 78.5, bodyFat = 21.4, previousEvening = 45.0

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            let wave = sin(Double(offset) / 6.0)

            // Slow, monotone-ish body trend with day-to-day scale noise.
            weight -= 0.012 + state.next(-0.18, 0.18)
            bodyFat -= 0.006 + state.next(-0.09, 0.09)
            let height = 1.78
            let bmi = weight / (height * height)
            let leanMass = weight * (1 - bodyFat / 100)

            // Night: bed around 23:30, 6.5–8.5 h, with stage structure.
            let bedtime = calendar.date(byAdding: .minute, value: Int(state.next(-45, 45)) - 30, to: date.addingTimeInterval(-30 * 60)) ?? date
            let asleepMinutes = (isWeekend ? 480.0 : 425.0) + state.next(-55, 55)
            let session = night(from: bedtime, asleepMinutes: asleepMinutes, generator: &state)

            let sleepScore = Statistics.clamp(62 + asleepMinutes / 12 - 20 + wave * 5 + state.next(-6, 6))
            let recovery = Statistics.clamp(sleepScore * 0.55 + 30 + wave * 7 + state.next(-7, 7))
            let workouts = offset % 3 == 1 ? [workout(on: date, generator: &state)] : []
            let strain = Statistics.clamp((workouts.isEmpty ? 26 : 58) + wave * 6 + state.next(-8, 8))

            let vitals: [Vital] = [
                .init(id: "hrv", value: 48 + wave * 9 + state.next(-6, 6), unit: "ms", date: date),
                .init(id: "rhr", value: 52 - wave * 3 + state.next(-3, 3), unit: "bpm", date: date),
                .init(id: "respiratory", value: 14.2 + state.next(-0.8, 0.8), unit: "/min", date: date),
                .init(id: "oxygen", value: 97 + state.next(-1, 1), unit: "%", date: date),
                .init(id: "temperature", value: 36.4 + state.next(-0.2, 0.2), unit: "°C", date: date),
                .init(id: "steps", value: (isWeekend ? 6_500 : 9_800) + state.next(-2_200, 2_200), unit: "steps", date: date),
                .init(id: "activeEnergy", value: 420 + state.next(-140, 220), unit: "kcal", date: date),
                .init(id: "restingEnergy", value: 1_680 + state.next(-40, 40), unit: "kcal", date: date),
                .init(id: "exercise", value: workouts.isEmpty ? 18 : 52, unit: "min", date: date),
                .init(id: "distance", value: (isWeekend ? 4_600 : 7_100) + state.next(-1_500, 1_500), unit: "m", date: date),
                .init(id: "walkingHR", value: 96 + state.next(-5, 5), unit: "bpm", date: date),
                .init(id: "hrRecovery", value: 32 + state.next(-5, 5), unit: "bpm", date: date),
                .init(id: "vo2", value: 46.5 + state.next(-0.6, 0.6), unit: "ml/kg/min", date: date),
                .init(id: "weight", value: weight, unit: "kg", date: date),
                .init(id: "height", value: height, unit: "m", date: date),
                .init(id: "bodyFat", value: bodyFat, unit: "%", date: date),
                .init(id: "leanMass", value: leanMass, unit: "kg", date: date),
                .init(id: "bmi", value: bmi, unit: "BMI", date: date),
                // Screening signals, so the demo history exercises the cards
                // that interpret them. Values sit in the ordinary range: the
                // sample data should not look like a patient.
                .init(id: "breathingDisturbances", value: max(0, 0.9 + state.next(-0.5, 0.9)), unit: "", date: date),
                .init(id: "steadiness", value: 72 + state.next(-3, 3), unit: "%", date: date),
                .init(id: "systolic", value: 118 + state.next(-6, 8), unit: "mmHg", date: date),
                .init(id: "diastolic", value: 76 + state.next(-4, 5), unit: "mmHg", date: date)
            ]

            let stress = stressTimeline(on: date, session: session, workouts: workouts, generator: &state)
            let energy = energyTimeline(date: date, session: session, stress: stress, workouts: workouts,
                                        recovery: recovery, sleep: sleepScore, previousEvening: previousEvening, now: now)
            previousEvening = energy.last?.value ?? previousEvening

            var scores: [Metric: ScoreResult] = [:]
            scores[.sleep] = score(sleepScore, contributors: [
                .init("duration", value: asleepMinutes, score: Statistics.clamp(asleepMinutes / 4.6), weight: 35, unit: "min"),
                .init("efficiency", value: 92, score: 92, weight: 20, unit: "%"),
                .init("continuity", value: 14, score: 88, weight: 15, unit: "min"),
                .init("stages", score: 80, weight: 15),
                .init("consistency", score: 74, weight: 10),
                .init("hrDip", value: 18, score: 90, weight: 5, unit: "%")
            ], observations: days - offset)
            scores[.recovery] = score(recovery, contributors: [
                .init("hrv", value: vitals[0].value, baseline: 48, score: Statistics.clamp(recovery + 4), weight: 30, unit: "ms"),
                .init("rhr", value: vitals[1].value, baseline: 52, score: Statistics.clamp(recovery - 2), weight: 20, unit: "bpm"),
                .init("sleep", value: sleepScore, score: sleepScore, weight: 25),
                .init("respiratory", value: vitals[2].value, baseline: 14.2, score: 84, weight: 10, unit: "/min"),
                .init("temperature", value: vitals[4].value, baseline: 36.4, score: 86, weight: 10, unit: "°C"),
                .init("oxygen", value: vitals[3].value, baseline: 97, score: 88, weight: 5, unit: "%")
            ], observations: days - offset)
            scores[.strain] = score(strain, contributors: [
                .init("zoneLoad", value: workouts.isEmpty ? 0 : 132, score: workouts.isEmpty ? nil : strain, weight: 55, unit: "points"),
                .init("strengthLoad", value: 0, score: nil, weight: 20, unit: "points"),
                .init("nonWorkoutActivity", value: 180, score: strain, weight: 25, unit: "kcal")
            ], observations: days - offset)
            scores[.stress] = score(stress.last?.value ?? 32, contributors: [
                .init("hr", value: 64, score: 40, weight: 55, unit: "bpm"),
                .init("hrv", value: vitals[0].value, score: 44, weight: 35, unit: "ms"),
                .init("movement", value: 0.2, score: 30, weight: 10)
            ], observations: days - offset)
            scores[.energy] = score(energy.last?.value ?? 55, contributors: [
                .init("sleep", value: sleepScore, score: sleepScore, weight: 35),
                .init("recovery", value: recovery, score: recovery, weight: 65)
            ], observations: days - offset)

            result.append(.init(date: date, scores: scores, vitals: vitals, sleepSessions: [session],
                                workouts: workouts, stress: stress, energy: energy.map(\.timeline),
                                sleepNeed: 470, sleepDebt: max(0, 470 - asleepMinutes) * 0.7,
                                rawLoad: workouts.isEmpty ? 30 : 150, targetStrain: 52,
                                energyDetail: energy))
        }
        return result
    }

    private static func score(_ value: Double, contributors: [Contributor], observations: Int) -> ScoreResult {
        let report = ConfidenceEngine.evaluate(contributors: contributors, observations: observations)
        var result = ScoreResult(value: value, confidence: report.level, contributors: contributors, quality: .good, report: report)
        result.algorithmVersion = DailyEngine.algorithmVersion
        return result
    }

    /// A night with the cycle structure a watch actually records: deep early,
    /// REM weighted to the second half, brief awakenings in between.
    private static func night(from bedtime: Date, asleepMinutes: Double, generator: inout Generator) -> SleepSession {
        var segments: [SleepSegment] = []
        var cursor = bedtime
        func add(_ stage: SleepStage, _ minutes: Double) {
            let end = cursor.addingTimeInterval(minutes * 60)
            segments.append(.init(start: cursor, end: end, stage: stage, source: "com.apple.health"))
            cursor = end
        }
        add(.awake, 8)
        let cycles = 5
        let perCycle = asleepMinutes / Double(cycles)
        for index in 0..<cycles {
            let progress = Double(index) / Double(cycles - 1)
            let deep = perCycle * (0.34 - 0.24 * progress)
            let rem = perCycle * (0.10 + 0.28 * progress)
            let core = max(8, perCycle - deep - rem)
            add(.core, core * 0.6)
            add(.deep, deep)
            add(.core, core * 0.4)
            add(.rem, rem)
            if index < cycles - 1 { add(.awake, generator.next(1, 6)) }
        }
        return SleepSession(segments: segments)
    }

    private static func workout(on date: Date, generator: inout Generator) -> WorkoutSummary {
        let start = date.addingTimeInterval(18 * 3600 + generator.next(-3_000, 3_000))
        let minutes = 42 + generator.next(-10, 18)
        return .init(start: start, end: start.addingTimeInterval(minutes * 60),
                     activity: "running", calories: minutes * 11, distanceMeters: minutes * 170,
                     source: "Apple Watch", zoneMinutes: [6, 12, minutes * 0.4, minutes * 0.2, 3])
    }

    private static func stressTimeline(on date: Date, session: SleepSession, workouts: [WorkoutSummary], generator: inout Generator) -> [TimelinePoint] {
        var points: [TimelinePoint] = []
        // Starts with the night, not at waking: activation is measured while
        // asleep too, and it is the calmest part of the day.
        var time = session.start
        let end = date.addingTimeInterval(23 * 3600)
        while time < end {
            let asleep = time >= session.start && time <= session.end
            let hour = Double(Calendar.current.component(.hour, from: time))
            let base = asleep
                ? 9 + generator.next(0, 6)
                : 24 + 22 * max(0, sin((hour - 6) / 16 * .pi))
            let exercising = workouts.contains { $0.start <= time && $0.end >= time }
            if !exercising {
                points.append(.init(date: time, value: Statistics.clamp(base + generator.next(asleep ? -4 : -9, asleep ? 5 : 12))))
            }
            time = time.addingTimeInterval(900)
        }
        return points
    }

    private static func energyTimeline(date: Date, session: SleepSession, stress: [TimelinePoint], workouts: [WorkoutSummary], recovery: Double, sleep: Double, previousEvening: Double, now: Date) -> [EnergyPoint] {
        let morning = EnergyBankEngine.morning(previous: previousEvening, recovery: recovery, sleep: sleep) ?? 70
        let start = session.start
        var current = EnergyBankEngine.nightStart(previousEvening: previousEvening, recovery: recovery, sleep: sleep)
        let rate = EnergyBankEngine.sleepRate(start: current, target: morning, minutes: session.asleepMinutes)
        let limit = min(date.addingTimeInterval(24 * 3600), now)
        guard start < limit else { return [] }

        var points: [EnergyPoint] = [.init(date: start, value: current, asleep: true)]
        var time = start
        while time.addingTimeInterval(900) <= limit {
            let previousTime = time
            time = time.addingTimeInterval(900)
            let asleep = session.segments.filter { $0.stage.asleep }.reduce(0.0) { total, segment in
                total + max(0, min(segment.end, time).timeIntervalSince(max(segment.start, previousTime))) / 60
            }
            let sample = stress.first { abs($0.date.timeIntervalSince(previousTime)) < 450 }
            let active = workouts.filter { $0.start < time && $0.end > previousTime }
            let load = active.isEmpty ? 0 : 9.0
            let step = EnergyBankEngine.step(energy: current, stress: sample?.value, load: load,
                                             resting: sample.map { $0.value < 25 } ?? false,
                                             asleepMinutes: asleep, sleepRate: rate)
            current = step.value
            points.append(.init(date: time, value: current, restoration: step.restoration,
                                stressDrain: step.stressDrain, loadDrain: step.loadDrain,
                                baselineDrain: step.baselineDrain, asleep: step.asleep,
                                predicted: sample == nil && !step.asleep, exercise: !active.isEmpty))
        }
        return points
    }

    /// Deterministic, so two runs produce identical screens and a visual
    /// regression is a real change rather than new noise.
    private struct Generator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(_ lower: Double, _ upper: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(0x20_0000_0000_0000)
            return lower + unit * (upper - lower)
        }
    }
}
