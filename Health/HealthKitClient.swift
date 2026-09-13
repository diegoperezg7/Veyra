@preconcurrency import HealthKit
import Foundation
import PulseCore

struct HealthMetricDefinition: Sendable {
    var key: String
    var identifier: HKQuantityTypeIdentifier
    var unit: String
    var displayUnit: String
    var cumulative: Bool = false
}
enum HealthCatalog {
    static func unit(for definition: HealthMetricDefinition) -> HKUnit {
        switch definition.unit {
        case "%": return .percent()
        case "count/min": return .count().unitDivided(by: .minute())
        case "count": return .count()
        case "ms": return .secondUnit(with: .milli)
        case "degC": return .degreeCelsius()
        case "kcal": return .kilocalorie()
        case "min": return .minute()
        case "m": return .meter()
        case "kg": return .gramUnit(with: .kilo)
        case "mg/dL": return .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case "ml/kg*min": return .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case "mmHg": return .millimeterOfMercury()
        case "W": return .watt()
        case "m/s": return .meter().unitDivided(by: .second())
        case "cm": return .meterUnit(with: .centi)
        case "ml": return .literUnit(with: .milli)
        case "g": return .gram()
        case "mcg": return .gramUnit(with: .micro)
        default: return HKUnit(from: definition.unit)
        }
    }
    static let quantities: [HealthMetricDefinition] = [
        .init(key: "hr", identifier: .heartRate, unit: "count/min", displayUnit: "bpm"),
        .init(key: "rhr", identifier: .restingHeartRate, unit: "count/min", displayUnit: "bpm"),
        .init(key: "hrv", identifier: .heartRateVariabilitySDNN, unit: "ms", displayUnit: "ms"),
        .init(key: "respiratory", identifier: .respiratoryRate, unit: "count/min", displayUnit: "/min"),
        .init(key: "oxygen", identifier: .oxygenSaturation, unit: "%", displayUnit: "%"),
        .init(key: "temperature", identifier: .appleSleepingWristTemperature, unit: "degC", displayUnit: "°C"),
        .init(key: "steps", identifier: .stepCount, unit: "count", displayUnit: "steps", cumulative: true),
        .init(key: "activeEnergy", identifier: .activeEnergyBurned, unit: "kcal", displayUnit: "kcal", cumulative: true),
        .init(key: "restingEnergy", identifier: .basalEnergyBurned, unit: "kcal", displayUnit: "kcal", cumulative: true),
        .init(key: "distance", identifier: .distanceWalkingRunning, unit: "m", displayUnit: "m", cumulative: true),
        .init(key: "exercise", identifier: .appleExerciseTime, unit: "min", displayUnit: "min", cumulative: true),
        .init(key: "stand", identifier: .appleStandTime, unit: "min", displayUnit: "min", cumulative: true),
        .init(key: "flights", identifier: .flightsClimbed, unit: "count", displayUnit: "floors", cumulative: true),
        .init(key: "vo2", identifier: .vo2Max, unit: "ml/kg*min", displayUnit: "ml/kg/min"),
        // Sleep apnoea screening, iOS 18. Reported per night as a unitless
        // count; the elevated threshold comes from Apple, not from us.
        .init(key: "breathingDisturbances", identifier: .appleSleepingBreathingDisturbances, unit: "count", displayUnit: ""),
        // Only produced for people who enabled AFib History after entering a
        // diagnosis, so its absence carries no meaning.
        .init(key: "afibBurden", identifier: .atrialFibrillationBurden, unit: "%", displayUnit: "%"),
        .init(key: "steadiness", identifier: .appleWalkingSteadiness, unit: "%", displayUnit: "%"),
        .init(key: "walkingHR", identifier: .walkingHeartRateAverage, unit: "count/min", displayUnit: "bpm"),
        .init(key: "hrRecovery", identifier: .heartRateRecoveryOneMinute, unit: "count/min", displayUnit: "bpm"),
        .init(key: "weight", identifier: .bodyMass, unit: "kg", displayUnit: "kg"),
        .init(key: "height", identifier: .height, unit: "m", displayUnit: "m"),
        .init(key: "waist", identifier: .waistCircumference, unit: "m", displayUnit: "m"),
        .init(key: "bodyFat", identifier: .bodyFatPercentage, unit: "%", displayUnit: "%"),
        .init(key: "leanMass", identifier: .leanBodyMass, unit: "kg", displayUnit: "kg"),
        .init(key: "bmi", identifier: .bodyMassIndex, unit: "count", displayUnit: "BMI"),
        .init(key: "glucose", identifier: .bloodGlucose, unit: "mg/dL", displayUnit: "mg/dL"),
        .init(key: "systolic", identifier: .bloodPressureSystolic, unit: "mmHg", displayUnit: "mmHg"),
        .init(key: "diastolic", identifier: .bloodPressureDiastolic, unit: "mmHg", displayUnit: "mmHg"),
        .init(key: "runningPower", identifier: .runningPower, unit: "W", displayUnit: "W"),
        .init(key: "runningSpeed", identifier: .runningSpeed, unit: "m/s", displayUnit: "m/s"),
        .init(key: "stride", identifier: .runningStrideLength, unit: "m", displayUnit: "m"),
        .init(key: "verticalOscillation", identifier: .runningVerticalOscillation, unit: "cm", displayUnit: "cm"),
        .init(key: "groundContact", identifier: .runningGroundContactTime, unit: "ms", displayUnit: "ms"),
        .init(key: "cyclingPower", identifier: .cyclingPower, unit: "W", displayUnit: "W"),
        .init(key: "cyclingCadence", identifier: .cyclingCadence, unit: "count/min", displayUnit: "rpm"),
        .init(key: "cyclingSpeed", identifier: .cyclingSpeed, unit: "m/s", displayUnit: "m/s"),
        .init(key: "effort", identifier: .workoutEffortScore, unit: "count", displayUnit: "RPE")
    ]
    /// Category types read alongside the quantities. Irregular rhythm
    /// notifications are events, not measurements, so they have no value to
    /// average — only a date and a count.
    static let categories: [HKCategoryTypeIdentifier] = [.sleepAnalysis, .irregularHeartRhythmEvent]
    static var readTypes: Set<HKObjectType> {
        Set(quantities.compactMap { HKQuantityType.quantityType(forIdentifier: $0.identifier) }
            + [HKObjectType.workoutType() as HKSampleType]
            + categories.compactMap { HKObjectType.categoryType(forIdentifier: $0) as HKSampleType? })
    }
    /// The value at which Apple itself calls sleeping breathing disturbances
    /// elevated. Read from HealthKit so Veyra can never disagree with the
    /// Health app about the same night.
    static var breathingDisturbanceThreshold: Double? {
        HKAppleSleepingBreathingDisturbancesClassification.elevated.minimum.doubleValue(for: .count())
    }
    /// Apple's walking steadiness cut-offs, as percentages.
    static var walkingSteadinessThresholds: (low: Double, veryLow: Double) {
        (HKAppleWalkingSteadinessClassification.low.minimum.doubleValue(for: .percent()) * 100,
         HKAppleWalkingSteadinessClassification.veryLow.minimum.doubleValue(for: .percent()) * 100)
    }
}
struct HealthChanges: Sendable { var anchors: [String: Data]; var affected: Set<Date>; var deleted: Bool }
enum HealthServiceError: Error { case unavailable, unsupported, writeNotAuthorized }
actor HealthKitClient: HealthDataRepository {
    let store = HKHealthStore()
    func authorize(cycle: Bool = false, writing: Bool = false) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthServiceError.unavailable }
        var read = HealthCatalog.readTypes
        // Characteristics are separate object types and must be requested too,
        // or the profile and the wellness age have no age to work from.
        for identifier in [HKCharacteristicTypeIdentifier.dateOfBirth, .biologicalSex] {
            if let type = HKObjectType.characteristicType(forIdentifier: identifier) { read.insert(type) }
        }
        if cycle, let flow = HKObjectType.categoryType(forIdentifier: .menstrualFlow) { read.insert(flow) }
        let write: Set<HKSampleType> = writing ? [HKObjectType.workoutType() as HKSampleType] : []
        try await store.requestAuthorization(toShare: write, read: read)
    }
    /// Characteristics Apple actually exposes. There is no HealthKit API for
    /// the user's name, so a profile screen cannot read one — weight and height
    /// come through as ordinary samples instead.
    func characteristics() -> (birthDate: Date?, biologicalSex: String?) {
        guard HKHealthStore.isHealthDataAvailable() else { return (nil, nil) }
        let birth = (try? store.dateOfBirthComponents())?.date
        let sex: String?
        switch try? store.biologicalSex().biologicalSex {
        case .female: sex = "female"
        case .male: sex = "male"
        case .other: sex = "other"
        default: sex = nil
        }
        return (birth, sex)
    }
    func read(from: Date, to: Date, maximumHR: Double) async throws -> HealthBatch {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        // The types are independent of each other, so reading them concurrently
        // turns a long serial walk over ~35 queries into a handful of rounds.
        var vitals: [Vital] = try await withThrowingTaskGroup(of: [Vital].self) { group in
            for definition in HealthCatalog.quantities {
                guard let type = HKObjectType.quantityType(forIdentifier: definition.identifier) else { continue }
                group.addTask { [self] in
                    let unit = HealthCatalog.unit(for: definition)
                    if definition.cumulative {
                        let daily = try await cumulative(type: type, unit: unit, from: from, to: to)
                        return daily.map { .init(id: definition.key, value: $0.1, unit: definition.displayUnit, date: $0.0) }
                    }
                    // Built here rather than captured: NSPredicate is not
                    // Sendable and cannot cross into a concurrent task.
                    return try await samples(type, from: from, to: to).compactMap { sample -> Vital? in
                        guard let sample = sample as? HKQuantitySample, sample.quantity.is(compatibleWith: unit) else { return nil }
                        let raw = sample.quantity.doubleValue(for: unit)
                        let value = definition.unit == "%" ? raw * 100 : raw
                        guard value.isFinite else { return nil }
                        return .init(id: definition.key, value: value, unit: definition.displayUnit, date: sample.startDate)
                    }
                }
            }
            var all: [Vital] = []
            for try await chunk in group { all += chunk }
            return all
        }
        var sleep: [SleepSegment] = []
        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            sleep = try await samples(type, predicate: predicate).compactMap { sample in
                guard let sample = sample as? HKCategorySample, let stage = SleepStage(rawValue: sample.value) else { return nil }
                return .init(id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage, source: sample.sourceRevision.source.bundleIdentifier)
            }
        }
        // Irregular rhythm notifications arrive as events. Recorded as a vital
        // of value 1 so they land on the timeline with everything else.
        if let type = HKObjectType.categoryType(forIdentifier: .irregularHeartRhythmEvent) {
            let events = try await samples(type, predicate: predicate)
            vitals += events.map { .init(id: "irregularRhythm", value: 1, unit: "", date: $0.startDate) }
        }
        let heartRates = vitals.filter { $0.id == "hr" }.sorted { $0.date < $1.date }
        // Resting heart rate drifts over weeks, so a single median across the
        // whole imported window mis-scales the zones of older workouts. Index
        // the daily samples and fall back to the window median only when the
        // workout's own day has none.
        let restingByDay = Dictionary(vitals.filter { $0.id == "rhr" }.map { (Calendar.current.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { _, b in b })
        let restingFallback = Statistics.median(vitals.filter { $0.id == "rhr" }.map(\.value))
        let maximum = Statistics.clamp(maximumHR, 100, 240)
        let workouts = try await samples(HKObjectType.workoutType(), predicate: predicate).compactMap { sample -> WorkoutSummary? in
            guard let workout = sample as? HKWorkout else { return nil }
            var zones = [Double](repeating: 0, count: 5)
            let points = heartRates.filter { $0.date >= workout.startDate && $0.date <= workout.endDate }
            let resting = restingByDay[Calendar.current.startOfDay(for: workout.startDate)] ?? restingFallback
            for (point, next) in zip(points, points.dropFirst()) {
                let interval = next.date.timeIntervalSince(point.date)
                guard interval > 0, interval <= 120, let resting,
                      let zone = HeartRateZoneEngine.zone(heartRate: point.value, resting: resting, maximum: maximum), zone > 0 else { continue }
                zones[zone - 1] += interval / 60
            }
            let calories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned).flatMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie()) }
            return .init(id: workout.uuid, start: workout.startDate, end: workout.endDate, activity: Self.activityName(workout.workoutActivityType), calories: calories, distanceMeters: workout.totalDistance?.doubleValue(for: .meter()), source: workout.sourceRevision.source.name, zoneMinutes: zones)
        }
        return .init(vitals: vitals.sorted { $0.date < $1.date }, sleep: sleep, workouts: workouts)
    }
    private func samples(_ type: HKSampleType, from: Date, to: Date) async throws -> [HKSample] {
        try await samples(type, predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: []))
    }
    private func samples(_ type: HKSampleType, predicate: NSPredicate?) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: results ?? []) }
            }
            store.execute(query)
        }
    }
    /// Step counts bucketed into the same 15-minute grid the stress timeline
    /// uses, normalised to 0–1. Without this the stress engine received a
    /// constant zero for movement, which made its movement component collapse
    /// into a duplicate of the heart-rate component.
    func movement(from: Date, to: Date) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [:] }
        let buckets = try await cumulative(type: type, unit: .count(), from: from, to: to, components: DateComponents(minute: 15))
        // 250 steps in a quarter of an hour is a steady walk; anything at or
        // beyond that counts as fully explained by movement.
        return Dictionary(buckets.map { ($0.0, Statistics.clamp($0.1 / 250, 0, 1)) }, uniquingKeysWith: { _, b in b })
    }
    private func cumulative(type: HKQuantityType, unit: HKUnit, from: Date, to: Date, components: DateComponents = DateComponents(day: 1)) async throws -> [(Date, Double)] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to), options: .cumulativeSum, anchorDate: calendar.startOfDay(for: from), intervalComponents: components)
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [(Date, Double)] = []
                collection?.enumerateStatistics(from: from, to: to) { statistics, _ in
                    if let sum = statistics.sumQuantity() { values.append((statistics.startDate, sum.doubleValue(for: unit))) }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    func changes(anchors: [String: Data], since: Date) async throws -> HealthChanges {
        var result = HealthChanges(anchors: anchors, affected: [], deleted: false)
        for type in HealthCatalog.readTypes.compactMap({ $0 as? HKSampleType }).sorted(by: { $0.identifier < $1.identifier }) {
            let anchor = try anchors[type.identifier].flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
            var cursor = anchor
            var more = true
            while more {
                let page = try await anchored(type: type, anchor: cursor, since: since)
                for dates in page.dates { result.affected.insert(Calendar.current.startOfDay(for: dates.0)); result.affected.insert(Calendar.current.startOfDay(for: dates.1)) }
                result.deleted = result.deleted || page.deleted
                cursor = page.anchor
                more = page.count == 1000
            }
            if let cursor { result.anchors[type.identifier] = try NSKeyedArchiver.archivedData(withRootObject: cursor, requiringSecureCoding: true) }
        }
        return result
    }
    private func anchored(type: HKSampleType, anchor: HKQueryAnchor?, since: Date) async throws -> (dates: [(Date, Date)], anchor: HKQueryAnchor?, deleted: Bool, count: Int) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil), anchor: anchor, limit: 1000) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ((samples ?? []).map { ($0.startDate, $0.endDate) }, next, !(deleted ?? []).isEmpty, (samples?.count ?? 0) + (deleted?.count ?? 0))) }
            }
            store.execute(query)
        }
    }
    func cycleStarts(from: Date) async throws -> [Date] {
        guard let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return [] }
        let all = try await samples(type, predicate: HKQuery.predicateForSamples(withStart: from, end: Date()))
        let days = Set(all.compactMap { sample -> Date? in guard let s = sample as? HKCategorySample, s.value > 1 else { return nil }; return Calendar.current.startOfDay(for: s.startDate) }).sorted()
        return days.enumerated().compactMap { index, day in index == 0 || day.timeIntervalSince(days[index - 1]) > 3 * 86400 ? day : nil }
    }
    nonisolated static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type { case .running: "running"; case .walking: "walking"; case .hiking: "hiking"; case .cycling: "cycling"; case .traditionalStrengthTraining: "strength"; case .functionalStrengthTraining: "functionalStrength"; case .highIntensityIntervalTraining: "hiit"; case .yoga: "yoga"; case .rowing: "rowing"; case .elliptical: "elliptical"; case .stairClimbing: "stairs"; case .swimming: "swimming"; case .martialArts: "martialArts"; case .coreTraining: "coreTraining"; default: "workout" }
    }
}
