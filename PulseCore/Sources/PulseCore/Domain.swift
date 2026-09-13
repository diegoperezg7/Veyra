import Foundation

public enum Metric: String, CaseIterable, Codable, Sendable, Identifiable {
    case recovery, sleep, strain, stress, energy
    public var id: String { rawValue }
}
public enum Confidence: String, Codable, Sendable { case insufficient, low, medium, high }
public enum DataQuality: String, Codable, Sendable { case excellent, good, partial, poor, insufficient }
public struct Contributor: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var value: Double?
    public var baseline: Double?
    public var score: Double?
    public var weight: Double
    public var unit: String
    public init(_ id: String, value: Double? = nil, baseline: Double? = nil, score: Double?, weight: Double, unit: String = "") {
        self.id = id; self.value = value; self.baseline = baseline; self.score = score; self.weight = weight; self.unit = unit
    }
}
public struct ScoreResult: Codable, Sendable, Equatable {
    public var value: Double?
    public var confidence: Confidence
    public var contributors: [Contributor]
    public var quality: DataQuality
    public var algorithmVersion: Int = 1
    /// Optional so snapshots written by earlier versions still decode.
    /// `LocalStore` deletes records it cannot decode, so a required new field
    /// here would silently destroy the user's history.
    public var report: ConfidenceReport?
    public var missingContributors: [String] { contributors.filter { $0.score == nil }.map(\.id) }
    /// Percentage form of the confidence, for display. Falls back to the middle
    /// of the band when an older snapshot has no report attached.
    public var confidencePercent: Double {
        report?.percent ?? { switch confidence { case .insufficient: 0; case .low: 35; case .medium: 60; case .high: 85 } }()
    }
    public init(value: Double?, confidence: Confidence = .insufficient, contributors: [Contributor] = [], quality: DataQuality = .insufficient, report: ConfidenceReport? = nil) {
        self.value = value.flatMap { $0.isFinite ? $0 : nil }; self.confidence = confidence; self.contributors = contributors; self.quality = quality; self.report = report
    }
    public static let unavailable = ScoreResult(value: nil)
}
/// One 15-minute step of the energy simulation, keeping *why* the level moved.
/// The battery view needs the breakdown, not just the resulting level.
public struct EnergyPoint: Codable, Sendable, Identifiable, Equatable {
    public var date: Date
    public var value: Double
    public var restoration: Double
    public var stressDrain: Double
    public var loadDrain: Double
    public var baselineDrain: Double
    public var asleep: Bool
    public var predicted: Bool
    public var exercise: Bool
    public var id: Date { date }
    public var net: Double { restoration - stressDrain - loadDrain - baselineDrain }
    public init(date: Date, value: Double, restoration: Double = 0, stressDrain: Double = 0, loadDrain: Double = 0, baselineDrain: Double = 0, asleep: Bool = false, predicted: Bool = false, exercise: Bool = false) {
        self.date = date; self.value = value; self.restoration = restoration; self.stressDrain = stressDrain
        self.loadDrain = loadDrain; self.baselineDrain = baselineDrain; self.asleep = asleep; self.predicted = predicted; self.exercise = exercise
    }
    public var timeline: TimelinePoint { .init(date: date, value: value, predicted: predicted, exercise: exercise) }
}
public struct TimelinePoint: Codable, Sendable, Identifiable, Equatable {
    public var date: Date
    public var value: Double
    public var predicted: Bool
    public var exercise: Bool
    public var id: Date { date }
    public init(date: Date, value: Double, predicted: Bool = false, exercise: Bool = false) {
        self.date = date; self.value = value; self.predicted = predicted; self.exercise = exercise
    }
}
public struct Vital: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var value: Double
    public var unit: String
    public var date: Date
    public init(id: String, value: Double, unit: String, date: Date) { self.id = id; self.value = value; self.unit = unit; self.date = date }
}
public enum SleepStage: Int, Codable, Sendable { case inBed = 0, unspecified = 1, awake = 2, core = 3, deep = 4, rem = 5
    public var asleep: Bool { self != .awake && self != .inBed }
}
public struct SleepSegment: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var source: String
    public var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
    public init(id: UUID = UUID(), start: Date, end: Date, stage: SleepStage, source: String = "") {
        self.id = id; self.start = start; self.end = end; self.stage = stage; self.source = source
    }
}
public struct SleepSession: Codable, Sendable, Identifiable, Equatable {
    public var segments: [SleepSegment]
    public var id: Date { start }
    public var start: Date { segments.map(\.start).min() ?? .distantPast }
    public var end: Date { segments.map(\.end).max() ?? .distantPast }
    public var asleepMinutes: Double { segments.filter { $0.stage.asleep }.reduce(0) { $0 + $1.minutes } }
    public var bedMinutes: Double { max(asleepMinutes, end.timeIntervalSince(start) / 60) }
    public init(segments: [SleepSegment]) { self.segments = segments }
}
public struct WorkoutSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var activity: String
    public var calories: Double?
    public var distanceMeters: Double?
    public var source: String
    /// Minutes in zones 1 to 5. Zone 0 — below 50% of heart-rate reserve — is
    /// kept separately so the existing load calculation is unaffected.
    public var zoneMinutes: [Double]
    /// Everything below is optional so a workout recorded by an earlier version
    /// still decodes. `LocalStore` deletes records it cannot read.
    public var belowZoneMinutes: Double?
    /// Heart rate through the session, subsampled to roughly one point a
    /// minute: enough to draw the shape, small enough to store.
    public var heartRate: [TimelinePoint]?
    public var averageHeartRate: Double?
    public var maximumHeartRate: Double?
    /// The drop one minute after the effort ended, from HealthKit's own
    /// measurement when the watch recorded one.
    public var heartRateRecovery: Double?
    /// The references the zones were computed against, so a chart can draw the
    /// same bands the minutes were counted in.
    public var restingHeartRate: Double?
    public var maximumHeartRateReference: Double?

    public var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
    /// Minutes the watch actually attributed to a zone, zone 0 included.
    public var measuredMinutes: Double { zoneMinutes.reduce(0, +) + (belowZoneMinutes ?? 0) }

    public init(id: UUID = UUID(), start: Date, end: Date, activity: String, calories: Double? = nil, distanceMeters: Double? = nil, source: String = "", zoneMinutes: [Double] = [], belowZoneMinutes: Double? = nil, heartRate: [TimelinePoint]? = nil, averageHeartRate: Double? = nil, maximumHeartRate: Double? = nil, heartRateRecovery: Double? = nil, restingHeartRate: Double? = nil, maximumHeartRateReference: Double? = nil) {
        self.id = id; self.start = start; self.end = end; self.activity = activity; self.calories = calories; self.distanceMeters = distanceMeters; self.source = source; self.zoneMinutes = zoneMinutes
        self.belowZoneMinutes = belowZoneMinutes; self.heartRate = heartRate
        self.averageHeartRate = averageHeartRate; self.maximumHeartRate = maximumHeartRate
        self.heartRateRecovery = heartRateRecovery
        self.restingHeartRate = restingHeartRate; self.maximumHeartRateReference = maximumHeartRateReference
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, activity, calories, distanceMeters, source, zoneMinutes
        case belowZoneMinutes, heartRate, averageHeartRate, maximumHeartRate
        case heartRateRecovery, restingHeartRate, maximumHeartRateReference
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        activity = try container.decode(String.self, forKey: .activity)
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) .flatMap { $0 } ?? ""
        zoneMinutes = (try? container.decodeIfPresent([Double].self, forKey: .zoneMinutes)).flatMap { $0 } ?? []
        calories = try? container.decodeIfPresent(Double.self, forKey: .calories)
        distanceMeters = try? container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        belowZoneMinutes = try? container.decodeIfPresent(Double.self, forKey: .belowZoneMinutes)
        heartRate = try? container.decodeIfPresent([TimelinePoint].self, forKey: .heartRate)
        averageHeartRate = try? container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maximumHeartRate = try? container.decodeIfPresent(Double.self, forKey: .maximumHeartRate)
        heartRateRecovery = try? container.decodeIfPresent(Double.self, forKey: .heartRateRecovery)
        restingHeartRate = try? container.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        maximumHeartRateReference = try? container.decodeIfPresent(Double.self, forKey: .maximumHeartRateReference)
    }
}
public struct DailySnapshot: Codable, Sendable, Identifiable, Equatable {
    public var date: Date
    public var updatedAt: Date
    public var scores: [Metric: ScoreResult]
    public var vitals: [Vital]
    public var sleepSessions: [SleepSession]
    public var workouts: [WorkoutSummary]
    public var stress: [TimelinePoint]
    public var energy: [TimelinePoint]
    public var sleepNeed: Double
    public var sleepDebt: Double
    public var rawLoad: Double?
    public var targetStrain: Double?
    /// Optional for backward-compatible decoding of stored snapshots.
    public var energyDetail: [EnergyPoint]?
    public var id: Date { date }
    public init(date: Date, updatedAt: Date = Date(), scores: [Metric: ScoreResult] = [:], vitals: [Vital] = [], sleepSessions: [SleepSession] = [], workouts: [WorkoutSummary] = [], stress: [TimelinePoint] = [], energy: [TimelinePoint] = [], sleepNeed: Double = 480, sleepDebt: Double = 0, rawLoad: Double? = nil, targetStrain: Double? = nil, energyDetail: [EnergyPoint]? = nil) {
        self.date = date; self.updatedAt = updatedAt; self.scores = scores; self.vitals = vitals; self.sleepSessions = sleepSessions; self.workouts = workouts; self.stress = stress; self.energy = energy; self.sleepNeed = sleepNeed; self.sleepDebt = sleepDebt; self.rawLoad = rawLoad; self.targetStrain = targetStrain; self.energyDetail = energyDetail
    }
    public func score(_ metric: Metric) -> ScoreResult { scores[metric] ?? .unavailable }
    public func vital(_ key: String) -> Vital? { vitals.first { $0.id == key } }
}
public struct HealthBatch: Sendable {
    public var vitals: [Vital]
    public var sleep: [SleepSegment]
    public var workouts: [WorkoutSummary]
    /// Types the source could not read on this pass — normally because the
    /// user has not granted them. The import continues without them and says
    /// so, rather than failing outright.
    public var unreadableTypes: [String]
    public init(vitals: [Vital] = [], sleep: [SleepSegment] = [], workouts: [WorkoutSummary] = [], unreadableTypes: [String] = []) {
        self.vitals = vitals; self.sleep = sleep; self.workouts = workouts; self.unreadableTypes = unreadableTypes
    }
}
public protocol HealthDataRepository: Sendable {
    /// `maximumHR` is required because heart-rate zones are personal; deriving
    /// them from a fixed 185 bpm mis-scales every workout for most people.
    func read(from: Date, to: Date, maximumHR: Double) async throws -> HealthBatch
}
/// One exercise in the catalogue. Decoding is explicit and every field has a
/// fallback so a catalogue written by a different version still loads.
public struct ExerciseDefinition: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// The original English name, which is what most gyms print on the machine.
    public var englishName: String = ""
    public var primaryMuscles: [String] = []
    public var secondaryMuscles: [String] = []
    /// Coarse grouping used by the library filters: chest, back, shoulders,
    /// arms, legs, core.
    public var group: String = "other"
    public var equipment: String = "bodyweight"
    public var allEquipment: [String] = []
    public var movementPattern: String = "other"
    public var compound: Bool = false
    public var unilateral: Bool = false
    public var bodyweight: Bool = false
    /// Original instructions from the source dataset, in English.
    public var steps: [String] = []
    /// File names of the two illustration frames, relaxed then contracted.
    public var art: [String] = []

    public init(id: String, name: String) { self.id = id; self.name = name }

    private enum CodingKeys: String, CodingKey {
        case id, name, englishName, primaryMuscles, secondaryMuscles, group, equipment
        case allEquipment, movementPattern, compound, unilateral, bodyweight, steps, art
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
        }
        englishName = value(.englishName, "")
        primaryMuscles = value(.primaryMuscles, [])
        secondaryMuscles = value(.secondaryMuscles, [])
        group = value(.group, "other")
        equipment = value(.equipment, "bodyweight")
        allEquipment = value(.allEquipment, [])
        movementPattern = value(.movementPattern, "other")
        compound = value(.compound, false)
        unilateral = value(.unilateral, false)
        bodyweight = value(.bodyweight, false)
        steps = value(.steps, [])
        art = value(.art, [])
    }
    /// The frame shown when the exercise is listed: the contracted position,
    /// which is the more recognisable of the two.
    public var coverArt: String? { art.count > 1 ? art[1] : art.first }
}
public struct StrengthSet: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var exerciseID: String
    public var reps: Int
    public var weightKg: Double
    public var rpe: Double
    public var kind: String
    public var completed: Bool
    public var superset: String
    /// Seconds rested before this set was performed, measured from when the
    /// previous one was ticked. Optional because sets logged before the timer
    /// existed have none, and because a set entered after the fact has no rest
    /// to measure.
    public var restSeconds: Double?
    public init(exerciseID: String, reps: Int = 10, weightKg: Double = 0, rpe: Double = 7, kind: String = "working", completed: Bool = false, superset: String = "", restSeconds: Double? = nil) {
        self.exerciseID = exerciseID; self.reps = reps; self.weightKg = weightKg; self.rpe = rpe; self.kind = kind; self.completed = completed; self.superset = superset
        self.restSeconds = restSeconds
    }
}
/// A logged strength workout. Kept here rather than in the app so the history
/// engine — which is what makes today's session start from last time's numbers
/// — can be tested without a running app.
public struct StrengthSession: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var start = Date()
    public var end: Date?
    public var name: String
    public var sets: [StrengthSet]
    public var note = ""
    public var healthSaved = false
    public init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil, name: String, sets: [StrengthSet], note: String = "", healthSaved: Bool = false) {
        self.id = id; self.start = start; self.end = end; self.name = name
        self.sets = sets; self.note = note; self.healthSaved = healthSaved
    }
    public var minutes: Double { max(0, (end ?? Date()).timeIntervalSince(start) / 60) }
    /// Exercise ids in the order they were first performed.
    public var exerciseOrder: [String] {
        var seen: [String] = []
        for set in sets where !seen.contains(set.exerciseID) { seen.append(set.exerciseID) }
        return seen
    }
}

public struct WorkoutTemplate: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var sets: [StrengthSet]
    public init(name: String, sets: [StrengthSet]) { self.name = name; self.sets = sets }
}
public struct AlarmConfiguration: Codable, Sendable, Equatable {
    public var enabled = false
    public var hour = 7
    public var minute = 30
    public var windowMinutes = 20
    public var snoozeMinutes = 5
    public init() {}
    public func nextDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
    }
}
public struct WatchEnvelope: Codable, Sendable {
    public var version = 1
    public var operationID: UUID = UUID()
    public var snapshot: DailySnapshot?
    public var templates: [WorkoutTemplate]?
    public var alarm: AlarmConfiguration?
    public var action: String?
    public var amount: Double?
    public var date: Date = Date()
    public init(snapshot: DailySnapshot? = nil, templates: [WorkoutTemplate]? = nil, alarm: AlarmConfiguration? = nil, action: String? = nil, amount: Double? = nil) {
        self.snapshot = snapshot; self.templates = templates; self.alarm = alarm; self.action = action; self.amount = amount
    }
}
