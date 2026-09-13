import Foundation
import SwiftData
import PulseCore

enum PulseSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoredRecord.self] }
    @Model final class StoredRecord {
        @Attribute(.unique) var key: String
        var kind: String
        var date: Date
        var payload: Data
        init(key: String, kind: String, date: Date, payload: Data) { self.key = key; self.kind = kind; self.date = date; self.payload = payload }
    }
}
enum PulseMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PulseSchema.self] }
    static var stages: [MigrationStage] { [] }
}
typealias StoredRecord = PulseSchema.StoredRecord
@MainActor final class LocalStore {
    let container: ModelContainer
    let context: ModelContext
    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: PulseSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        // A previous interrupted install can leave SQLite's -wal/-shm sidecars
        // behind and make SwiftData refuse to open the store. Keep a recoverable
        // copy and recreate the container instead of showing a dead-end screen.
        do {
            container = try ModelContainer(for: schema, migrationPlan: PulseMigration.self, configurations: [configuration])
        } catch {
            guard !inMemory else { throw error }
            let fileManager = FileManager.default
            let storeURL = configuration.url
            let parent = storeURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let backup = parent.appendingPathComponent("VeyraStore-recovery-\(UUID().uuidString)")
            try? fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            for candidate in [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm")] {
                if fileManager.fileExists(atPath: candidate.path) {
                    try? fileManager.moveItem(at: candidate, to: backup.appendingPathComponent(candidate.lastPathComponent))
                }
            }
            container = try ModelContainer(for: schema, migrationPlan: PulseMigration.self, configurations: [configuration])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        if !inMemory {
            #if os(iOS) || os(watchOS)
            let directory = configuration.url.deletingLastPathComponent()
            // Protection is best-effort: simulator filesystems and devices that
            // are locked can reject this attribute even though SwiftData works.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            #endif
        }
    }
    func save<T: Encodable>(_ value: T, key: String, kind: String, date: Date = Date()) throws {
        let payload = try JSONEncoder().encode(value)
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.key == key }); descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first { record.payload = payload; record.date = date }
        else { context.insert(StoredRecord(key: key, kind: kind, date: date, payload: payload)) }
        try context.save()
    }
    func load<T: Decodable>(_ type: T.Type, kind: String) throws -> [T] {
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kind == kind }, sortBy: [SortDescriptor(\.date)])
        let records = try context.fetch(descriptor)
        let decoder = JSONDecoder()
        var values: [T] = []
        var removedCorruptRecord = false

        // A single interrupted write must not make the whole app unusable.
        // Keep every valid record and remove only the payload that cannot be
        // decoded anymore. The user can then continue with the rest of their
        // local history instead of seeing the storage recovery screen.
        for record in records {
            do {
                values.append(try decoder.decode(T.self, from: record.payload))
            } catch {
                context.delete(record)
                removedCorruptRecord = true
            }
        }

        if removedCorruptRecord {
            try? context.save()
        }
        return values
    }
    func remove(key: String) throws {
        try context.delete(model: StoredRecord.self, where: #Predicate { $0.key == key }); try context.save()
    }
    func remove(kind: String) throws {
        try context.delete(model: StoredRecord.self, where: #Predicate { $0.kind == kind }); try context.save()
    }
    func deleteAll() throws { try context.delete(model: StoredRecord.self); try context.save() }
}
struct LogEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date = Date()
    var kind: String
    var title: String
    var note = ""
    var tags: [String: Bool] = [:]
}
struct HealthDocument: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date = Date()
    var name: String
    var fileName: String
    var text: String
    var biomarkers: [Biomarker] = []
}
struct Biomarker: Codable, Identifiable, Equatable, Sendable { var id = UUID(); var name: String; var value: Double; var unit: String; var date = Date() }
// StrengthSession now lives in PulseCore, next to the engine that reads it.
// The stored shape is unchanged, so existing records still decode.
/// Every property carries a default and decoding is explicit, so adding or
/// removing a preference never makes a stored record undecodable. `LocalStore`
/// deletes records it cannot decode, and losing preferences that way would
/// silently reset the user's whole configuration.
struct UserPreferences: Codable, Sendable {
    var onboarded = false
    var baseSleep = 480.0
    var importDays = 365
    var autoSyncMinutes = 15
    var lastSyncAt: Date?
    var healthConnected = false
    var maximumHR = 185.0
    var birthDate: Date?
    var biologicalSex: String?
    var sleepSource = ""
    var status = "active"
    var writeHealth = false
    var cycle = false
    var darkMode = "system"
    var language = "es"
    var imperial = false
    var alarm = AlarmConfiguration()
    var enabledCards = ["health", "stress", "energy", "activity", "journal"]
    /// Signature of the HealthKit types this install has asked permission for.
    /// When a new version reads a type that was never requested, its queries
    /// fail with "authorization not determined" — which used to take the whole
    /// sync down with them. Comparing this against the current catalogue is how
    /// the app knows to ask again.
    var authorizedCatalog: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case onboarded, baseSleep, importDays, autoSyncMinutes, lastSyncAt, healthConnected
        case maximumHR, birthDate, biologicalSex, sleepSource, status, writeHealth, cycle, darkMode, language
        case imperial, alarm, enabledCards, authorizedCatalog
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UserPreferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        onboarded = value(.onboarded, fallback.onboarded)
        baseSleep = value(.baseSleep, fallback.baseSleep)
        importDays = value(.importDays, fallback.importDays)
        autoSyncMinutes = value(.autoSyncMinutes, fallback.autoSyncMinutes)
        lastSyncAt = try? container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        healthConnected = value(.healthConnected, fallback.healthConnected)
        maximumHR = value(.maximumHR, fallback.maximumHR)
        birthDate = try? container.decodeIfPresent(Date.self, forKey: .birthDate)
        biologicalSex = try? container.decodeIfPresent(String.self, forKey: .biologicalSex)
        sleepSource = value(.sleepSource, fallback.sleepSource)
        status = value(.status, fallback.status)
        writeHealth = value(.writeHealth, fallback.writeHealth)
        cycle = value(.cycle, fallback.cycle)
        darkMode = value(.darkMode, fallback.darkMode)
        language = value(.language, fallback.language)
        imperial = value(.imperial, fallback.imperial)
        alarm = value(.alarm, fallback.alarm)
        authorizedCatalog = try? container.decodeIfPresent(String.self, forKey: .authorizedCatalog)
        // Nutrition cards existed in earlier versions and must not come back.
        enabledCards = value(.enabledCards, fallback.enabledCards).filter { fallback.enabledCards.contains($0) }
        if enabledCards.isEmpty { enabledCards = fallback.enabledCards }
    }
}
