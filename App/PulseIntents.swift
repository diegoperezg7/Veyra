import AppIntents
import Foundation
struct OpenPulseMetric: AppIntent {
    static let title: LocalizedStringResource = "Open Veyra"
    static let openAppWhenRun = true
    @Parameter(title: "Screen", default: "today") var screen: String
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "pulselab://" + (["today", "recovery", "sleep", "strain", "stress", "energy", "fitness", "biology", "trends", "journal", "alarm", "workout"].contains(screen) ? screen : "today"))!)) }
}
struct PulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] { AppShortcut(intent: OpenPulseMetric(), phrases: ["Open \(.applicationName)"], shortTitle: "PulseLab", systemImageName: "waveform.path.ecg") }
}
