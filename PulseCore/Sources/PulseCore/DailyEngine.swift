import Foundation

/// Extra per-day inputs the engine cannot derive from HealthKit samples alone.
public struct DailyContext: Sendable {
    /// Completed strength sets recorded in the app, keyed by nothing: the
    /// caller filters them to the day. Muscular work is invisible to heart rate
    /// zones, so without this a heavy lifting session produced no strain.
    public var strengthLoad: Double
    /// Fifteen-minute movement intensity, 0–1, used to tell an elevated heart
    /// rate caused by activity from one caused by physiological activation.
    public var movement: [Date: Double]
    public init(strengthLoad: Double = 0, movement: [Date: Double] = [:]) {
        self.strengthLoad = strengthLoad; self.movement = movement
    }
}

public enum DailyEngine {
    /// Bumped whenever the stored numbers change meaning, so Diagnostics can
    /// offer a recalculation and old snapshots stay identifiable.
    public static let algorithmVersion = 3

    public static func calculate(date: Date, batch: HealthBatch, history: [DailySnapshot], baseSleep: Double = 480, maximumHR: Double = 185, preferredSleepSource: String? = nil, status: String = "active", context: DailyContext = .init(), calendar: Calendar = .current, now: Date = Date()) -> DailySnapshot {
        let history = history.filter { $0.date < date }.sorted { $0.date < $1.date }
        let end = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        let dayVitals = batch.vitals.filter { $0.date >= date && $0.date < end }
        let sessions = SleepEngine.sessions(batch.sleep, preferredSource: preferredSleepSource).filter { $0.end >= date && $0.end < end }
        let main = sessions.max { $0.asleepMinutes < $1.asleepMinutes }
        let previous = history.last
        let need = SleepEngine.need(base: baseSleep, debt: previous?.sleepDebt ?? 0, previousStrain: previous?.score(.strain).value ?? 0)
        let stageHistory = history.compactMap { $0.sleepSessions.max { $0.asleepMinutes < $1.asleepMinutes } }.map { session in session.segments.filter { $0.stage == .deep || $0.stage == .rem }.reduce(0) { $0 + $1.minutes } / max(1, session.asleepMinutes) }
        let onsetHistory = history.suffix(14).compactMap { $0.sleepSessions.max { $0.asleepMinutes < $1.asleepMinutes } }.map { Double(calendar.component(.hour, from: $0.start) * 60 + calendar.component(.minute, from: $0.start)) }

        // Heart-rate dip needs samples from inside the night and from the
        // waking hours that frame it, so it is computed before scoring sleep.
        let hrDip: Double? = main.flatMap { session in
            let nightly = batch.vitals.filter { $0.id == "hr" && $0.date >= session.start && $0.date <= session.end }.map(\.value)
            let waking = batch.vitals.filter { $0.id == "hr" && ($0.date < session.start || $0.date > session.end) }.map(\.value)
            return SleepEngine.heartRateDip(nightly: nightly, waking: waking)
        }
        let sleep = SleepEngine.score(main, need: need, stageHistory: stageHistory, onsetHistory: onsetHistory, hrDip: hrDip)

        var summaryVitals: [Vital] = []
        let latestMeasurementKeys: Set<String> = ["weight", "height", "bodyFat", "leanMass", "bmi", "waist", "glucose", "systolic", "diastolic"]
        for key in Set(dayVitals.map(\.id)).sorted() where key != "hr" {
            let points = dayVitals.filter { $0.id == key }
            if latestMeasurementKeys.contains(key), let last = points.last {
                // A scale or cuff measurement is discrete. The latest recorded
                // value is the truthful daily state; a median can combine
                // unrelated weigh-ins and hide a real reading.
                summaryVitals.append(last)
            } else if let last = points.last, let value = Statistics.median(points.map(\.value)) {
                summaryVitals.append(.init(id: key, value: value, unit: last.unit, date: last.date))
            }
        }
        // Night measurements belong to the wake date, including samples before midnight.
        if let main {
            for key in ["hrv", "respiratory", "temperature", "oxygen"] {
                let overnight = batch.vitals.filter { $0.id == key && $0.date >= main.start && $0.date <= main.end }
                if let value = Statistics.median(overnight.map(\.value)), let last = overnight.last {
                    summaryVitals.removeAll { $0.id == key }; summaryVitals.append(.init(id: key, value: value, unit: last.unit, date: last.date))
                }
            }
        }
        let values = Dictionary(summaryVitals.map { ($0.id, $0.value) }, uniquingKeysWith: { _, b in b })
        let histories = Dictionary(uniqueKeysWithValues: RecoveryEngine.weights.keys.map { key in (key, history.suffix(42).compactMap { $0.vital(key)?.value }) })
        let newestVital = summaryVitals.map(\.date).max()
        let dataAge = newestVital.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 0
        let recovery = RecoveryEngine.calculate(values: values, histories: histories, sleep: sleep, dataAgeInDays: dataAge)

        let workouts = StrainEngine.deduplicate(batch.workouts.filter { $0.start >= date && $0.start < end })
        let cardio = workouts.reduce(0) { $0 + HeartRateZoneEngine.load(zoneMinutes: $1.zoneMinutes) }
        let strength = max(0, context.strengthLoad.isFinite ? context.strengthLoad : 0)
        let hasActivity = values["steps"] != nil || values["activeEnergy"] != nil || !workouts.isEmpty || strength > 0
        let passiveCalories = max(0, (values["activeEnergy"] ?? 0) - workouts.reduce(0) { $0 + ($1.calories ?? 0) })
        let raw = cardio + passiveCalories * 0.06 + strength
        let strain = hasActivity ? StrainEngine.score(rawLoad: raw, history: history.compactMap(\.rawLoad)) : nil
        let target = StrainEngine.target(history: history.compactMap { $0.score(.strain).value }, recovery: recovery.value, status: status)

        let dayHeartRates = dayVitals.filter { $0.id == "hr" }.map(\.value).filter(\.isFinite)
        let restingHistory = history.suffix(42).compactMap { $0.vital("rhr")?.value }.filter(\.isFinite)
        let todayResting = dayVitals.filter { $0.id == "rhr" }.map(\.value).filter(\.isFinite)
        var hrBaseline = BaselineEngine.calculate(restingHistory + todayResting)
        // RHR is often exported as one daily sample. When there is not yet a
        // three-day RHR history, derive a provisional reference from the lower
        // tenth percentile of today's actual heart-rate samples. This avoids
        // inventing a population default while still making the metric useful
        // from the first watch day onward.
        if hrBaseline?.count ?? 0 < 3, dayHeartRates.count >= 3,
           let lowReference = Statistics.percentile(dayHeartRates, 0.10) {
            let mad = Statistics.median(dayHeartRates.map { abs($0 - lowReference) }) ?? 0
            hrBaseline = Baseline(median: lowReference, mad: max(1, mad), count: dayHeartRates.count)
        }
        let todayHRV = dayVitals.filter { $0.id == "hrv" }.map(\.value).filter(\.isFinite)
        let hrvBaseline = BaselineEngine.calculate((histories["hrv"] ?? []) + todayHRV)

        let hr = dayVitals.filter { $0.id == "hr" }
        let grouped = Dictionary(grouping: hr) { Int($0.date.timeIntervalSince(date) / 900) }
        var stress: [TimelinePoint] = []
        for bin in grouped.keys.sorted() {
            // HealthKit heart-rate samples are not guaranteed to arrive twice
            // inside every 15-minute bucket. One valid observation is enough
            // to calculate a low-confidence point against the personal
            // baseline; dropping it made the stress timeline appear empty.
            guard let points = grouped[bin], !points.isEmpty else { continue }
            let time = date.addingTimeInterval(Double(bin) * 900)
            let exercise = workouts.contains { $0.start < time.addingTimeInterval(900) && $0.end > time }
            let nearbyHRV = dayVitals.last { $0.id == "hrv" && abs($0.date.timeIntervalSince(time)) <= 1800 }
            let movement = context.movement[time] ?? 0
            if let value = StressEngine.calculate(hr: Statistics.median(points.map(\.value)), hrBaseline: hrBaseline, hrv: nearbyHRV?.value, hrvBaseline: hrvBaseline, movement: movement, workout: exercise) { stress.append(.init(date: time, value: value)) }
        }

        let detail = energyTimeline(date: date, end: end, now: now, main: main, sessions: sessions,
                                    workouts: workouts, stress: stress, previous: previous,
                                    recovery: recovery.value, sleep: sleep.value)
        let energy = detail.map(\.timeline)

        var energyScore = ScoreResult(value: energy.last?.value, confidence: .insufficient, quality: energy.isEmpty ? .insufficient : .partial)
        energyScore.algorithmVersion = algorithmVersion
        energyScore.contributors = [
            .init("sleep", value: sleep.value, score: sleep.value, weight: recovery.value == nil ? 100 : 35),
            .init("recovery", value: recovery.value, score: recovery.value, weight: 65)
        ]
        let measuredShare = detail.isEmpty ? 0 : Double(detail.filter { !$0.predicted }.count) / Double(detail.count)
        var energyReport = ConfidenceEngine.evaluate(contributors: energyScore.contributors, observations: history.count, ageInDays: dataAge)
        // The battery is a simulation: intervals without an observed stress
        // sample are extrapolated, and that uncertainty belongs in the number.
        energyReport.percent = Statistics.clamp(energyReport.percent * (0.5 + 0.5 * measuredShare))
        if measuredShare < 0.999 { energyReport.limitations.append("confidencePredictedIntervals") }
        energyScore.report = energyReport
        energyScore.confidence = energy.isEmpty ? .insufficient : energyReport.level

        var strainScore = ScoreResult(value: strain, confidence: .insufficient, quality: hasActivity ? .partial : .insufficient)
        strainScore.algorithmVersion = algorithmVersion
        strainScore.contributors = [
            .init("zoneLoad", value: cardio, score: cardio > 0 ? strain : nil, weight: 55, unit: "points"),
            .init("strengthLoad", value: strength, score: strength > 0 ? strain : nil, weight: 20, unit: "points"),
            .init("nonWorkoutActivity", value: passiveCalories, score: values["activeEnergy"] != nil ? strain : nil, weight: 25, unit: "kcal")
        ]
        let strainReport = ConfidenceEngine.evaluate(contributors: strainScore.contributors, observations: history.compactMap(\.rawLoad).count, ageInDays: dataAge)
        strainScore.report = strainReport
        strainScore.confidence = hasActivity ? strainReport.level : .insufficient

        var stressScore = ScoreResult(value: stress.last?.value, confidence: .insufficient, quality: stress.isEmpty ? .insufficient : .partial)
        stressScore.algorithmVersion = algorithmVersion
        stressScore.contributors = [
            .init("hr", value: stress.last?.value, score: stress.last?.value, weight: 55, unit: "bpm"),
            .init("hrv", value: values["hrv"], score: values["hrv"] != nil ? stress.last?.value : nil, weight: 35, unit: "ms"),
            .init("movement", value: nil, score: context.movement.isEmpty ? nil : 0, weight: 10)
        ]
        let stressReport = ConfidenceEngine.evaluate(contributors: stressScore.contributors, observations: hrBaseline?.count ?? 0, target: 14, ageInDays: dataAge)
        stressScore.report = stressReport
        stressScore.confidence = stress.isEmpty ? .insufficient : stressReport.level

        var sleepScore = sleep
        sleepScore.algorithmVersion = algorithmVersion
        var recoveryScore = recovery
        recoveryScore.algorithmVersion = algorithmVersion

        let scores: [Metric: ScoreResult] = [.recovery: recoveryScore, .sleep: sleepScore, .strain: strainScore, .stress: stressScore, .energy: energyScore]
        let debt = sessions.isEmpty ? previous?.sleepDebt ?? 0 : SleepEngine.debt(previous: previous?.sleepDebt ?? 0, need: need, restorative: sessions.reduce(0) { $0 + $1.asleepMinutes })
        return .init(date: date, scores: scores, vitals: summaryVitals, sleepSessions: sessions, workouts: workouts, stress: stress, energy: energy, sleepNeed: need, sleepDebt: debt, rawLoad: hasActivity ? raw : nil, targetStrain: target.map { ($0.lowerBound + $0.upperBound) / 2 }, energyDetail: detail)
    }

    /// Simulates the day's energy in 15-minute steps. Unlike version 2 this
    /// starts at the beginning of the night, so the overnight recharge is
    /// visible, and it keeps running on days with no scored sleep by carrying
    /// the previous evening's level forward.
    private static func energyTimeline(date: Date, end: Date, now: Date, main: SleepSession?, sessions: [SleepSession], workouts: [WorkoutSummary], stress: [TimelinePoint], previous: DailySnapshot?, recovery: Double?, sleep: Double?) -> [EnergyPoint] {
        let previousEvening = previous?.energyDetail?.last?.value ?? previous?.energy.last?.value
        guard let morning = EnergyBankEngine.morning(previous: previousEvening, recovery: recovery, sleep: sleep) else { return [] }
        let limit = min(end, now)

        // Start at the night's onset when the night belongs to this day and has
        // already finished; otherwise start the waking simulation at midnight.
        let start: Date
        var current: Double
        var sleepRate = 0.0
        if let main, main.end <= now, main.end < end {
            start = max(main.start, date.addingTimeInterval(-6 * 3600))
            current = EnergyBankEngine.nightStart(previousEvening: previousEvening, recovery: recovery, sleep: sleep)
            sleepRate = EnergyBankEngine.sleepRate(start: current, target: morning, minutes: main.asleepMinutes)
        } else {
            start = date
            current = morning
        }
        guard start < limit else { return [] }

        let asleepSegments = sessions.flatMap(\.segments).filter { $0.stage.asleep }
        let napSegments = sessions.filter { $0.id != main?.id }.flatMap(\.segments).filter { $0.stage.asleep }

        var points: [EnergyPoint] = [.init(date: start, value: current, asleep: main.map { start >= $0.start && start < $0.end } ?? false)]
        var time = start
        while time.addingTimeInterval(900) <= limit {
            let previousTime = time
            time = time.addingTimeInterval(900)
            let sample = stress.first { abs($0.date.timeIntervalSince(previousTime)) < 450 }
            let active = workouts.filter { $0.start < time && $0.end > previousTime }
            let load = active.reduce(0.0) { total, workout in
                let overlap = max(0, min(workout.end, time).timeIntervalSince(max(workout.start, previousTime))) / 60
                return total + HeartRateZoneEngine.load(zoneMinutes: workout.zoneMinutes) * overlap / max(1, workout.minutes)
            }
            func minutes(in segments: [SleepSegment]) -> Double {
                segments.reduce(0.0) { total, segment in
                    total + max(0, min(segment.end, time).timeIntervalSince(max(segment.start, previousTime))) / 60
                }
            }
            let asleep = minutes(in: asleepSegments)
            let nap = minutes(in: napSegments)
            let step = EnergyBankEngine.step(energy: current, stress: sample?.value, load: load,
                                             resting: sample.map { $0.value < 25 } ?? false,
                                             napMinutes: nap, asleepMinutes: asleep, sleepRate: sleepRate)
            current = step.value
            points.append(.init(date: time, value: current, restoration: step.restoration, stressDrain: step.stressDrain,
                                loadDrain: step.loadDrain, baselineDrain: step.baselineDrain, asleep: step.asleep,
                                predicted: sample == nil && !step.asleep, exercise: !active.isEmpty))
        }
        return points
    }
}
