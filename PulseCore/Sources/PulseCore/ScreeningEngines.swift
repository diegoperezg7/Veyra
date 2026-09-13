import Foundation

/// Readings the watch already records but the app was not interpreting. Each
/// engine here turns a raw number into the band its own literature defines, so
/// the app can say *what the number means* instead of only showing it.
///
/// Where Apple publishes the thresholds itself — breathing disturbances and
/// walking steadiness — the engine takes them as parameters and the iOS layer
/// supplies Apple's own ranges. Inventing numbers for those would produce a
/// classification that disagrees with the Health app on the same sample.

// MARK: - Bands

/// A named band with the range that produced it, so the UI can draw the scale
/// and not just the label. `key` is a localisation key, never display text.
public struct ReferenceBand: Sendable, Equatable, Identifiable {
    public var key: String
    public var lower: Double?
    public var upper: Double?
    public var severity: Int
    public var id: String { key }
    public init(key: String, lower: Double? = nil, upper: Double? = nil, severity: Int = 0) {
        self.key = key; self.lower = lower; self.upper = upper; self.severity = severity
    }
    public func contains(_ value: Double) -> Bool {
        (lower.map { value >= $0 } ?? true) && (upper.map { value < $0 } ?? true)
    }
}

// MARK: - Wrist temperature

/// Nightly wrist temperature is only meaningful as a deviation from your own
/// baseline: the absolute figure depends on the watch, the wrist and the room.
/// Apple builds its baseline over roughly five nights; this uses the same
/// minimum and reports the deviation in degrees Celsius.
///
/// The bands are derived, not published. No clinical threshold exists for
/// consumer wrist temperature, so they are expressed against the spread of the
/// wearer's own nights and phrased as "worth noticing", never as a diagnosis.
public enum TemperatureDeviationEngine {
    public static let minimumNights = 5

    public struct Result: Sendable, Equatable {
        public var deviation: Double
        public var baseline: Double
        public var nights: Int
        public var band: String
        public var unusual: Bool
    }

    public static func calculate(nightly: [Double], latest: Double? = nil) -> Result? {
        let values = nightly.filter(\.isFinite)
        guard let current = latest ?? values.last else { return nil }
        let history = latest == nil ? values.dropLast().map { $0 } : values
        guard history.count >= minimumNights, let baseline = BaselineEngine.calculate(history) else { return nil }
        let deviation = current - baseline.median
        let magnitude = abs(deviation)
        // A third of a degree is within ordinary night-to-night variation for
        // most wearers; a full degree is not, and coincides with how Apple
        // surfaces the reading in Cycle Tracking.
        let band: String
        if magnitude < 0.3 { band = "temperatureTypical" }
        else if magnitude < 0.7 { band = "temperatureSlight" }
        else if magnitude < 1.2 { band = "temperatureNotable" }
        else { band = "temperatureMarked" }
        return .init(deviation: deviation, baseline: baseline.median, nights: history.count,
                     band: band, unusual: magnitude >= 0.7)
    }
}

// MARK: - Sleeping breathing disturbances

/// Apple's sleep apnoea screening feature. The watch reports a nightly figure
/// and classifies it as not elevated or elevated; `elevatedFrom` must come from
/// `HKAppleSleepingBreathingDisturbancesClassification` so Veyra never
/// contradicts the Health app.
///
/// Apple's own guidance is that elevated readings across a month are the signal
/// worth acting on, not a single night, which is what `monthly` reports.
public enum BreathingDisturbanceEngine {
    public static let minimumNights = 10

    public static func classify(_ value: Double, elevatedFrom threshold: Double) -> String? {
        guard value.isFinite, threshold.isFinite else { return nil }
        return value >= threshold ? "breathingElevated" : "breathingNotElevated"
    }

    public struct Monthly: Sendable, Equatable {
        public var elevatedNights: Int
        public var nights: Int
        public var fraction: Double
        /// Apple notifies when elevated readings persist across a month. Below
        /// that, the reading is reported without a prompt to act on it.
        public var persistent: Bool
    }

    public static func monthly(nightly: [Double], elevatedFrom threshold: Double) -> Monthly? {
        let values = nightly.filter(\.isFinite)
        guard values.count >= minimumNights, threshold.isFinite else { return nil }
        let elevated = values.filter { $0 >= threshold }.count
        let fraction = Double(elevated) / Double(values.count)
        return .init(elevatedNights: elevated, nights: values.count, fraction: fraction, persistent: fraction >= 0.5)
    }
}

// MARK: - Chronotype

/// Mid-sleep point, the midpoint between falling asleep and waking, is the
/// standard marker of chronotype in the Munich ChronoType Questionnaire
/// (Roenneberg et al.). The cut-offs below are Roenneberg's, collapsed from
/// seven categories to five.
///
/// This is the uncorrected mid-sleep: MSFsc additionally subtracts half the
/// sleep debt accumulated on work days, which needs a reliable work/free-day
/// split the app does not have. It is therefore a chronotype *estimate*, and
/// late risers who are sleep-deprived on weekdays will read slightly late.
public enum ChronotypeEngine {
    public static let minimumNights = 7

    public struct Result: Sendable, Equatable {
        /// Minutes after midnight, 0–1440.
        public var midSleep: Double
        public var band: String
        public var nights: Int
        public var spreadMinutes: Double?
    }

    public static func calculate(sessions: [SleepSession], calendar: Calendar = .current) -> Result? {
        let midpoints: [Double] = sessions.compactMap { session in
            let asleep = session.segments.filter { $0.stage.asleep }
            guard let start = asleep.map(\.start).min(), let end = asleep.map(\.end).max(), end > start else { return nil }
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let components = calendar.dateComponents([.hour, .minute], from: middle)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        guard midpoints.count >= minimumNights else { return nil }
        // Mid-sleep is a time of day, so it has to be averaged on the circle:
        // 23:50 and 00:10 average to midnight, not to noon.
        let radians = midpoints.map { $0 / 1440 * 2 * Double.pi }
        let x = radians.reduce(0) { $0 + cos($1) } / Double(radians.count)
        let y = radians.reduce(0) { $0 + sin($1) } / Double(radians.count)
        guard x != 0 || y != 0 else { return nil }
        var mid = atan2(y, x) / (2 * Double.pi) * 1440
        if mid < 0 { mid += 1440 }
        let band: String
        switch mid {
        case ..<(2 * 60 + 17): band = "chronotypeEarly"
        case ..<(3 * 60 + 14): band = "chronotypeModeratelyEarly"
        case ..<(5 * 60 + 8): band = "chronotypeIntermediate"
        case ..<(7 * 60 + 2): band = "chronotypeModeratelyLate"
        default: band = "chronotypeLate"
        }
        return .init(midSleep: mid, band: band, nights: midpoints.count,
                     spreadMinutes: Statistics.circularDeviation(midpoints))
    }
}

// MARK: - Atrial fibrillation

/// AFib burden is the share of time the watch estimated the wearer was in
/// atrial fibrillation. It is only produced for people who have entered a
/// diagnosis and enabled the feature, so its absence means nothing.
///
/// The bands follow KP-RHYTHM (Go et al., JAMA Cardiology 2018), where the
/// highest tertile of burden — at or above roughly 11% — carried the raised
/// stroke risk. Apple's own display floor is 2%.
public enum AtrialFibrillationEngine {
    public static let bands: [ReferenceBand] = [
        .init(key: "afibMinimal", lower: 0, upper: 2, severity: 0),
        .init(key: "afibLow", lower: 2, upper: 11.4, severity: 1),
        .init(key: "afibHigh", lower: 11.4, upper: nil, severity: 2)
    ]
    public static func band(_ burden: Double) -> ReferenceBand? {
        guard burden.isFinite, burden >= 0 else { return nil }
        return bands.first { $0.contains(burden) } ?? bands.last
    }
    /// Weekly average burden, which is the form the feature is meant to be read
    /// in; a single day is noisy.
    public static func weekly(_ daily: [Double]) -> Double? { Statistics.mean(daily.filter(\.isFinite)) }
}

// MARK: - Walking steadiness

/// Apple's gait stability estimate, derived from iPhone motion during walking.
/// The thresholds are Apple's and are passed in from
/// `HKAppleWalkingSteadinessClassification` rather than hard-coded, so the
/// classification always matches the Health app.
public enum WalkingSteadinessEngine {
    public static func classify(_ value: Double, lowFrom low: Double, veryLowFrom veryLow: Double) -> String? {
        guard value.isFinite, low.isFinite, veryLow.isFinite else { return nil }
        if value < veryLow { return "steadinessVeryLow" }
        if value < low { return "steadinessLow" }
        return "steadinessOK"
    }
    /// The trend matters more than one reading: a steady decline is the thing
    /// the feature exists to catch. Returns percentage points per 30 days.
    public static func trend(_ points: [TimelinePoint]) -> Double? {
        guard points.count >= 8 else { return nil }
        return TrendEngine.projection(points, days: 30).map { $0 - (points.last?.value ?? 0) }
    }
}

// MARK: - Blood pressure

/// ACC/AHA 2017 categories. Europe's ESC/ESH 2023 guideline draws the line for
/// hypertension at 140/90 rather than 130/80 and calls 130–139/85–89 "high
/// normal"; both are reported so the reading is not tied to one continent.
public enum BloodPressureEngine {
    public struct Reading: Sendable, Equatable {
        public var systolic: Double
        public var diastolic: Double
        /// ACC/AHA 2017 category key.
        public var band: String
        /// ESC/ESH 2023 category key.
        public var europeanBand: String
        public var severity: Int
        /// Systolic at or above 180, or diastolic at or above 120: the reading
        /// that both guidelines say needs prompt medical attention.
        public var crisis: Bool
    }

    public static func classify(systolic: Double, diastolic: Double) -> Reading? {
        guard systolic.isFinite, diastolic.isFinite, systolic > 40, diastolic > 20, systolic > diastolic else { return nil }
        let band: String
        let severity: Int
        // Categories are assigned on the higher of the two readings.
        if systolic >= 180 || diastolic >= 120 { band = "bpCrisis"; severity = 4 }
        else if systolic >= 140 || diastolic >= 90 { band = "bpStage2"; severity = 3 }
        else if systolic >= 130 || diastolic >= 80 { band = "bpStage1"; severity = 2 }
        else if systolic >= 120 { band = "bpElevated"; severity = 1 }
        else { band = "bpNormal"; severity = 0 }
        let european: String
        if systolic >= 180 || diastolic >= 110 { european = "bpEuropeanGrade3" }
        else if systolic >= 160 || diastolic >= 100 { european = "bpEuropeanGrade2" }
        else if systolic >= 140 || diastolic >= 90 { european = "bpEuropeanGrade1" }
        else if systolic >= 130 || diastolic >= 85 { european = "bpEuropeanHighNormal" }
        else if systolic >= 120 || diastolic >= 80 { european = "bpEuropeanNormal" }
        else { european = "bpEuropeanOptimal" }
        return .init(systolic: systolic, diastolic: diastolic, band: band, europeanBand: european,
                     severity: severity, crisis: systolic >= 180 || diastolic >= 120)
    }

    /// Both guidelines classify on an average of readings taken on separate
    /// occasions, never on one cuff inflation.
    public static let minimumReadings = 3
    public static func average(systolic: [Double], diastolic: [Double]) -> Reading? {
        guard systolic.count >= minimumReadings, diastolic.count >= minimumReadings,
              let s = Statistics.median(systolic), let d = Statistics.median(diastolic) else { return nil }
        return classify(systolic: s, diastolic: d)
    }
}

// MARK: - VO2max percentile

/// Where a measurement sits among healthy adults of the same age and sex.
///
/// The median comes from the same ACSM reference curve the wellness age uses,
/// so the two can never disagree. The spread around it is a normal
/// approximation to the FRIEND registry distribution rather than a lookup of
/// its published percentile table — this is a derived figure, and a percentile
/// within a few points either way is the most that should be read into it.
public enum VO2MaxNorms {
    /// Standard deviation of VO2max within an age and sex group, mL/kg/min.
    public static func deviation(sex: String?) -> Double? {
        switch sex { case "male": 7.0; case "female": 6.0; default: nil }
    }

    public static func percentile(vo2: Double, age: Double, sex: String?) -> Double? {
        guard vo2.isFinite, vo2 > 0,
              let median = WellnessAgeEngine.expectedVO2(age: age, sex: sex),
              let deviation = deviation(sex: sex), deviation > 0 else { return nil }
        let z = (vo2 - median) / deviation
        return Statistics.clamp(normalCDF(z) * 100, 1, 99)
    }

    /// ACSM fitness categories, which are defined by percentile.
    public static func band(percentile: Double) -> String {
        switch percentile {
        case ..<20: "vo2Poor"
        case ..<40: "vo2Fair"
        case ..<60: "vo2Average"
        case ..<80: "vo2Good"
        default: "vo2Excellent"
        }
    }

    static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }
}

// MARK: - Weekly activity against the WHO guideline

/// WHO 2020 guidelines for adults: 150–300 minutes of moderate-intensity
/// aerobic activity a week, or 75–150 vigorous, or an equivalent combination —
/// and vigorous minutes count double in that combination.
///
/// Intensity is read from heart-rate reserve, following ACSM: 40–59% of reserve
/// is moderate and 60% or more is vigorous. Veyra's zone 1 starts at 50% of
/// reserve, so zone 1 is counted as moderate and zones 2 and above as vigorous.
/// Activity below zone 1 is not counted, which means the estimate is
/// conservative: brisk walking that never reaches 50% of reserve is missed.
public enum WeeklyActivityEngine {
    public static let moderateTarget = 150.0
    public static let upperTarget = 300.0

    public struct Result: Sendable, Equatable {
        public var moderateMinutes: Double
        public var vigorousMinutes: Double
        /// Moderate-equivalent minutes: moderate + 2 × vigorous.
        public var equivalentMinutes: Double
        public var percentOfGuideline: Double
        public var meetsGuideline: Bool
        /// The upper end of the recommended range, beyond which the guideline
        /// reports no further mortality benefit.
        public var exceedsUpperRange: Bool
        public var band: String
    }

    public static func calculate(workouts: [WorkoutSummary], from: Date, to: Date) -> Result {
        let window = workouts.filter { $0.start >= from && $0.start < to }
        let moderate = window.reduce(0) { $0 + ($1.zoneMinutes.first ?? 0) }
        let vigorous = window.reduce(0) { $0 + $1.zoneMinutes.dropFirst().prefix(4).reduce(0, +) }
        let equivalent = moderate + vigorous * 2
        let percent = equivalent / moderateTarget * 100
        let band: String
        switch percent {
        case ..<34: band = "activityInactive"
        case ..<67: band = "activityInsufficient"
        case ..<100: band = "activityApproaching"
        case ..<200: band = "activityMeets"
        default: band = "activityExceeds"
        }
        return .init(moderateMinutes: moderate, vigorousMinutes: vigorous, equivalentMinutes: equivalent,
                     percentOfGuideline: Statistics.clamp(percent, 0, 999),
                     meetsGuideline: equivalent >= moderateTarget,
                     exceedsUpperRange: equivalent > upperTarget, band: band)
    }
}
