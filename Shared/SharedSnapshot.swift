import Foundation
import PulseCore
import WidgetKit

enum SharedSnapshotStore {
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "PulseAppGroup") as? String ?? "group.local.pulselab" }
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
    static func write(_ snapshot: DailySnapshot) throws {
        guard let directory else { return }
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func read() -> DailySnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("snapshot.json")) else { return nil }
        return try? JSONDecoder().decode(DailySnapshot.self, from: data)
    }
}
