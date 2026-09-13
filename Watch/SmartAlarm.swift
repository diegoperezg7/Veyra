import Foundation
import WatchKit
@preconcurrency import CoreMotion
import Observation
import UserNotifications
import PulseCore

@Observable @MainActor final class SmartAlarm: NSObject, WKExtendedRuntimeSessionDelegate {
    var status = "off"
    var ringing = false
    var target: Date?
    private var runtime: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()
    private var timer: Timer?
    private var movement: [Double] = []
    private var config = AlarmConfiguration()
    func configure(_ config: AlarmConfiguration) {
        self.config = config
        runtime?.invalidate(); timer?.invalidate(); motion.stopAccelerometerUpdates(); ringing = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-backup"])
        guard config.enabled, let target = config.nextDate() else { status = "off"; self.target = nil; return }
        self.target = target
        let start = max(Date().addingTimeInterval(2), target.addingTimeInterval(-Double(max(1, config.windowMinutes)) * 60))
        let session = WKExtendedRuntimeSession(); session.delegate = self; runtime = session
        session.start(at: start); status = "scheduled"
        Task {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { status = "notificationPermissionRequired"; return }
                let content = UNMutableNotificationContent(); content.title = L("smartAlarm"); content.body = L("wakeTime"); content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target), repeats: false)
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "alarm-backup", content: content, trigger: trigger))
            } catch { status = "alarmBackupFailed" }
        }
    }
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) { Task { @MainActor in self.startMonitoring() } }
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) { Task { @MainActor in if !self.ringing { self.sound() } } }
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        let failed = error != nil
        Task { @MainActor in self.motion.stopAccelerometerUpdates(); self.timer?.invalidate(); if failed { self.status = "alarmFallback" } }
    }
    private func startMonitoring() {
        status = "monitoring"; movement = []
        if config.windowMinutes > 0 && motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1
            motion.startAccelerometerUpdates(to: .main) { [weak self] sample, _ in
                guard let sample else { return }
                let acceleration = sample.acceleration
                let magnitude = abs(sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z) - 1)
                Task { @MainActor [weak self] in guard let self else { return }; self.movement.append(magnitude); if self.movement.count > 60 { self.movement.removeFirst() } }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
    }
    private func tick() {
        guard !ringing, let target else { return }
        // Motion is a wakefulness cue only; no live sleep-stage claims.
        let naturalMovement = config.windowMinutes > 0 && movement.count >= 30 && movement.suffix(15).filter { $0 > 0.12 }.count >= 10
        if Date() >= target || naturalMovement { sound() }
    }
    private func sound() {
        guard !ringing else { return }; ringing = true; status = "wakeTime"
        motion.stopAccelerometerUpdates(); timer?.invalidate()
        runtime?.notifyUser(hapticType: .notification, repeatHandler: { _ in 3 })
    }
    func stop() { ringing = false; runtime?.invalidate(); timer?.invalidate(); motion.stopAccelerometerUpdates(); status = "off"; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-backup"]) }
    func snooze() {
        stop(); guard config.snoozeMinutes > 0 else { return }
        let date = Date().addingTimeInterval(Double(config.snoozeMinutes) * 60)
        var next = config; next.hour = Calendar.current.component(.hour, from: date); next.minute = Calendar.current.component(.minute, from: date); next.windowMinutes = 0; configure(next)
    }
}
