import SwiftUI
import Observation
import UserNotifications
import BackgroundTasks
import PulseCore
@preconcurrency import HealthKit

@Observable @MainActor final class AppModel {
    var preferences = UserPreferences()
    var history: [DailySnapshot] = []
    var entries: [LogEntry] = []
    var templates: [WorkoutTemplate] = []
    var sessions: [StrengthSession] = []
    var documents: [HealthDocument] = []
    var cycleStarts: [Date] = []
    /// Stored so the number is stable between recalibrations instead of being
    /// recomputed — and quietly changing — on every redraw.
    var wellnessAges: [WellnessAgeEstimate] = []
    var selectedDate = Calendar.current.startOfDay(for: Date())
    var syncing = false
    var progress = 0.0
    /// Localization key describing what the sync is doing right now.
    var syncPhase: String?
    /// Free-form counter such as "12/30", shown next to the phase.
    var syncDetail: String?
    /// Set briefly when a sync finishes, so the overlay can confirm before it
    /// disappears rather than just vanishing.
    var syncCompletedAt: Date?
    var errorMessage: String?
    var route: String?
    var tab = "home"
    var exercises: [ExerciseDefinition] = []
    let store: LocalStore
    let health = HealthKitClient()
    let connectivity = Connectivity()
    private var anchors: [String: Data] = [:]
    private var observers: [HKObserverQuery] = []
    private let observerStore = HKHealthStore()
    var today: DailySnapshot { history.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } ?? DailySnapshot(date: selectedDate) }
    var activeSession: StrengthSession? { sessions.last { $0.end == nil } }
    init(store: LocalStore) throws {
        self.store = store
        preferences = try store.load(UserPreferences.self, kind: "preferences").first ?? UserPreferences()
        history = try store.load(DailySnapshot.self, kind: "daily")
        // Migrate existing installations that already had imported HealthKit data.
        if !preferences.healthConnected && !history.isEmpty { preferences.healthConnected = true }
        entries = try store.load(LogEntry.self, kind: "entry")
        templates = try store.load(WorkoutTemplate.self, kind: "template")
        sessions = try store.load(StrengthSession.self, kind: "session")
        documents = try store.load(HealthDocument.self, kind: "document")
        anchors = try store.load([String: Data].self, kind: "anchors").first ?? [:]
        wellnessAges = try store.load(WellnessAgeEstimate.self, kind: "wellnessAge").sorted { $0.date < $1.date }
        if let url = Bundle.main.url(forResource: "exercises", withExtension: "json") { exercises = try JSONDecoder().decode([ExerciseDefinition].self, from: Data(contentsOf: url)) }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting") {
            preferences.onboarded = true
            // Lets the UI suite and manual review open a given screen directly,
            // since a tab bar cannot be driven from the command line.
            if let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) {
                tab = arguments[index + 1]
            }
            if let index = arguments.firstIndex(of: "--route"), arguments.indices.contains(index + 1) {
                route = arguments[index + 1]
            }
            if arguments.contains("--seed") {
                // In-memory store only, so this can never reach a real install.
                history = SampleData.history()
                preferences.birthDate = Calendar.current.date(byAdding: .year, value: -34, to: Date())
                preferences.biologicalSex = "male"
                preferences.healthConnected = true
                recalibrateWellnessAge(force: true)
            }
        }
    }
    func savePreferences() {
        perform { try store.save(preferences, key: "preferences", kind: "preferences") }
        publish()
    }
    func connectHealth() async {
        do {
            try await health.authorize(cycle: preferences.cycle, writing: preferences.writeHealth)
            preferences.healthConnected = true; preferences.onboarded = true
            await importCharacteristics()
            savePreferences()
            await sync(force: history.isEmpty)
            registerObservers()
        } catch { errorMessage = L("healthConnectionError") }
    }
    /// What an import attempt actually did, so the button can say so instead of
    /// appearing to do nothing.
    enum CharacteristicsResult { case updated, alreadyCurrent, unavailable }

    /// Pulls the date of birth and biological sex from Health so the user does
    /// not have to retype what the phone already knows.
    ///
    /// - Parameter overwrite: when false (the automatic path) only empty fields
    ///   are filled, so a value the user typed by hand is never clobbered. When
    ///   true (the explicit button) Health wins, because that is what the user
    ///   just asked for.
    @discardableResult
    func importCharacteristics(overwrite: Bool = false) async -> CharacteristicsResult {
        let characteristics = await health.characteristics()
        guard characteristics.birthDate != nil || characteristics.biologicalSex != nil else { return .unavailable }
        var changed = false
        if let birth = characteristics.birthDate, overwrite || preferences.birthDate == nil {
            if preferences.birthDate != birth { preferences.birthDate = birth; changed = true }
        }
        if let sex = characteristics.biologicalSex, overwrite || preferences.biologicalSex == nil {
            if preferences.biologicalSex != sex { preferences.biologicalSex = sex; changed = true }
        }
        if changed { savePreferences() }
        return changed ? .updated : .alreadyCurrent
    }
    func sync(force: Bool = false, days override: Int? = nil) async {
        guard !syncing else { return }
        syncing = true; progress = 0; syncPhase = "syncDetecting"; syncDetail = nil
        defer { syncing = false; syncPhase = nil; syncDetail = nil }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(override ?? preferences.importDays), to: calendar.startOfDay(for: Date())) ?? Date()
        do {
            let changes = try await health.changes(anchors: force ? [:] : anchors, since: start)
            progress = 0.05
            var from = start
            if !force && !history.isEmpty && !changes.deleted {
                from = changes.affected.min() ?? calendar.startOfDay(for: Date())
                from = max(start, calendar.date(byAdding: .day, value: -1, to: from) ?? from)
            }
            var updated = history.filter { $0.date < from }
            let days = DayBoundary.days(from: from, through: Date())
            var offset = 0
            while offset < days.count {
                try Task.checkCancellation()
                let chunk = Array(days.dropFirst(offset).prefix(30))
                guard let first = chunk.first, let last = chunk.last else { break }
                let readFrom = calendar.date(byAdding: .day, value: -1, to: first) ?? first
                let readTo = calendar.date(byAdding: .day, value: 1, to: last) ?? Date()

                // Reading and calculating are reported separately: reading is
                // the slow part, and a single bar that only moved once every
                // thirty days looked stuck.
                syncPhase = "syncReading"
                syncDetail = "\(min(offset + chunk.count, days.count))/\(days.count)"
                let batch = try await health.read(from: readFrom, to: readTo, maximumHR: preferences.maximumHR)
                let movement = (try? await health.movement(from: readFrom, to: readTo)) ?? [:]
                progress = fraction(offset: offset, chunk: chunk.count, total: days.count, within: 0.6)

                syncPhase = "syncCalculating"
                let prior = updated
                let prefs = preferences
                let strengthByDay = strengthLoadByDay(in: chunk)
                let calculated = await Task.detached(priority: .utility) {
                    var all = prior, new: [DailySnapshot] = []
                    for day in chunk {
                        let context = DailyContext(strengthLoad: strengthByDay[day] ?? 0, movement: movement)
                        let snapshot = DailyEngine.calculate(date: day, batch: batch, history: all, baseSleep: prefs.baseSleep, maximumHR: prefs.maximumHR, preferredSleepSource: prefs.sleepSource.isEmpty ? nil : prefs.sleepSource, status: prefs.status, context: context)
                        all.append(snapshot); new.append(snapshot)
                    }
                    return new
                }.value
                for snapshot in calculated { try store.save(snapshot, key: "daily.\(snapshot.date.timeIntervalSince1970)", kind: "daily", date: snapshot.date) }
                updated.append(contentsOf: calculated)
                history = updated
                offset += chunk.count
                progress = fraction(offset: offset, chunk: 0, total: days.count, within: 0.95)
                // Keep the watch and the widgets moving during a long import
                // instead of leaving them stale until the very end.
                publish()
            }
            syncPhase = "syncFinishing"
            // Advance anchors only after every affected derived record is durably saved.
            try store.save(changes.anchors, key: "anchors", kind: "anchors")
            anchors = changes.anchors
            if preferences.cycle { cycleStarts = try await health.cycleStarts(from: start) }
            preferences.lastSyncAt = Date()
            try store.save(preferences, key: "preferences", kind: "preferences")
            await importCharacteristics()
            recalibrateWellnessAge()
            publish()
            progress = 1
            syncCompletedAt = Date()
        } catch is CancellationError { errorMessage = L("syncCancelled") }
        catch { errorMessage = L("syncError") }
    }
    /// Maps chunk progress into the slice of the bar reserved for the work,
    /// leaving room at both ends for change detection and publication.
    private func fraction(offset: Int, chunk: Int, total: Int, within ceiling: Double) -> Double {
        let done = Double(offset + chunk) / Double(max(1, total))
        return min(ceiling, 0.05 + done * (ceiling - 0.05))
    }
    /// Completed strength sets are recorded in the app, not in HealthKit
    /// quantity samples, so their load has to be handed to the engine.
    private func strengthLoadByDay(in days: [Date]) -> [Date: Double] {
        let calendar = Calendar.current
        let wanted = Set(days)
        var result: [Date: Double] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.start)
            guard wanted.contains(day) else { continue }
            let best = Dictionary(grouping: session.sets.filter(\.completed), by: \.exerciseID)
                .mapValues { sets in sets.compactMap { StrengthEngine.estimated1RM(weight: $0.weightKg, reps: $0.reps) }.max() }
            result[day, default: 0] += session.sets.reduce(0) { $0 + StrengthEngine.load($1, estimated1RM: best[$1.exerciseID] ?? nil) }
        }
        return result
    }
    /// Types whose arrival should refresh the day. Workouts and heart rate are
    /// requested immediately because they change what the user sees right now;
    /// the rest are hourly, which is all HealthKit grants for most types.
    private static let observedTypes: [(HKSampleType, HKUpdateFrequency)] = {
        let quantities: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
            (.heartRate, .immediate), (.heartRateVariabilitySDNN, .hourly), (.restingHeartRate, .hourly),
            (.activeEnergyBurned, .hourly), (.stepCount, .hourly), (.respiratoryRate, .hourly),
            (.oxygenSaturation, .hourly), (.appleSleepingWristTemperature, .hourly)
        ]
        var types: [(HKSampleType, HKUpdateFrequency)] = quantities.compactMap { identifier, frequency in
            HKObjectType.quantityType(forIdentifier: identifier).map { ($0 as HKSampleType, frequency) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append((sleep, .hourly)) }
        types.append((HKObjectType.workoutType(), .immediate))
        return types
    }()
    func registerObservers() {
        guard observers.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        for (type, frequency) in Self.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                // HealthKit's completion handler is not sendable, so it is
                // acknowledged here and the sync runs after. A sync that fails
                // is retried by the next observation or the periodic timer.
                completion()
                Task { @MainActor [weak self] in await self?.sync() }
            }
            observers.append(query); observerStore.execute(query)
            observerStore.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }
    /// Widgets and the watch always describe the current day, never whichever
    /// day happens to be last in a partially synced history.
    var currentSnapshot: DailySnapshot? {
        let today = Calendar.current.startOfDay(for: Date())
        return history.first { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? history.max { $0.date < $1.date }
    }
    func publish() {
        guard let latest = currentSnapshot else {
            connectivity.send(.init(templates: templates, alarm: preferences.alarm)); return
        }
        do { try SharedSnapshotStore.write(latest) } catch { errorMessage = L("widgetSyncError") }
        connectivity.send(.init(snapshot: latest, templates: templates, alarm: preferences.alarm))
    }
    func persist(_ entry: LogEntry) throws {
        try store.save(entry, key: entry.id.uuidString, kind: "entry", date: entry.date)
        entries.removeAll { $0.id == entry.id }; entries.append(entry); entries.sort { $0.date < $1.date }
    }
    func addEntry(_ entry: LogEntry) async {
        do { try persist(entry) } catch { errorMessage = L("saveError") }
    }
    func deleteEntry(_ entry: LogEntry) {
        perform { try store.remove(key: entry.id.uuidString); entries.removeAll { $0.id == entry.id } }
    }
    func saveTemplate(_ template: WorkoutTemplate) { perform { try store.save(template, key: template.id.uuidString, kind: "template"); templates.removeAll { $0.id == template.id }; templates.append(template); publish() } }
    func deleteTemplate(_ template: WorkoutTemplate) { perform { try store.remove(key: template.id.uuidString); templates.removeAll { $0.id == template.id }; publish() } }
    func saveSession(_ session: StrengthSession) { perform { try store.save(session, key: session.id.uuidString, kind: "session", date: session.start); sessions.removeAll { $0.id == session.id }; sessions.append(session) } }
    func startStrength(_ template: WorkoutTemplate) { guard activeSession == nil else { return }; saveSession(.init(name: template.name, sets: template.sets)); route = "activeStrength" }
    func saveDocument(_ document: HealthDocument) { perform { try store.save(document, key: document.id.uuidString, kind: "document"); documents.append(document) } }
    func handleURL(_ url: URL) {
        guard url.scheme == "pulselab", let host = url.host else { return }
        if ["today", "home"].contains(host) { tab = "home" }
        else if ["fitness", "biology", "trends"].contains(host) { tab = host }
        else { route = host }
    }
    func export(csv: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VeyraExport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(csv ? "Veyra.csv" : "Veyra.json")
        if csv {
            let header = "date,recovery,sleep,strain,stress,energy,sleepNeedMinutes,sleepDebtMinutes\n"
            let formatter = ISO8601DateFormatter()
            let rows = history.map { snapshot in ([formatter.string(from: snapshot.date)] + Metric.allCases.map { snapshot.score($0).value.map { String($0) } ?? "" } + [String(snapshot.sleepNeed), String(snapshot.sleepDebt)]).joined(separator: ",") }.joined(separator: "\n")
            try Data((header + rows).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        } else {
            struct Export: Encodable { var version = 2; var history: [DailySnapshot]; var entries: [LogEntry]; var templates: [WorkoutTemplate]; var sessions: [StrengthSession] }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Export(history: history, entries: entries, templates: templates, sessions: sessions)).write(to: url, options: [.atomic, .completeFileProtection])
        }
        return url
    }
    func deleteLocalData() {
        perform {
            try store.deleteAll()
            history = []; entries = []; templates = []; sessions = []; documents = []; anchors = [:]; preferences = UserPreferences()
            let docs = Self.documentsDirectory
            if FileManager.default.fileExists(atPath: docs.path) { try FileManager.default.removeItem(at: docs) }
            if let group = SharedSnapshotStore.directory { let file = group.appendingPathComponent("snapshot.json"); if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }
    static var documentsDirectory: URL { URL.documentsDirectory.appendingPathComponent("HealthDocuments", isDirectory: true) }
    func perform(_ operation: () throws -> Void) { do { try operation() } catch { errorMessage = L("saveError") } }
}

extension AppModel {
    static let refreshTaskID = "local.pulselab.refresh"

    /// Registered once at launch. HealthKit's background delivery covers most
    /// updates, but it does not fire for every type and stops if the app is
    /// never woken, so a scheduled refresh keeps the day current.
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.scheduleBackgroundRefresh()
                let work = Task { await self.sync() }
                task.expirationHandler = { work.cancel() }
                await work.value
                task.setTaskCompleted(success: self.errorMessage == nil)
            }
        }
    }
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(max(15, preferences.autoSyncMinutes)) * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}


extension AppModel {
    /// Days between automatic recalibrations. The estimate is a slow-moving
    /// summary of weeks of data; recomputing it continuously would make it
    /// jitter without meaning anything.
    static let wellnessAgeInterval = 7.0

    var wellnessAge: WellnessAgeEstimate? { wellnessAges.last }

    /// Recomputes only when there is nothing stored, when the stored estimate is
    /// older than a week, or when the user explicitly asks.
    @discardableResult
    func recalibrateWellnessAge(force: Bool = false, now: Date = Date()) -> Bool {
        if !force, let latest = wellnessAge,
           now.timeIntervalSince(latest.date) < Self.wellnessAgeInterval * 86_400 { return false }
        guard let estimate = makeWellnessAge(now: now) else { return false }
        perform {
            try store.save(estimate, key: "wellnessAge.\(Int(estimate.date.timeIntervalSince1970))", kind: "wellnessAge", date: estimate.date)
            wellnessAges.removeAll { Calendar.current.isDate($0.date, inSameDayAs: estimate.date) }
            wellnessAges.append(estimate)
            wellnessAges.sort { $0.date < $1.date }
        }
        return true
    }

    private func makeWellnessAge(now: Date) -> WellnessAgeEstimate? {
        let calendar = Calendar.current
        let days = Array(history.sorted { $0.date < $1.date }.suffix(42))
        let inputs = WellnessAgeInputs(
            chronologicalAge: WellnessAgeEngine.age(from: preferences.birthDate, now: now),
            biologicalSex: preferences.biologicalSex,
            vo2: days.compactMap { $0.vital("vo2")?.value },
            restingHeartRate: days.compactMap { $0.vital("rhr")?.value },
            hrv: days.compactMap { $0.vital("hrv")?.value },
            sleepScores: days.compactMap { $0.score(.sleep).value },
            sleepOnsets: days.compactMap { day in
                day.sleepSessions.max { $0.asleepMinutes < $1.asleepMinutes }.map { session in
                    Double(calendar.component(.hour, from: session.start) * 60 + calendar.component(.minute, from: session.start))
                }
            },
            steps: days.compactMap { $0.vital("steps")?.value },
            exerciseMinutes: days.compactMap { $0.vital("exercise")?.value },
            workoutMinutes: days.map { $0.workouts.reduce(0) { $0 + $1.minutes } },
            stress: days.compactMap { day in Statistics.mean(day.stress.map(\.value)) },
            bmi: days.compactMap { $0.vital("bmi")?.value },
            bodyFat: days.compactMap { $0.vital("bodyFat")?.value }
        )
        return WellnessAgeEngine.calculate(date: now, inputs: inputs)
    }

    /// When the next automatic recalibration is due.
    var nextWellnessAgeDate: Date? {
        wellnessAge.map { $0.date.addingTimeInterval(Self.wellnessAgeInterval * 86_400) }
    }
}
