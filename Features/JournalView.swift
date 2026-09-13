import SwiftUI
import PulseCore

/// The three states a habit can be in. "Not recorded" is a real answer and has
/// to stay distinguishable from "no": a day you never filled in must not count
/// as a day without caffeine.
enum HabitState {
    case unrecorded, no, yes
}

/// The habit switch. A capsule with a minus on one side and a plus on the
/// other, and a lit thumb that slides to the answer — green for yes, red for
/// no, nothing at all until you answer. Tapping the side that is already lit
/// clears it, which is the only way back to "not recorded".
struct HabitSwitch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var state: HabitState
    var onChange: (HabitState) -> Void

    private let width: CGFloat = 92
    private let height: CGFloat = 38

    private var tint: Color {
        switch state {
        case .yes: AppColors.accentVivid
        case .no: AppColors.danger
        case .unrecorded: .clear
        }
    }

    var body: some View {
        ZStack {
            Capsule().fill(AppColors.surfaceRaised)
            Capsule().strokeBorder(AppColors.border, lineWidth: 1)
            if state != .unrecorded {
                thumb
                    .frame(width: width / 2 - 3, height: height - 6)
                    .offset(x: state == .yes ? width / 4 : -width / 4)
            }
            // Real buttons rather than a tap gesture over the capsule: each
            // half has to know it was the one pressed, and this way VoiceOver
            // and the hit testing both come for free.
            HStack(spacing: 0) {
                half(.no, symbol: "minus")
                half(.yes, symbol: "plus")
            }
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: state)
        .accessibilityElement(children: .contain)
    }

    /// Lit from above, the way the battery cell is, so it reads as a physical
    /// switch rather than a coloured rectangle.
    private var thumb: some View {
        Capsule()
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.28), tint],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.55), radius: 7, y: 1)
    }

    private func half(_ target: HabitState, symbol: String) -> some View {
        Button {
            // Pressing the lit side clears the answer: the only way back to
            // "not recorded" once something has been set.
            onChange(state == target ? .unrecorded : target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(state == target ? Color.white : AppColors.ink.opacity(0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(target == .yes ? "yes" : "no"))
    }
}

/// Icons and colours for the built-in habits, so the list can be read at a
/// glance instead of parsed word by word.
enum HabitStyle {
    static func symbol(_ key: String) -> String {
        switch key {
        case "alcohol": "wineglass.fill"
        case "caffeine": "cup.and.saucer.fill"
        case "lateMeal": "fork.knife"
        case "meditation": "figure.mind.and.body"
        case "sunlight": "sun.max.fill"
        case "screenTime": "iphone"
        case "sauna": "thermometer.sun.fill"
        case "travel": "airplane"
        case "sickness": "cross.case.fill"
        case "supplements": "pills.fill"
        case "pain": "bandage.fill"
        case "mood": "face.smiling"
        case "stress": "waveform.path.ecg"
        case "nap": "zzz"
        case "coldPlunge": "snowflake"
        case "massage": "hands.and.sparkles.fill"
        default: "tag.fill"
        }
    }
    /// A quiet tint per habit, used only for the icon. The switch carries the
    /// answer's colour; the icon carries the habit's identity.
    static func tint(_ key: String) -> Color {
        switch key {
        case "alcohol", "lateMeal", "screenTime": AppColors.metric(.strain)
        case "caffeine", "supplements": AppColors.metric(.energy)
        case "meditation", "sauna", "massage", "nap", "coldPlunge": AppColors.metric(.sleep)
        case "sunlight": AppColors.metric(.energy)
        case "sickness", "pain": AppColors.metric(.stress)
        default: AppColors.accent
        }
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var date = Date()
    @State private var tags: [String: Bool] = [:]
    @State private var note = ""
    @State private var custom = ""
    @State private var saved = false
    @FocusState private var noteFocused: Bool

    private let builtins = ["alcohol", "caffeine", "lateMeal", "meditation", "sunlight",
                            "screenTime", "sauna", "nap", "coldPlunge", "travel",
                            "sickness", "supplements", "pain"]

    private var customKeys: [String] { tags.keys.filter { !builtins.contains($0) }.sorted() }
    private var answered: Int { tags.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                dayCard
                habitsCard
                notesCard
                saveButton
                if !history.isEmpty { historyCard }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L("journal"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var dayCard: some View {
        Card(spacing: 10) {
            HStack {
                Label(L("date"), systemImage: "calendar")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
            }
            Text(L("journalDayDetail"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var habitsCard: some View {
        Card(spacing: 4) {
            HStack {
                Label(L("habits"), systemImage: "checklist").font(AppTypography.cardTitle)
                Spacer()
                if answered > 0 {
                    Text("\(answered)").font(.caption.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(AppColors.accentSoft, in: Capsule())
                        .foregroundStyle(AppColors.accent)
                        .contentTransition(.numericText())
                }
            }
            .padding(.bottom, 6)

            ForEach(builtins + customKeys, id: \.self) { key in
                HabitRow(key: key, state: state(for: key)) { newState in
                    withAnimation(.snappy(duration: 0.2)) { set(key, newState) }
                }
                if key != (builtins + customKeys).last {
                    Divider().overlay(AppColors.divider)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.accent)
                TextField(L("customHabit"), text: $custom)
                    .font(.subheadline)
                    .onSubmit(addCustom)
                if !custom.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(L("add"), action: addCustom)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent).tint(AppColors.accent)
                }
            }
            .padding(.top, 12)
        }
    }

    private var notesCard: some View {
        Card(spacing: 8) {
            Label(L("notes"), systemImage: "text.alignleft").font(AppTypography.cardTitle)
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text(L("journalNotePlaceholder"))
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .focused($noteFocused)
                    .font(.subheadline)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
            }
        }
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: saved ? "saved" : "save") { save() }
                .disabled(tags.isEmpty && note.isEmpty)
                .opacity(tags.isEmpty && note.isEmpty ? 0.5 : 1)
            if saved {
                Label(L("journalSavedDetail"), systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(AppColors.accent)
            }
        }
    }

    private var history: [LogEntry] {
        model.entries.filter { $0.kind == "journal" }.sorted { $0.date > $1.date }
    }

    private var historyCard: some View {
        Card(spacing: 12) {
            Label(L("history"), systemImage: "clock.arrow.circlepath").font(AppTypography.cardTitle)
            ForEach(history.prefix(20)) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            model.deleteEntry(entry)
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                    }
                    if !entry.tags.isEmpty {
                        HabitChips(tags: entry.tags)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if entry.id != history.prefix(20).last?.id {
                    Divider().overlay(AppColors.divider)
                }
            }
        }
    }

    private func state(for key: String) -> HabitState {
        guard let value = tags[key] else { return .unrecorded }
        return value ? .yes : .no
    }
    private func set(_ key: String, _ state: HabitState) {
        switch state {
        case .unrecorded: tags.removeValue(forKey: key)
        case .yes: tags[key] = true
        case .no: tags[key] = false
        }
        saved = false
    }
    private func addCustom() {
        let key = custom.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, tags[key] == nil else { return }
        withAnimation(.snappy) { tags[key] = true }
        custom = ""
    }
    private func save() {
        noteFocused = false
        Task {
            var entry = LogEntry(kind: "journal", title: L("journal"), note: note, tags: tags)
            entry.date = date
            await model.addEntry(entry)
            withAnimation { saved = true; tags = [:]; note = "" }
        }
    }
}

/// One habit: its icon, its name, and the switch.
private struct HabitRow: View {
    var key: String
    var state: HabitState
    var onChange: (HabitState) -> Void

    private var iconTint: Color {
        switch state {
        case .yes: AppColors.accentVivid
        case .no: AppColors.danger
        case .unrecorded: HabitStyle.tint(key)
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: HabitStyle.symbol(key))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 34, height: 34)
                .background(iconTint.opacity(state == .unrecorded ? 0.10 : 0.16), in: Circle())
            Text(L(key))
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            HabitSwitch(state: state, onChange: onChange)
        }
        .padding(.vertical, 7)
        .accessibilityIdentifier("habit-" + key)
    }
}

/// The answers of a past day, as small icon chips.
private struct HabitChips: View {
    var tags: [String: Bool]
    private var ordered: [(String, Bool)] { tags.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(ordered, id: \.0) { key, value in
                HStack(spacing: 4) {
                    Image(systemName: HabitStyle.symbol(key)).font(.system(size: 9, weight: .semibold))
                    Text(L(key)).font(.caption2.weight(.medium))
                    Image(systemName: value ? "plus" : "minus").font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((value ? AppColors.accentVivid : AppColors.danger).opacity(0.12), in: Capsule())
                .foregroundStyle(value ? AppColors.accent : AppColors.danger)
            }
        }
    }
}

/// Chips wrap onto as many lines as they need. SwiftUI has no flow layout of
/// its own, and an HStack would push them off the card.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A starting plan: a few days a week, one compound movement per pattern.
/// Deliberately plain — it exists to give someone a first routine to edit, not
/// to prescribe training.
struct TrainingPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 3
    @State private var goal = "generalFitness"
    @State private var saved = false

    private let patterns = ["squat", "hinge", "push", "pull", "core"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card(spacing: 12) {
                    Label(L("trainingPlan"), systemImage: "calendar.badge.plus").font(AppTypography.cardTitle)
                    Picker(L("goal"), selection: $goal) {
                        ForEach(["generalFitness", "strength", "endurance"], id: \.self) { Text(L($0)).tag($0) }
                    }.pickerStyle(.segmented)
                    Stepper(L("daysPerWeek") + ": \(days)", value: $days, in: 2...5).font(.subheadline)
                    Text(L("planDetail")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(0..<days, id: \.self) { index in
                    Card(spacing: 12) {
                        Text(L("day") + " \(index + 1)").font(AppTypography.cardTitle)
                        ForEach(exercises(index)) { exercise in
                            HStack(spacing: 12) {
                                ExerciseThumbnail(exercise: exercise, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text("3 × \(goal == "strength" ? "8" : "12") · " + L("chooseWeight"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                PrimaryButton(title: saved ? "planSaved" : "savePlan") {
                    for index in 0..<days {
                        let sets = exercises(index).flatMap { exercise in
                            (0..<3).map { _ in StrengthSet(exerciseID: exercise.id, reps: goal == "strength" ? 8 : 12) }
                        }
                        model.saveTemplate(.init(name: L(goal) + " · " + L("day") + " \(index + 1)", sets: sets))
                    }
                    saved = true
                }
                .disabled(saved)
            }
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L("trainingPlan"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One compound movement per pattern, rotated by day so the week is not the
    /// same session three times.
    private func exercises(_ day: Int) -> [ExerciseDefinition] {
        patterns.compactMap { pattern in
            let options = model.exercises
                .filter { $0.movementPattern == pattern && $0.compound && !$0.unilateral }
                .sorted { $0.id < $1.id }
            guard !options.isEmpty else { return nil }
            return options[day % options.count]
        }
    }
}

struct CheckinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var text = ""
    var body: some View { Form { DatePicker(L("time"), selection: $time, displayedComponents: .hourAndMinute); TextField(L("reminder"), text: $text, axis: .vertical); Text(L("checkinDetail")).font(.footnote); Button(L("schedule")) { Task { do { try await NotificationService.schedule(id: "checkin", title: "Veyra", body: text, date: time, repeats: true); dismiss() } catch { model.errorMessage = L("notificationError") } } }.disabled(text.isEmpty); Button(L("removeReminder"), role: .destructive) { NotificationService.cancel("checkin"); dismiss() } }.navigationTitle(L("checkin")) }
}
