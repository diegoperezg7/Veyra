import Foundation

/// Everything the estimate is allowed to look at. Built by the caller from
/// stored history so the engine stays a pure function over plain numbers.
public struct WellnessAgeInputs: Sendable {
    public var chronologicalAge: Double?
    public var biologicalSex: String?
    /// mL/kg/min, from Apple Watch or another source that writes VO2max.
    public var vo2: [Double]
    public var restingHeartRate: [Double]
    /// SDNN in milliseconds.
    public var hrv: [Double]
    /// Daily sleep scores, 0–100.
    public var sleepScores: [Double]
    /// Minutes of the main sleep onset each night, for regularity.
    public var sleepOnsets: [Double]
    public var steps: [Double]
    /// Apple exercise minutes per day.
    public var exerciseMinutes: [Double]
    /// Minutes of recorded workouts per day.
    public var workoutMinutes: [Double]
    /// Daily mean physiological activation, 0–100.
    public var stress: [Double]
    public var bmi: [Double]
    public var bodyFat: [Double]

    public init(chronologicalAge: Double? = nil, biologicalSex: String? = nil, vo2: [Double] = [], restingHeartRate: [Double] = [], hrv: [Double] = [], sleepScores: [Double] = [], sleepOnsets: [Double] = [], steps: [Double] = [], exerciseMinutes: [Double] = [], workoutMinutes: [Double] = [], stress: [Double] = [], bmi: [Double] = [], bodyFat: [Double] = []) {
        self.chronologicalAge = chronologicalAge; self.biologicalSex = biologicalSex
        self.vo2 = vo2; self.restingHeartRate = restingHeartRate; self.hrv = hrv
        self.sleepScores = sleepScores; self.sleepOnsets = sleepOnsets; self.steps = steps
        self.exerciseMinutes = exerciseMinutes; self.workoutMinutes = workoutMinutes
        self.stress = stress; self.bmi = bmi; self.bodyFat = bodyFat
    }
}

/// One signal's contribution, in years, with the observation behind it.
public struct AgeFactor: Sendable, Equatable, Identifiable {
    public var id: String { key }
    /// Localisation key: "vo2", "rhr", "hrv", "sleep", "activity"…
    public var key: String
    public var value: Double
    public var unit: String
    /// Years added (positive) or subtracted (negative) before weighting.
    public var years: Double
    public var weight: Double
    /// What this signal would be for someone of the user's chronological age.
    public var expected: Double?
    public init(key: String, value: Double, unit: String, years: Double, weight: Double, expected: Double? = nil) {
        self.key = key; self.value = value; self.unit = unit
        self.years = years; self.weight = weight; self.expected = expected
    }
}

public struct WellnessAgeEstimate: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var age: Double
    public var chronologicalAge: Double
    public var margin: Double
    public var report: ConfidenceReport
    public var contributors: [Contributor]
    /// Cardiorespiratory fitness expressed as an age, when VO2max is available.
    /// This is the anchor of the estimate and is worth showing on its own.
    public var fitnessAge: Double?
    public var id: Date { date }
    public var confidence: Confidence { report.level }
    public var range: ClosedRange<Double> { (age - margin)...(age + margin) }
    public var delta: Double { age - chronologicalAge }

    public init(date: Date = Date(), age: Double, chronologicalAge: Double, margin: Double, report: ConfidenceReport, contributors: [Contributor], fitnessAge: Double? = nil) {
        self.date = date; self.age = age; self.chronologicalAge = chronologicalAge
        self.margin = margin; self.report = report; self.contributors = contributors
        self.fitnessAge = fitnessAge
    }
}

/// A transparent, wearable-only estimate. It is **not** a biological age in the
/// clinical sense: the published methods for that (Klemera–Doubal, PhenoAge)
/// require blood chemistry — albumin, creatinine, glucose, CRP, lymphocyte
/// percentage, MCV, RDW, alkaline phosphatase, white cell count — and a watch
/// measures none of them.
///
/// What a watch *can* anchor is cardiorespiratory fitness. VO2max has published
/// normative curves by age and sex (ACSM guidelines, Cooper Institute / FRIEND
/// registry), and inverting that curve gives a defensible "your fitness matches
/// the median N-year-old". Everything else is a bounded correction on top.
///
/// References are recorded in Documentation/ALGORITHMS.md.
public enum WellnessAgeEngine {
    /// Observations at which the estimate is considered fully calibrated.
    public static let target = 42.0
    /// The whole estimate never departs from chronological age by more than
    /// this, however extreme the inputs.
    public static let maximumDeviation = 15.0

    // MARK: - VO2max reference curve

    /// Median VO2max, in mL/kg/min, for a healthy adult of this age and sex.
    /// Linear fits to the ACSM "average" bands, whose decade midpoints run
    /// 39→24.5 for men and 33→21.5 for women between ages 25 and 75.
    public static func expectedVO2(age: Double, sex: String?) -> Double? {
        guard age.isFinite else { return nil }
        switch sex {
        case "male": return 39.0 - 0.29 * (age - 25)
        case "female": return 33.0 - 0.23 * (age - 25)
        default: return nil
        }
    }
    /// Youngest age the reference curve can express. The published bands stop
    /// in the twenties, so a very fit person saturates here rather than being
    /// given an implausible teenage figure.
    public static let fitnessAgeFloor = 20.0

    /// The age whose median VO2max equals this measurement — the inverse of the
    /// curve above. This is the single most defensible number here.
    public static func fitnessAge(vo2: Double, sex: String?) -> Double? {
        guard vo2.isFinite, vo2 > 0 else { return nil }
        let slope: Double
        let intercept: Double
        switch sex {
        case "male": slope = 0.29; intercept = 39.0
        case "female": slope = 0.23; intercept = 33.0
        default: return nil
        }
        return Statistics.clamp(25 + (intercept - vo2) / slope, fitnessAgeFloor, 100)
    }
    /// True when the measurement is better than the curve can express, so the
    /// screen can say "20 or under" instead of asserting exactly 20.
    public static func fitnessAgeSaturates(vo2: Double, sex: String?) -> Bool {
        guard let raw = rawFitnessAge(vo2: vo2, sex: sex) else { return false }
        return raw < fitnessAgeFloor
    }
    private static func rawFitnessAge(vo2: Double, sex: String?) -> Double? {
        guard vo2.isFinite, vo2 > 0 else { return nil }
        switch sex {
        case "male": return 25 + (39.0 - vo2) / 0.29
        case "female": return 25 + (33.0 - vo2) / 0.23
        default: return nil
        }
    }

    // MARK: - Estimate

    public static func calculate(date: Date = Date(), inputs: WellnessAgeInputs) -> WellnessAgeEstimate? {
        guard let chronologicalAge = inputs.chronologicalAge,
              chronologicalAge.isFinite, (18...100).contains(chronologicalAge) else { return nil }

        var factors: [AgeFactor] = []
        var missing: [Contributor] = []

        // 1. Cardiorespiratory fitness. The anchor: weight 35, and the only
        //    factor allowed to move the estimate by more than a few years.
        var anchor: Double?
        if let vo2 = Statistics.mean(finite(inputs.vo2)) {
            let expected = expectedVO2(age: chronologicalAge, sex: inputs.biologicalSex)
            if let fitness = fitnessAge(vo2: vo2, sex: inputs.biologicalSex) {
                anchor = fitness
                factors.append(.init(key: "vo2", value: vo2, unit: "ml/kg/min",
                                     years: Statistics.clamp(fitness - chronologicalAge, -15, 15),
                                     weight: 35, expected: expected))
            } else {
                // Without a declared sex there is no curve to invert; the value
                // is still shown, but it cannot be turned into years.
                missing.append(.init("vo2", value: vo2, score: nil, weight: 35, unit: "ml/kg/min"))
            }
        } else {
            missing.append(.init("vo2", score: nil, weight: 35, unit: "ml/kg/min"))
        }

        // 2. Resting heart rate. Higher resting rates track with worse
        //    cardiovascular outcomes; 60 bpm is the reference.
        add(&factors, &missing, key: "rhr", values: inputs.restingHeartRate, unit: "bpm", weight: 15, expected: 60) { rhr in
            Statistics.clamp((rhr - 60) / 10 * 2.5, -5, 5)
        }

        // 3. Heart-rate variability. SDNN falls with age; the reference curve
        //    below is a coarse fit to wrist-measured SDNN, not a clinical norm.
        let expectedHRV = Statistics.clamp(60 - 0.45 * (chronologicalAge - 20), 18, 70)
        add(&factors, &missing, key: "hrv", values: inputs.hrv, unit: "ms", weight: 10, expected: expectedHRV) { hrv in
            Statistics.clamp((expectedHRV - hrv) / max(1, expectedHRV) * 10, -5, 5)
        }

        // 4. Sleep quality, plus the regularity of when sleep starts — timing
        //    is part of sleep health, not only duration.
        add(&factors, &missing, key: "sleep", values: inputs.sleepScores, unit: "%", weight: 10, expected: 75) { score in
            Statistics.clamp((75 - score) / 12, -3, 3)
        }
        if let deviation = Statistics.circularDeviation(finite(inputs.sleepOnsets)), deviation.isFinite {
            factors.append(.init(key: "sleepRegularity", value: deviation, unit: "min",
                                 years: Statistics.clamp((deviation - 45) / 40, -1.5, 2.5),
                                 weight: 5, expected: 45))
        } else {
            missing.append(.init("sleepRegularity", score: nil, weight: 5, unit: "min"))
        }

        // 5. Movement volume. 7 500 steps a day is where the mortality curve
        //    has largely flattened in accelerometer cohorts.
        add(&factors, &missing, key: "activity", values: inputs.steps, unit: "steps", weight: 8, expected: 7_500) { steps in
            Statistics.clamp((7_500 - steps) / 2_500, -3, 3)
        }

        // 6. Deliberate training, which step counts miss entirely: a cyclist or
        //    a lifter can take very few steps and still train hard. The WHO
        //    guideline of 150 weekly minutes is the reference.
        let weeklyTraining = weeklyMinutes(exercise: inputs.exerciseMinutes, workouts: inputs.workoutMinutes)
        if let weeklyTraining {
            factors.append(.init(key: "training", value: weeklyTraining, unit: "min/week",
                                 years: Statistics.clamp((150 - weeklyTraining) / 75, -3, 3),
                                 weight: 12, expected: 150))
        } else {
            missing.append(.init("training", score: nil, weight: 12, unit: "min/week"))
        }

        // 7. Sustained physiological activation. Chronic stress load is an
        //    independent risk factor; 35 is the engine's neutral activation.
        add(&factors, &missing, key: "stress", values: inputs.stress, unit: "%", weight: 5, expected: 35) { stress in
            Statistics.clamp((stress - 35) / 15, -2, 3)
        }

        // 8. Body composition. Body fat is preferred where the scale reports
        //    it, because BMI cannot tell muscle from fat. Only ever a penalty:
        //    being nearer the reference is not evidence of being younger.
        if let fat = Statistics.mean(finite(inputs.bodyFat)), let reference = referenceBodyFat(sex: inputs.biologicalSex) {
            factors.append(.init(key: "bodyFat", value: fat, unit: "%",
                                 years: Statistics.clamp((fat - reference) / 6, 0, 3),
                                 weight: 5, expected: reference))
        } else if let bmi = Statistics.mean(finite(inputs.bmi)) {
            factors.append(.init(key: "bmi", value: bmi, unit: "",
                                 years: Statistics.clamp(abs(bmi - 22) / 4, 0, 3),
                                 weight: 5, expected: 22))
        } else {
            missing.append(.init("bodyFat", score: nil, weight: 5, unit: "%"))
        }

        guard !factors.isEmpty else { return nil }

        // Weighted mean over the signals that exist. Dividing by the full
        // weight instead would silently treat a missing signal as neutral.
        let presentWeight = factors.reduce(0) { $0 + $1.weight }
        let totalWeight = presentWeight + missing.reduce(0) { $0 + $1.weight }
        let adjustment = Statistics.clamp(
            factors.reduce(0) { $0 + $1.years * $1.weight } / max(1, presentWeight),
            -maximumDeviation, maximumDeviation)

        let observations = [inputs.sleepScores, inputs.steps, inputs.restingHeartRate].map { finite($0).count }.max() ?? 0
        var report = ConfidenceEngine.evaluate(
            contributors: contributors(factors: factors, missing: missing, totalWeight: totalWeight),
            observations: observations, target: target)
        // Without VO2max the anchor is gone and the rest are corrections with
        // nothing to correct, so the estimate is materially weaker.
        if anchor == nil {
            report.percent = Statistics.clamp(report.percent * 0.6)
            report.limitations.append("confidenceNoFitnessAnchor")
        }

        // The correction is trusted in proportion to the confidence, so a
        // first-week estimate stays close to the chronological age.
        let trusted = adjustment * Statistics.clamp(report.percent / 100, 0, 1)
        let margin = Statistics.clamp(1.5 + 8 * (1 - report.percent / 100), 1.5, 10)

        return .init(date: date,
                     age: Statistics.clamp(chronologicalAge + trusted, 18, 100),
                     chronologicalAge: chronologicalAge,
                     margin: margin,
                     report: report,
                     contributors: contributors(factors: factors, missing: missing, totalWeight: totalWeight),
                     fitnessAge: anchor)
    }

    /// Chronological age in years from a birth date, or nil when absent or absurd.
    public static func age(from birthDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let birthDate, birthDate < now else { return nil }
        let days = calendar.dateComponents([.day], from: birthDate, to: now).day ?? 0
        let years = Double(days) / 365.2425
        return (18...100).contains(years) ? years : nil
    }

    // MARK: - Helpers

    /// Reference body fat: the midpoint of the ACE "fitness" band.
    private static func referenceBodyFat(sex: String?) -> Double? {
        switch sex { case "male": 16; case "female": 23; default: nil }
    }

    /// Weekly training minutes, taking whichever source reports more. Apple
    /// exercise minutes and recorded workouts overlap, so summing them would
    /// double-count the same session.
    private static func weeklyMinutes(exercise: [Double], workouts: [Double]) -> Double? {
        let daily = zip(exercise + Array(repeating: 0, count: max(0, workouts.count - exercise.count)),
                        workouts + Array(repeating: 0, count: max(0, exercise.count - workouts.count)))
            .map { max($0, $1) }
        let finiteDaily = finite(daily.isEmpty ? exercise.isEmpty ? workouts : exercise : daily)
        guard !finiteDaily.isEmpty, let mean = Statistics.mean(finiteDaily) else { return nil }
        return mean * 7
    }

    private static func add(_ factors: inout [AgeFactor], _ missing: inout [Contributor],
                            key: String, values: [Double], unit: String, weight: Double,
                            expected: Double, years: (Double) -> Double) {
        guard let mean = Statistics.mean(finite(values)) else {
            missing.append(.init(key, score: nil, weight: weight, unit: unit)); return
        }
        factors.append(.init(key: key, value: mean, unit: unit, years: years(mean), weight: weight, expected: expected))
    }

    /// Factors and gaps as a single contributor list, which is what the
    /// confidence engine and the UI both consume.
    private static func contributors(factors: [AgeFactor], missing: [Contributor], totalWeight: Double) -> [Contributor] {
        factors.map { factor in
            Contributor(factor.key, value: factor.value, baseline: factor.expected,
                        score: 50 - factor.years * 5, weight: factor.weight, unit: factor.unit)
        } + missing
    }

    private static func finite(_ values: [Double]) -> [Double] { values.filter { $0.isFinite } }
}
