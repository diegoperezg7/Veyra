import XCTest
import HealthKit
@testable import Veyra
@testable import PulseCore

/// The launch path is the one thing every single use of the app pays for, and
/// the background observers are what decide whether the phone stays cool. Both
/// are easy to undo by accident, so they are pinned here.
@MainActor final class PerformanceGuardTests: XCTestCase {

    func testLaunchReadsOnlyTheRecentWindowAndNoCatalogue() throws {
        let store = try LocalStore(inMemory: true)
        // A year and a half of history, so the window genuinely has to bite.
        let calendar = Calendar.current
        for offset in 0..<500 {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let snapshot = DailySnapshot(date: calendar.startOfDay(for: date))
            try store.save(snapshot, key: "daily.\(offset)", kind: "daily", date: snapshot.date)
        }
        let model = try AppModel(store: store)
        XCTAssertEqual(model.history.count, AppModel.launchWindow,
                       "el arranque debe leer solo la ventana reciente")
        XCTAssertFalse(model.historyComplete)
        XCTAssertTrue(model.exercises.isEmpty, "el catálogo no se decodifica en el arranque")

        // The window keeps the newest days, not the oldest.
        let newest = model.history.map(\.date).max()!
        XCTAssertTrue(calendar.isDateInToday(newest))
    }

    func testTheRestOfTheHistoryLoadsAfterwards() async throws {
        let store = try LocalStore(inMemory: true)
        let calendar = Calendar.current
        for offset in 0..<120 {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            try store.save(DailySnapshot(date: calendar.startOfDay(for: date)), key: "daily.\(offset)", kind: "daily", date: date)
        }
        let model = try AppModel(store: store)
        XCTAssertEqual(model.history.count, AppModel.launchWindow)
        await model.loadRemainingHistory()
        XCTAssertEqual(model.history.count, 120, "el resto del historial debe acabar cargado")
        XCTAssertTrue(model.historyComplete)
        // Still in order, and without duplicates.
        XCTAssertEqual(model.history, model.history.sorted { $0.date < $1.date })
        XCTAssertEqual(Set(model.history.map(\.date)).count, 120)
    }

    func testVitalLookupsAreIndexedRatherThanScanned() throws {
        let store = try LocalStore(inMemory: true)
        let model = try AppModel(store: store)
        let day = Date()
        model.history = [
            DailySnapshot(date: day.addingTimeInterval(-86400), vitals: [.init(id: "hrv", value: 40, unit: "ms", date: day.addingTimeInterval(-86400))]),
            DailySnapshot(date: day, vitals: [.init(id: "hrv", value: 55, unit: "ms", date: day),
                                             .init(id: "rhr", value: 50, unit: "bpm", date: day)])
        ]
        XCTAssertEqual(model.latestVital("hrv")?.value, 55)
        XCTAssertEqual(model.vitalSeries["hrv"]?.count, 2)
        XCTAssertEqual(model.vitalSeries["hrv"]?.map(\.value), [40, 55], "la serie debe quedar ordenada")
        XCTAssertNil(model.latestVital("weight"))
    }

    /// Waking the app for every heart-rate sample ran a full import dozens of
    /// times a day and warmed the phone for nothing. A finished workout is a
    /// different matter: it happens a few times a week and is worth reacting to.
    func testOnlyWorkoutsWakeTheAppImmediately() {
        let immediate = AppModel.observedTypesForTesting.filter { $0.1 == .immediate }
        XCTAssertEqual(immediate.map(\.0.identifier), [HKWorkoutTypeIdentifier],
                       "solo los entrenamientos deben despertar la app de inmediato")
        XCTAssertGreaterThanOrEqual(AppModel.observerSyncInterval, 300,
                                    "las observaciones deben agruparse, no sincronizar una por una")
    }
}

/// The sample history is what review builds and screenshots show, so its
/// exercise ids have to exist in the catalogue that ships alongside it.
@MainActor final class SampleDataTests: XCTestCase {
    func testSampleWorkoutsReferenceRealExercises() async throws {
        let model = try AppModel(store: LocalStore(inMemory: true))
        await model.loadExercises()
        let catalogue = Set(model.exercises.map(\.id))
        let referenced = Set(SampleData.strengthSessions().flatMap { $0.sets.map(\.exerciseID) })
        XCTAssertFalse(referenced.isEmpty)
        XCTAssertTrue(referenced.isSubset(of: catalogue),
                      "faltan del catálogo: \(referenced.subtracting(catalogue).sorted())")
    }
}

/// Screens slice `history` directly instead of sorting it, so the order has to
/// be an invariant rather than a hope.
@MainActor final class HistoryOrderTests: XCTestCase {
    func testHistoryIsSortedAfterEveryLoadPath() async throws {
        let store = try LocalStore(inMemory: true)
        let calendar = Calendar.current
        // Saved out of order on purpose.
        for offset in [5, 1, 9, 3, 7, 0, 2] {
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: Date())!)
            try store.save(DailySnapshot(date: date), key: "daily.\(offset)", kind: "daily", date: date)
        }
        let model = try AppModel(store: store)
        XCTAssertEqual(model.history.map(\.date), model.history.map(\.date).sorted())
        await model.loadRemainingHistory()
        XCTAssertEqual(model.history.map(\.date), model.history.map(\.date).sorted())
    }
}

/// The sample workouts feed the detail screen in review builds, so they have to
/// carry everything that screen reads.
@MainActor final class SampleWorkoutTests: XCTestCase {
    func testSampleWorkoutsCarryHeartRateAndZones() {
        let history = SampleData.history(days: 10)
        let workouts = history.flatMap(\.workouts)
        XCTAssertFalse(workouts.isEmpty)
        for workout in workouts {
            XCTAssertGreaterThan(workout.minutes, 0, "un entrenamiento no puede durar cero")
            XCTAssertFalse(workout.heartRate?.isEmpty ?? true, "falta la serie de pulso")
            XCTAssertNotNil(workout.averageHeartRate)
            XCTAssertNotNil(WorkoutAnalysis.zoneShare(workout), "sin reparto por zonas")
            XCTAssertNotNil(WorkoutAnalysis.focus(workout))
            XCTAssertNotNil(workout.restingHeartRate)
            XCTAssertNotNil(workout.maximumHeartRateReference)
            // Never in the future, whatever time of day the sample is built.
            XCTAssertLessThanOrEqual(workout.end, Date().addingTimeInterval(60))
        }
        // Today has one, because today is the day every screen opens on.
        let today = history.first { Calendar.current.isDateInToday($0.date) }
        XCTAssertFalse(today?.workouts.isEmpty ?? true, "el día de hoy debe traer entrenamiento")
    }
}
