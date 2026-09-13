#if os(iOS)
@preconcurrency import ActivityKit
import Foundation
struct StrengthAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var exercise: String; var completedSets: Int; var totalSets: Int; var restUntil: Date? }
    var name: String
    var start: Date
}
@MainActor enum StrengthLiveActivity {
    static var current: Activity<StrengthAttributes>?
    static func start(name: String, date: Date, sets: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do { current = try Activity.request(attributes: StrengthAttributes(name: name, start: date), content: ActivityContent(state: .init(exercise: name, completedSets: 0, totalSets: sets), staleDate: nil), pushType: nil) } catch { current = nil }
    }
    static func update(exercise: String, completed: Int, total: Int, rest: Date?) async { await current?.update(ActivityContent(state: .init(exercise: exercise, completedSets: completed, totalSets: total, restUntil: rest), staleDate: rest)) }
    static func end() async { await current?.end(nil, dismissalPolicy: .immediate); current = nil }
}
#endif
