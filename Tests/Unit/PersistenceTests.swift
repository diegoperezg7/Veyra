import XCTest
@testable import Veyra
import PulseCore

@MainActor final class PersistenceTests: XCTestCase {
    func testRecordUpsertAndDeletion() throws {
        let store = try LocalStore(inMemory: true)
        var entry = LogEntry(kind: "journal", title: "Journal", tags: ["caffeine": true])
        try store.save(entry, key: entry.id.uuidString, kind: "entry")
        entry.tags["caffeine"] = false
        try store.save(entry, key: entry.id.uuidString, kind: "entry")
        let entries = try store.load(LogEntry.self, kind: "entry")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.tags["caffeine"], false)
        try store.remove(key: entry.id.uuidString)
        XCTAssertTrue(try store.load(LogEntry.self, kind: "entry").isEmpty)
    }

    func testCatalogIsUniqueAndComplete() throws {
        let model = try AppModel(store: LocalStore(inMemory: true))
        XCTAssertGreaterThanOrEqual(model.exercises.count, 250)
        XCTAssertEqual(Set(model.exercises.map(\.id)).count, model.exercises.count)
        XCTAssertEqual(Set(model.exercises.map(\.name)).count, model.exercises.count)
        // Every exercise must be classifiable and drawable: the library is
        // browsed by picture, so one without artwork is unusable there.
        XCTAssertFalse(model.exercises.contains { $0.primaryMuscles.isEmpty })
        XCTAssertFalse(model.exercises.contains { $0.art.isEmpty || $0.group == "other" && $0.primaryMuscles.isEmpty })
        XCTAssertFalse(model.exercises.contains { $0.name.isEmpty || $0.steps.isEmpty })
        // The artwork each exercise names has to exist in the bundle.
        for exercise in model.exercises.prefix(40) {
            for frame in exercise.art {
                XCTAssertNotNil(Bundle.main.url(forResource: frame, withExtension: nil, subdirectory: "ExerciseArt"),
                                "falta \(frame)")
            }
        }
    }

    /// `LocalStore` deletes records it cannot decode, so preferences saved by an
    /// older build — including the removed AI and nutrition fields — must still
    /// load rather than silently resetting the user's configuration.
    func testPreferencesFromAnOlderBuildStillDecode() throws {
        let legacy: [String: Any] = [
            "onboarded": true, "baseSleep": 450.0, "importDays": 90, "autoSyncMinutes": 30,
            "healthConnected": true, "maximumHR": 191.0, "sleepSource": "", "status": "active",
            "writeHealth": false, "cycle": false, "darkMode": "dark", "language": "en",
            "imperial": false,
            // Fields that no longer exist.
            "remoteAI": true, "aiEndpoint": "https://example.invalid", "coachingStyle": "direct",
            "enabledCards": ["health", "nutrition", "energy"],
            "targets": ["protein": 120.0]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertTrue(decoded.onboarded)
        XCTAssertEqual(decoded.baseSleep, 450)
        XCTAssertEqual(decoded.maximumHR, 191)
        XCTAssertEqual(decoded.darkMode, "dark")
        // The removed nutrition card must not survive the migration.
        XCTAssertFalse(decoded.enabledCards.contains("nutrition"))
        XCTAssertTrue(decoded.enabledCards.contains("energy"))
    }

    /// Snapshots written before the confidence report and energy breakdown
    /// existed must keep decoding; otherwise upgrading wipes the history.
    func testSnapshotsFromAnOlderBuildStillDecode() throws {
        // `scores` is keyed by `Metric`, not by String, so Swift encodes it as a
        // flat array of alternating keys and values rather than as an object.
        let legacy = """
        {"date":728000000,"updatedAt":728000000,"scores":[],"vitals":[],"sleepSessions":[],
         "workouts":[],"stress":[],"energy":[],"sleepNeed":480,"sleepDebt":0}
        """
        let decoded = try JSONDecoder().decode(DailySnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.energyDetail)
        XCTAssertEqual(decoded.sleepNeed, 480)
    }

    /// Widgets and the watch must describe today, not whichever day happens to
    /// be last in a partially synced history.
    func testCurrentSnapshotPrefersToday() throws {
        let model = try AppModel(store: LocalStore(inMemory: true))
        let today = Calendar.current.startOfDay(for: Date())
        let older = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        model.history = [DailySnapshot(date: today), DailySnapshot(date: older)]
        XCTAssertEqual(model.currentSnapshot?.date, today)
    }
}
