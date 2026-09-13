@preconcurrency import HealthKit
import Foundation
import Observation
import PulseCore

@Observable @MainActor final class WorkoutRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var running = false
    var paused = false
    var startDate: Date?
    var heartRate: Double?
    var calories: Double?
    var distance: Double?
    var error: String?
    var saving = false
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    func start(type: HKWorkoutActivityType, outdoor: Bool = false) async {
        guard session == nil else { return }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { error = L("healthUnavailable"); return }
            let read = Set([HKObjectType.quantityType(forIdentifier: .heartRate), HKObjectType.quantityType(forIdentifier: .activeEnergyBurned), HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)].compactMap { $0 })
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
            let configuration = HKWorkoutConfiguration(); configuration.activityType = type; configuration.locationType = outdoor ? .outdoor : .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.session = session; self.builder = builder
            session.delegate = self; builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let start = Date(); startDate = start; session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            running = true; paused = false; error = nil
        } catch { self.error = L("workoutStartError"); session?.end(); session = nil; builder = nil; running = false }
    }
    func togglePause() { guard running else { return }; if paused { session?.resume() } else { session?.pause() } }
    func finish() async -> Bool {
        guard let session, let builder, !saving else { return false }
        saving = true; defer { saving = false }
        do {
            session.end()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.endCollection(withEnd: Date()) { success, endError in
                    if let endError {
                        continuation.resume(throwing: endError)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "VeyraWorkout", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cerrar la colección de entrenamiento."]))
                    }
                }
            }
            _ = try await builder.finishWorkout()
            running = false; paused = false; self.session = nil; self.builder = nil
            return true
        } catch { self.error = L("workoutSaveError"); return false }
    }
    func addExternalHeartRate(_ value: Double) async {
        guard running, let builder, let type = HKQuantityType.quantityType(forIdentifier: .heartRate), (25...250).contains(value) else { return }
        let date = Date(); heartRate = value
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: value), start: date, end: date)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.add([sample]) { success, addError in
                if addError != nil || !success { Task { @MainActor in self.error = L("sensorError") } }
                continuation.resume()
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.paused = toState == .paused; if toState == .ended { self.running = false } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) { Task { @MainActor in self.error = L("workoutError") } }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType.quantityType(forIdentifier: .heartRate).flatMap { workoutBuilder.statistics(for: $0)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
        let calories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned).flatMap { workoutBuilder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie()) }
        let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning).flatMap { workoutBuilder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
        Task { @MainActor in self.heartRate = hr; self.calories = calories; self.distance = distance }
    }
}
