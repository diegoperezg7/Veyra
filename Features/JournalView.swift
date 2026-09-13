import SwiftUI
import PulseCore
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var date = Date()
    @State private var tags: [String: Bool] = [:]
    @State private var note = ""
    @State private var custom = ""
    @State private var saved = false
    private let builtins = ["alcohol", "caffeine", "lateMeal", "meditation", "sunlight", "screenTime", "sauna", "travel", "sickness", "supplements", "pain", "mood"]
    var body: some View { Form {
        Section { DatePicker(L("date"), selection: $date, in: ...Date()); Text(L("journalDayDetail")).font(.caption).foregroundStyle(.secondary) }
        Section(L("habits")) { ForEach(builtins + tags.keys.filter { !builtins.contains($0) }.sorted(), id: \.self) { key in HStack { Text(L(key)); Spacer(); Picker(L(key), selection: Binding(get: { tags[key].map { $0 ? 1 : 0 } ?? -1 }, set: { if $0 == -1 { tags.removeValue(forKey: key) } else { tags[key] = $0 == 1 } })) { Text("—").tag(-1); Text(L("no")).tag(0); Text(L("yes")).tag(1) }.pickerStyle(.segmented).frame(width: 160) } }; HStack { TextField(L("customHabit"), text: $custom); Button(L("add")) { let key = custom.trimmingCharacters(in: .whitespaces); if !key.isEmpty { tags[key] = true; custom = "" } } } }
        Section(L("notes")) { TextEditor(text: $note).frame(minHeight: 90) }
        Section { Button(L("save")) { Task { var entry = LogEntry(kind: "journal", title: L("journal"), note: note, tags: tags); entry.date = date; await model.addEntry(entry); saved = true; tags = [:]; note = "" } }.disabled(tags.isEmpty && note.isEmpty); if saved { Label(L("saved"), systemImage: "checkmark") } }
        Section(L("history")) { ForEach(model.entries.filter { $0.kind == "journal" }.sorted { $0.date > $1.date }) { entry in VStack(alignment: .leading, spacing: 5) { Text(entry.date.formatted(date: .abbreviated, time: .shortened)); Text(entry.tags.map { L($0.key) + ": " + L($0.value ? "yes" : "no") }.sorted().joined(separator: ", ")).font(.caption); Text(entry.note).font(.subheadline) }.swipeActions { Button(L("delete"), role: .destructive) { model.deleteEntry(entry) } } } }
    }.navigationTitle(L("journal")) }
}
struct TrainingPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 3
    @State private var goal = "generalFitness"
    @State private var saved = false
    var body: some View { Form { Section { Picker(L("goal"), selection: $goal) { ForEach(["generalFitness", "strength", "endurance"], id: \.self) { Text(L($0)).tag($0) } }; Stepper(L("daysPerWeek") + ": \(days)", value: $days, in: 2...5); Text(L("planDetail")).font(.footnote).foregroundStyle(.secondary) }
        ForEach(0..<days, id: \.self) { index in Section(L("day") + " \(index + 1)") { ForEach(selectedExercises(index)) { exercise in Text(exercise.name); Text("3 × 8–12 · " + L("chooseWeight")).font(.caption).foregroundStyle(.secondary) } } }
        Button(L("savePlan")) { for index in 0..<days { let sets = selectedExercises(index).flatMap { exercise in (0..<3).map { _ in StrengthSet(exerciseID: exercise.id, reps: goal == "strength" ? 8 : 12) } }; model.saveTemplate(.init(name: L(goal) + " · " + L("day") + " \(index + 1)", sets: sets)) }; saved = true }.disabled(saved)
        if saved { Label(L("planSaved"), systemImage: "checkmark") }
    }.navigationTitle(L("trainingPlan")) }
    private func selectedExercises(_ day: Int) -> [ExerciseDefinition] { let patterns = ["squat", "hinge", "push", "pull", "core"]; return patterns.compactMap { pattern in let options = model.exercises.filter { $0.movementPattern == pattern && !$0.name.contains("tempo") && !$0.name.contains("pause") }; return options.isEmpty ? nil : options[min(day, options.count - 1)] } }
}
struct CheckinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var text = ""
    var body: some View { Form { DatePicker(L("time"), selection: $time, displayedComponents: .hourAndMinute); TextField(L("reminder"), text: $text, axis: .vertical); Text(L("checkinDetail")).font(.footnote); Button(L("schedule")) { Task { do { try await NotificationService.schedule(id: "checkin", title: "Veyra", body: text, date: time, repeats: true); dismiss() } catch { model.errorMessage = L("notificationError") } } }.disabled(text.isEmpty); Button(L("removeReminder"), role: .destructive) { NotificationService.cancel("checkin"); dismiss() } }.navigationTitle(L("checkin")) }
}
