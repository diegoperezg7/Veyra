import SwiftUI
import PulseCore
import HealthKit

@Observable @MainActor final class WatchModel {
    var snapshot: DailySnapshot?
    var templates: [WorkoutTemplate] = []
    var alarmConfig = AlarmConfiguration()
    var completedSets: Set<UUID> = []
    var selectedTemplate: WorkoutTemplate?
    var lastAction: String?
    let connectivity = Connectivity()
    let recorder = WorkoutRecorder()
    let alarm = SmartAlarm()
    init() {
        snapshot = SharedSnapshotStore.read()
        if let data = UserDefaults.standard.data(forKey: "watchEnvelope"), let envelope = try? JSONDecoder().decode(WatchEnvelope.self, from: data) { templates = envelope.templates ?? []; alarmConfig = envelope.alarm ?? AlarmConfiguration() }
        connectivity.onReceive = { [weak self] envelope in self?.receive(envelope) }
        if alarmConfig.enabled { alarm.configure(alarmConfig) }
    }
    private func receive(_ envelope: WatchEnvelope) {
        if let snapshot = envelope.snapshot { self.snapshot = snapshot; do { try SharedSnapshotStore.write(snapshot) } catch { lastAction = L("saveError") } }
        if let templates = envelope.templates { self.templates = templates }
        if let config = envelope.alarm, config != alarmConfig { alarmConfig = config; alarm.configure(config) }
        do { let saved = WatchEnvelope(snapshot: snapshot, templates: templates, alarm: alarmConfig); UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: "watchEnvelope") } catch { lastAction = L("saveError") }
    }
    func updateAlarm() { alarm.configure(alarmConfig); receive(.init(alarm: alarmConfig)) }
}
@main struct PulseLabWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene { WindowGroup { NavigationStack { WatchHome() }.environment(model) } }
}
struct WatchHome: View {
    @Environment(WatchModel.self) private var model
    var body: some View { List {
        Image("VeyraLogo").renderingMode(.template).resizable().scaledToFit().frame(width: 140, height: 48).foregroundStyle(WatchColors.accent).frame(maxWidth: .infinity).listRowBackground(Color.clear)
        NavigationLink { WatchMetricDetail(metric: .energy) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("bodyBattery"), systemImage: "bolt.heart.fill").font(.caption).foregroundStyle(WatchColors.accent)
                HStack(alignment: .firstTextBaseline) {
                    Text(number(model.snapshot?.score(.energy).value)).font(.system(size: 42, weight: .light)).monospacedDigit()
                    Text("/100").font(.caption).foregroundStyle(.secondary)
                }
                if let value = model.snapshot?.score(.energy).value { ProgressView(value: min(100, max(0, value)), total: 100).tint(WatchColors.accent) }
                Text(L("estimate")).font(.caption2).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }.listRowBackground(WatchColors.accent.opacity(0.14))
        if model.recorder.running { NavigationLink(L("resumeWorkout")) { WatchLiveWorkout() }.tint(.green) }
        ForEach(Metric.allCases.filter { $0 != .energy }) { metric in NavigationLink { WatchMetricDetail(metric: metric) } label: { HStack { VStack(alignment: .leading, spacing: 5) { Text(L(metric.rawValue)).font(.caption).foregroundStyle(.secondary); Text(number(model.snapshot?.score(metric).value)).font(.system(size: 34, weight: .semibold)) }; Spacer(); Image(systemName: metric == .sleep ? "moon.fill" : "waveform.path.ecg").foregroundStyle(color(metric)) } }.listRowBackground(color(metric).opacity(0.12)) }
        NavigationLink { WatchWorkouts() } label: { Label(L("workout"), systemImage: "figure.run") }
        NavigationLink { WatchStrength() } label: { Label(L("strengthBuilder"), systemImage: "dumbbell") }
        NavigationLink { WatchAlarmView() } label: { Label(L("smartAlarm"), systemImage: "alarm") }
        NavigationLink { List { ForEach(model.snapshot?.vitals ?? []) { vital in VStack(alignment: .leading) { Text(L(vital.id)).font(.caption); Text(number(vital.value, digits: 1) + " " + vital.unit) } } } } label: { Label(L("healthMonitor"), systemImage: "heart") }
        if let snapshot = model.snapshot { Text(L("updated") + " " + snapshot.updatedAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
        else { Text(L("openPhoneToSync")).font(.caption) }
    }.navigationTitle("").toolbarTitleDisplayMode(.inline).sheet(isPresented: Binding(get: { model.alarm.ringing }, set: { if !$0 { model.alarm.stop() } })) { VStack { Text(L("wakeTime")).font(.title2); Button(L("stop")) { model.alarm.stop() }; if model.alarmConfig.snoozeMinutes > 0 { Button(L("snooze")) { model.alarm.snooze() } } } } }
    private func color(_ metric: Metric) -> Color { WatchColors.metric(metric) }
}
struct WatchMetricDetail: View {
    @Environment(WatchModel.self) private var model
    let metric: Metric
    var body: some View { List { Text(number(model.snapshot?.score(metric).value)).font(.system(size: 60, weight: .semibold)).frame(maxWidth: .infinity); Text(L(model.snapshot?.score(metric).confidence.rawValue ?? "insufficient")).font(.caption); ForEach(model.snapshot?.score(metric).contributors ?? []) { item in VStack(alignment: .leading) { Text(L(item.id)).font(.caption); Text(number(item.value, digits: 1) + " " + item.unit) } }; if model.snapshot?.score(metric).value == nil { Text(L("noDataDetail")).font(.caption) } }.navigationTitle(L(metric.rawValue)) }
}
struct WatchWorkouts: View {
    @Environment(WatchModel.self) private var model
    @State private var starting = false
    private let types: [(String, HKWorkoutActivityType)] = [("running", .running), ("walking", .walking), ("hiking", .hiking), ("cycling", .cycling), ("hiit", .highIntensityIntervalTraining), ("strength", .traditionalStrengthTraining), ("functionalStrength", .functionalStrengthTraining), ("yoga", .yoga), ("rowing", .rowing), ("elliptical", .elliptical), ("stairs", .stairClimbing), ("swimming", .swimming), ("martialArts", .martialArts), ("coreTraining", .coreTraining), ("workout", .mixedCardio)]
    var body: some View { List { ForEach(types, id: \.0) { name, type in Button(L(name)) { starting = true; Task { await model.recorder.start(type: type, outdoor: ["running", "walking", "hiking", "cycling"].contains(name)); starting = false } }.disabled(starting || model.recorder.running) }; if let error = model.recorder.error { Text(error).font(.caption).foregroundStyle(.red) } }.navigationTitle(L("workout")).navigationDestination(isPresented: Binding(get: { model.recorder.running }, set: { _ in })) { WatchLiveWorkout() } }
}
struct WatchLiveWorkout: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View { ScrollView { VStack(spacing: 16) {
        if let date = model.recorder.startDate { Text(date, style: .timer).font(.title2.monospacedDigit()).foregroundStyle(.yellow) }
        Text(number(model.recorder.heartRate)).font(.system(size: 50, weight: .bold)).foregroundStyle(.red)
        Text("bpm").font(.caption)
        Text(number(model.recorder.calories) + " kcal").font(.title3)
        if let distance = model.recorder.distance { Text(number(distance / 1000, digits: 2) + " km") }
        if let template = model.selectedTemplate {
            ForEach(template.sets) { set in
                Button { model.completedSets.insert(set.id) } label: {
                    HStack { Image(systemName: model.completedSets.contains(set.id) ? "checkmark.circle.fill" : "circle"); Text("\(set.reps) × \(number(set.weightKg)) kg") }
                }
            }
        }
        Button(L(model.recorder.paused ? "resume" : "pause")) { model.recorder.togglePause() }
        Button(L("finishWorkout"), role: .destructive) { Task { if await model.recorder.finish() { model.selectedTemplate = nil; model.completedSets = []; dismiss() } } }.disabled(model.recorder.saving)
        if let error = model.recorder.error { Text(error).font(.caption).foregroundStyle(.red) }
    }.padding(.horizontal) }.navigationBarBackButtonHidden(model.recorder.saving) }
}
struct WatchStrength: View {
    @Environment(WatchModel.self) private var model
    var body: some View { List { if model.templates.isEmpty { Text(L("createRoutineOnPhone")) }; ForEach(model.templates) { template in Button(template.name) { model.selectedTemplate = template; model.completedSets = []; Task { await model.recorder.start(type: .traditionalStrengthTraining) } }.disabled(model.recorder.running) } }.navigationTitle(L("strengthBuilder")).navigationDestination(isPresented: Binding(get: { model.recorder.running }, set: { _ in })) { WatchLiveWorkout() } }
}
struct WatchAlarmView: View {
    @Environment(WatchModel.self) private var model
    var body: some View { @Bindable var model = model
        Form { Toggle(L("enableAlarm"), isOn: $model.alarmConfig.enabled); Stepper(L("hour") + ": \(model.alarmConfig.hour)", value: $model.alarmConfig.hour, in: 0...23); Stepper(L("minute") + ": \(model.alarmConfig.minute)", value: $model.alarmConfig.minute, in: 0...59); Picker(L("smartWindow"), selection: $model.alarmConfig.windowMinutes) { ForEach([0, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) } }; Button(L("save")) { model.updateAlarm() }; Text(L(model.alarm.status)).font(.caption); if let target = model.alarm.target { Text(target.formatted(date: .omitted, time: .shortened)) } }.navigationTitle(L("smartAlarm"))
    }
}


/// The watch renders dark only, so these are the dark half of the phone's
/// adaptive tokens, repeated here because the watch target cannot import them.
enum WatchColors {
    static let accent = Color(red: 0x27 / 255, green: 0xF6 / 255, blue: 0xCC / 255)
    static func metric(_ metric: Metric) -> Color {
        switch metric {
        case .recovery: accent
        case .sleep: Color(red: 0x8F / 255, green: 0xA5 / 255, blue: 1)
        case .strain: Color(red: 1, green: 0x9E / 255, blue: 0x52 / 255)
        case .stress: Color(red: 0xC9 / 255, green: 0x8C / 255, blue: 0xF5 / 255)
        case .energy: Color(red: 1, green: 0xD6 / 255, blue: 0x66 / 255)
        }
    }
}
