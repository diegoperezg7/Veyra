import SwiftUI
import PulseCore

// MARK: - Home

/// The strength screen. What it has to answer, in order: am I mid-workout, what
/// did I do last time, and what do I want to do now. The previous version
/// answered none of those — it opened on an empty list of routines.
struct StrengthView: View {
    @Environment(AppModel.self) private var model
    @State private var editingRoutine: WorkoutTemplate?
    @State private var creating = false

    private var finished: [StrengthSession] {
        model.sessions.filter { $0.end != nil }.sorted { $0.start > $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let active = model.activeSession {
                    activeCard(active)
                } else {
                    startCard
                }
                if !weeklyVolume.isEmpty { volumeCard }
                if !finished.isEmpty { repeatCard }
                if !model.templates.isEmpty { routinesCard }
                toolsCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L("strength"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { NavigationStack { RoutineEditor(template: nil) } }
        .sheet(item: $editingRoutine) { template in NavigationStack { RoutineEditor(template: template) } }
    }

    private func activeCard(_ session: StrengthSession) -> some View {
        Button { model.route = "activeStrength" } label: {
            Card(accent: AppColors.accent, spacing: 12) {
                HStack {
                    Label(L("workoutInProgress"), systemImage: "record.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppColors.accent)
                    Spacer()
                    Text(duration(session.minutes)).font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(session.name).font(.title3.weight(.bold))
                HStack(spacing: 18) {
                    figure(L("exercises"), "\(session.exerciseOrder.count)")
                    figure(L("series"), "\(session.sets.filter(\.completed).count)/\(session.sets.count)")
                    figure(L("volume"), number(StrengthHistoryEngine.volume(session.sets)) + " kg")
                }
                Label(L("continueWorkout"), systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private var startCard: some View {
        Card(spacing: 14) {
            Label(L("newWorkout"), systemImage: "figure.strengthtraining.traditional")
                .font(AppTypography.cardTitle)
            Text(L("newWorkoutDetail")).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "startEmptyWorkout") {
                model.startSession(name: L("strengthSession"))
            }
        }
    }

    /// Completed volume per muscle group over the trailing week. A set counts
    /// for its primary group only; splitting it across secondary ones would
    /// imply a precision the catalogue does not have.
    private var weeklyVolume: [(String, Double)] {
        let end = Date()
        let totals = StrengthHistoryEngine.volumeByGroup(
            sessions: model.sessions, catalogue: model.exercises,
            from: end.addingTimeInterval(-7 * 86400), to: end)
        return totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var volumeCard: some View {
        Card(spacing: 12) {
            Label(L("weeklyVolume"), systemImage: "chart.bar.fill").font(AppTypography.cardTitle)
            let peak = weeklyVolume.first?.1 ?? 1
            ForEach(weeklyVolume, id: \.0) { group, volume in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(L("group." + group), systemImage: ExerciseVocabulary.groupSymbol(group))
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(number(volume) + " kg").font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule().fill(AppColors.accentVivid)
                            .frame(width: max(3, proxy.size.width * volume / peak))
                    }
                    .frame(height: 6)
                }
            }
            Text(L("weeklyVolumeDetail")).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var repeatCard: some View {
        Card(spacing: 12) {
            Label(L("repeatWorkout"), systemImage: "arrow.counterclockwise")
                .font(AppTypography.cardTitle)
            Text(L("repeatWorkoutDetail")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(finished.prefix(3)) { session in
                Button { model.repeatWorkout(session) } label: {
                    HStack(spacing: 12) {
                        artStack(for: session)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name).font(.subheadline.weight(.semibold))
                            Text(session.start.formatted(date: .abbreviated, time: .omitted)
                                 + " · " + number(StrengthHistoryEngine.volume(session.sets)) + " kg")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.title3).foregroundStyle(AppColors.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.activeSession != nil)
                if session.id != finished.prefix(3).last?.id { Divider().overlay(AppColors.divider) }
            }
        }
    }

    /// The first few exercises of a session, drawn small and overlapped, so a
    /// past workout is recognisable without reading it.
    private func artStack(for session: StrengthSession) -> some View {
        HStack(spacing: -14) {
            ForEach(Array(session.exerciseOrder.prefix(3).enumerated()), id: \.offset) { index, id in
                if let exercise = model.exercise(id) {
                    ExerciseArtView(exercise: exercise, tint: AppColors.ink.opacity(0.75))
                        .padding(4)
                        .frame(width: 40, height: 40)
                        .background(AppColors.surfaceRaised, in: Circle())
                        .overlay(Circle().strokeBorder(AppColors.surface, lineWidth: 2))
                        .zIndex(Double(3 - index))
                }
            }
        }
    }

    private var routinesCard: some View {
        Card(spacing: 12) {
            HStack {
                Label(L("routines"), systemImage: "list.bullet.rectangle").font(AppTypography.cardTitle)
                Spacer()
                Button { creating = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(AppColors.accent)
            }
            ForEach(model.templates) { template in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name).font(.subheadline.weight(.semibold))
                        Text("\(Set(template.sets.map(\.exerciseID)).count) " + L("exercises")
                             + " · \(template.sets.count) " + L("series"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editingRoutine = template } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    Button { model.startStrength(template) } label: {
                        Image(systemName: "play.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain).foregroundStyle(AppColors.accent)
                    .disabled(model.activeSession != nil)
                }
                .padding(.vertical, 3)
                if template.id != model.templates.last?.id { Divider().overlay(AppColors.divider) }
            }
        }
    }

    private var toolsCard: some View {
        Card(spacing: 4) {
            if model.templates.isEmpty {
                Button { creating = true } label: {
                    row("createRoutine", "plus.rectangle.on.rectangle")
                }.buttonStyle(.plain)
                Divider().overlay(AppColors.divider)
            }
            NavigationLink { ExerciseLibraryView(onSelect: nil) } label: {
                row("exerciseLibrary", "square.grid.2x2")
            }.buttonStyle(.plain)
            Divider().overlay(AppColors.divider)
            NavigationLink { PlateCalculatorView() } label: {
                row("plateCalculator", "circle.grid.cross")
            }.buttonStyle(.plain)
            if !finished.isEmpty {
                Divider().overlay(AppColors.divider)
                NavigationLink { SessionHistoryView() } label: {
                    row("history", "clock.arrow.circlepath")
                }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(AppColors.accent).frame(width: 26)
            Text(L(title)).font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Active session

/// Logging a workout. Every exercise is a card with its illustration and its
/// sets; a set is weight, reps and a tick. New sets arrive pre-filled from the
/// last time you did that exercise, which is what makes this a few taps rather
/// than a typing exercise.
struct ActiveStrengthView: View {
    @Environment(AppModel.self) private var model
    @State private var session: StrengthSession?
    @State private var pickingExercise = false
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ContentUnavailableView(L("noActiveWorkout"), systemImage: "figure.strengthtraining.traditional")
            }
        }
        .navigationTitle(session?.name ?? L("strength"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if session == nil { session = model.activeSession } }
        .sheet(isPresented: $pickingExercise) {
            NavigationStack {
                ExerciseLibraryView { exercise in
                    add(exercise)
                    pickingExercise = false
                }
            }
        }
        .confirmationDialog(L("finishWorkout"), isPresented: $confirmFinish, titleVisibility: .visible) {
            Button(L("finishWorkout")) { finish() }
            Button(L("discardWorkout"), role: .destructive) { discard() }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("finishWorkoutDetail"))
        }
    }

    private func content(_ session: StrengthSession) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                summary(session)
                ForEach(session.exerciseOrder, id: \.self) { id in
                    ExerciseBlock(
                        exercise: model.exercise(id),
                        fallbackName: id,
                        sets: session.sets.filter { $0.exerciseID == id },
                        previous: StrengthHistoryEngine.lastSets(exercise: id, in: model.sessions.filter { $0.id != session.id }),
                        onChange: update,
                        onAdd: { addSet(id) },
                        onRemove: { remove($0) }
                    )
                }
                Button { pickingExercise = true } label: {
                    Label(L("addExercise"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                PrimaryButton(title: "finishWorkout") { confirmFinish = true }
                    .disabled(session.sets.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .scrollDismissesKeyboard(.interactively)
    }

    private func summary(_ session: StrengthSession) -> some View {
        Card(spacing: 10) {
            HStack(spacing: 20) {
                stat(duration(session.minutes), L("duration"))
                stat("\(session.sets.filter(\.completed).count)/\(session.sets.count)", L("series"))
                stat(number(StrengthHistoryEngine.volume(session.sets)) + " kg", L("volume"))
            }
            ProgressView(value: session.sets.isEmpty ? 0 : Double(session.sets.filter(\.completed).count) / Double(session.sets.count))
                .tint(AppColors.accentVivid)
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add(_ exercise: ExerciseDefinition) {
        guard var current = session else { return }
        // Pre-filled from the last time, or an empty set to type into.
        let suggestion = StrengthHistoryEngine.suggestion(exercise: exercise.id, in: model.sessions.filter { $0.id != current.id })
        current.sets.append(suggestion ?? StrengthSet(exerciseID: exercise.id))
        persist(current)
    }
    private func addSet(_ id: String) {
        guard var current = session else { return }
        let position = current.sets.filter { $0.exerciseID == id }.count
        let history = model.sessions.filter { $0.id != current.id }
        // Repeat the set just done rather than the historical one: within a
        // session the last thing you lifted is the better guess.
        let previous = current.sets.last { $0.exerciseID == id }
        var new = StrengthHistoryEngine.suggestion(exercise: id, position: position, in: history)
            ?? previous.map { var copy = $0; copy.id = UUID(); copy.completed = false; return copy }
            ?? StrengthSet(exerciseID: id)
        if let previous, previous.completed { new.weightKg = previous.weightKg; new.reps = previous.reps }
        new.id = UUID()
        new.completed = false
        // Insert after that exercise's last set so the card stays together.
        if let index = current.sets.lastIndex(where: { $0.exerciseID == id }) {
            current.sets.insert(new, at: index + 1)
        } else {
            current.sets.append(new)
        }
        persist(current)
    }
    private func update(_ set: StrengthSet) {
        guard var current = session, let index = current.sets.firstIndex(where: { $0.id == set.id }) else { return }
        current.sets[index] = set
        persist(current)
    }
    private func remove(_ set: StrengthSet) {
        guard var current = session else { return }
        current.sets.removeAll { $0.id == set.id }
        persist(current)
    }
    private func persist(_ updated: StrengthSession) {
        session = updated
        model.saveSession(updated)
    }
    private func finish() {
        guard var current = session else { return }
        // Sets left untouched are not part of what happened.
        current.sets.removeAll { !$0.completed }
        current.end = Date()
        model.saveSession(current)
        session = nil
        // Back to the strength screen rather than out of the sheet entirely:
        // the workout that was just finished is there, ready to be repeated.
        model.route = "strength"
    }
    private func discard() {
        guard let current = session else { return }
        model.deleteSession(current)
        session = nil
        model.route = "strength"
    }
}

/// One exercise inside a session: picture, name, what you did last time, and
/// the set rows.
private struct ExerciseBlock: View {
    var exercise: ExerciseDefinition?
    var fallbackName: String
    var sets: [StrengthSet]
    var previous: [StrengthSet]
    var onChange: (StrengthSet) -> Void
    var onAdd: () -> Void
    var onRemove: (StrengthSet) -> Void

    var body: some View {
        Card(spacing: 12) {
            HStack(spacing: 12) {
                if let exercise {
                    ExerciseThumbnail(exercise: exercise, size: 52)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise?.name ?? fallbackName).font(.subheadline.weight(.semibold))
                    if !previous.isEmpty {
                        Text(L("lastTime") + " " + previous.map { "\($0.reps)×\(number($0.weightKg, digits: 1))" }.joined(separator: "  "))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let exercise {
                        Text(L("muscle." + (exercise.primaryMuscles.first ?? "other")))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                // The set number needs no heading: the column is a list of 1, 2,
                // 3 and a word there only wraps.
                Spacer().frame(width: 26)
                Text(L("weightShort")).frame(maxWidth: .infinity)
                Text(L("repsShort")).frame(maxWidth: .infinity)
                Spacer().frame(width: 34)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).textCase(.uppercase)

            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRow(index: index + 1, set: set, onChange: onChange, onRemove: { onRemove(set) })
            }

            Button(action: onAdd) {
                Label(L("addSet"), systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppColors.surfaceRaised, in: Capsule())
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Weight, reps and a tick. Marking a set done is the action that matters, so
/// it is a big target and it lights up.
private struct SetRow: View {
    var index: Int
    var set: StrengthSet
    var onChange: (StrengthSet) -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(set.completed ? AppColors.accent : .secondary)
                .frame(width: 26, alignment: .leading)

            NumberField(value: Binding(
                get: { set.weightKg },
                set: { var copy = set; copy.weightKg = $0; onChange(copy) }
            ), decimals: true, identifier: "weight-\(index)")
            .frame(height: 36)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1) }

            NumberField(value: Binding(
                get: { Double(set.reps) },
                set: { var copy = set; copy.reps = max(0, Int($0.rounded())); onChange(copy) }
            ), decimals: false, identifier: "reps-\(index)")
            .frame(height: 36)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1) }

            Button {
                var copy = set
                copy.completed.toggle()
                onChange(copy)
            } label: {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.completed ? AppColors.accentVivid : AppColors.border)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("completeSet"))
            .accessibilityIdentifier("complete-\(index)")
        }
        .padding(.vertical, 2)
        .swipeActions { Button(L("delete"), role: .destructive, action: onRemove) }
        .contextMenu { Button(L("delete"), role: .destructive, action: onRemove) }
    }
}

/// A compact numeric field.
///
/// Tapping it selects everything, so typing replaces the number instead of
/// appending to it — with a set pre-filled from last time, appending is never
/// what you meant, and in a gym you are not going to fight a cursor.
private struct NumberField: UIViewRepresentable {
    @Binding var value: Double
    var decimals: Bool
    var identifier: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = decimals ? .decimalPad : .numberPad
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        field.placeholder = "0"
        field.accessibilityIdentifier = identifier
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.value = $value
        // Never fight the keyboard: while the field is being edited its text
        // belongs to the person typing.
        guard !field.isFirstResponder else { return }
        field.text = value == 0 ? "" : NumberField.format(value, decimals: decimals)
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    static func format(_ value: Double, decimals: Bool) -> String {
        let fractional = value.truncatingRemainder(dividingBy: 1) != 0
        return number(value, digits: decimals && fractional ? 1 : 0)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }

        func textFieldDidBeginEditing(_ field: UITextField) {
            DispatchQueue.main.async { field.selectAll(nil) }
        }
        @objc func changed(_ field: UITextField) {
            let text = (field.text ?? "").replacingOccurrences(of: ",", with: ".")
            value.wrappedValue = Double(text) ?? 0
        }
    }
}

// MARK: - Library

/// The catalogue, browsed by picture. Names are hard to scan and easy to
/// confuse; the drawing is recognised instantly, which is the whole point of
/// having shipped 268 of them.
struct ExerciseLibraryView: View {
    @Environment(AppModel.self) private var model
    var onSelect: ((ExerciseDefinition) -> Void)?
    @State private var search = ""
    @State private var group: String?
    @State private var equipment: String?

    private var filtered: [ExerciseDefinition] {
        model.exercises.filter { exercise in
            (group == nil || exercise.group == group)
            && (equipment == nil || exercise.equipment == equipment)
            && (search.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(search)
                || exercise.englishName.localizedCaseInsensitiveContains(search))
        }
    }
    private var equipmentOptions: [String] {
        Array(Set(model.exercises.map(\.equipment))).sorted()
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filters
                Text("\(filtered.count) " + L("exercises"))
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { exercise in
                        tile(exercise)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .searchable(text: $search, prompt: L("searchExercise"))
        .navigationTitle(L("exerciseLibrary"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(L("all"), symbol: nil, active: group == nil) { group = nil }
                    ForEach(ExerciseVocabulary.groups, id: \.self) { key in
                        chip(L("group." + key), symbol: ExerciseVocabulary.groupSymbol(key), active: group == key) {
                            group = group == key ? nil : key
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(L("anyEquipment"), symbol: nil, active: equipment == nil) { equipment = nil }
                    ForEach(equipmentOptions, id: \.self) { key in
                        chip(L("equipment." + key), symbol: ExerciseVocabulary.equipmentSymbol(key), active: equipment == key) {
                            equipment = equipment == key ? nil : key
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func chip(_ title: String, symbol: String?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption2) }
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(active ? AppColors.accent : AppColors.surfaceRaised, in: Capsule())
            .foregroundStyle(active ? AppColors.background : AppColors.ink)
            .overlay { Capsule().strokeBorder(active ? .clear : AppColors.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ exercise: ExerciseDefinition) -> some View {
        Group {
            if let onSelect {
                Button { onSelect(exercise) } label: { card(exercise) }.buttonStyle(.plain)
            } else {
                NavigationLink { ExerciseDetailView(exercise: exercise) } label: { card(exercise) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func card(_ exercise: ExerciseDefinition) -> some View {
        VStack(spacing: 6) {
            ExerciseArtView(exercise: exercise, tint: AppColors.ink.opacity(0.85))
                .padding(8)
                .frame(height: 86)
            Text(exercise.name)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(8)
        .frame(height: 158, alignment: .top)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

/// One exercise in full: the movement animated between its two frames, what it
/// works, and what you have lifted on it.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    var exercise: ExerciseDefinition

    private var best: StrengthSet? { StrengthHistoryEngine.best(exercise: exercise.id, in: model.sessions) }
    private var last: [StrengthSet] { StrengthHistoryEngine.lastSets(exercise: exercise.id, in: model.sessions) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    ExerciseArtView(exercise: exercise, tint: AppColors.ink.opacity(0.88), animated: true)
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                    Text(exercise.name).font(.title3.weight(.bold))
                    if !exercise.englishName.isEmpty {
                        Text(exercise.englishName).font(.caption).foregroundStyle(.secondary)
                    }
                    FlowRow(spacing: 6) {
                        tag(L("group." + exercise.group), symbol: ExerciseVocabulary.groupSymbol(exercise.group))
                        tag(L("equipment." + exercise.equipment), symbol: ExerciseVocabulary.equipmentSymbol(exercise.equipment))
                        if exercise.compound { tag(L("compound"), symbol: "arrow.triangle.merge") }
                        if exercise.unilateral { tag(L("unilateral"), symbol: "arrow.left.and.right") }
                    }
                }
                if !exercise.primaryMuscles.isEmpty || !exercise.secondaryMuscles.isEmpty {
                    Card(spacing: 10) {
                        Label(L("muscles"), systemImage: "figure.arms.open").font(AppTypography.cardTitle)
                        if !exercise.primaryMuscles.isEmpty {
                            muscleRow(L("primaryMuscles"), exercise.primaryMuscles, tint: AppColors.accent)
                        }
                        if !exercise.secondaryMuscles.isEmpty {
                            muscleRow(L("secondaryMuscles"), exercise.secondaryMuscles, tint: .secondary)
                        }
                    }
                }
                if best != nil || !last.isEmpty {
                    Card(spacing: 10) {
                        Label(L("yourNumbers"), systemImage: "chart.line.uptrend.xyaxis").font(AppTypography.cardTitle)
                        if let best {
                            ValueRow(title: "bestSet", value: "\(best.reps) × " + number(best.weightKg, digits: 1) + " kg")
                            if let oneRM = StrengthEngine.estimated1RM(weight: best.weightKg, reps: best.reps) {
                                ValueRow(title: "estimated1RM", value: number(oneRM, digits: 1) + " kg")
                            }
                        }
                        if !last.isEmpty {
                            ValueRow(title: "lastTime", value: last.map { "\($0.reps)×\(number($0.weightKg, digits: 1))" }.joined(separator: "  "))
                        }
                    }
                }
                if !exercise.steps.isEmpty {
                    Card(spacing: 10) {
                        Label(L("howToDoIt"), systemImage: "list.number").font(AppTypography.cardTitle)
                        ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(AppColors.accent).frame(width: 16, alignment: .trailing)
                                Text(step).font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(L("instructionsSource")).font(.caption2).foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadExercises() }
    }

    private func muscleRow(_ title: String, _ muscles: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            FlowRow(spacing: 6) {
                ForEach(muscles, id: \.self) { muscle in
                    Text(L("muscle." + muscle))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(AppColors.surfaceRaised, in: Capsule())
                        .foregroundStyle(tint)
                }
            }
        }
    }

    private func tag(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2)
            Text(title).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(AppColors.accentSoft, in: Capsule())
        .foregroundStyle(AppColors.accent)
    }
}

// MARK: - Routines and history

/// Building a routine: pick exercises, say how many sets, save. The previous
/// editor listed exercise ids with no way to set anything.
struct RoutineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var template: WorkoutTemplate?
    @State private var name = ""
    @State private var sets: [StrengthSet] = []
    @State private var picking = false
    @State private var loaded = false

    private var order: [String] {
        var seen: [String] = []
        for set in sets where !seen.contains(set.exerciseID) { seen.append(set.exerciseID) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card(spacing: 10) {
                    Text(L("routineName")).font(.caption).foregroundStyle(.secondary)
                    TextField(L("routineNamePlaceholder"), text: $name)
                        .font(.title3.weight(.semibold))
                }
                ForEach(order, id: \.self) { id in
                    let count = sets.filter { $0.exerciseID == id }.count
                    Card(spacing: 12) {
                        HStack(spacing: 12) {
                            if let exercise = model.exercise(id) {
                                ExerciseThumbnail(exercise: exercise, size: 48)
                            }
                            Text(model.exercise(id)?.name ?? id).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button { sets.removeAll { $0.exerciseID == id } } label: {
                                Image(systemName: "trash").font(.caption)
                            }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                        Stepper("\(count) " + L("series"), value: Binding(
                            get: { count },
                            set: { newValue in
                                let current = sets.filter { $0.exerciseID == id }.count
                                if newValue > current {
                                    let reference = sets.last { $0.exerciseID == id } ?? StrengthSet(exerciseID: id)
                                    for _ in 0..<(newValue - current) {
                                        var copy = reference; copy.id = UUID()
                                        if let index = sets.lastIndex(where: { $0.exerciseID == id }) {
                                            sets.insert(copy, at: index + 1)
                                        } else { sets.append(copy) }
                                    }
                                } else if newValue < current {
                                    for _ in 0..<(current - newValue) {
                                        if let index = sets.lastIndex(where: { $0.exerciseID == id }) { sets.remove(at: index) }
                                    }
                                }
                            }
                        ), in: 1...10)
                        .font(.subheadline)
                    }
                }
                Button { picking = true } label: {
                    Label(L("addExercise"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(AppColors.accent)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L(template == nil ? "createRoutine" : "editRoutine"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let template else { loaded = true; return }
            name = template.name
            sets = template.sets
            loaded = true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("save")) {
                    var saved = WorkoutTemplate(name: name, sets: sets)
                    if let template { saved.id = template.id }
                    model.saveTemplate(saved)
                    dismiss()
                }
                .disabled(name.isEmpty || sets.isEmpty)
            }
            if template != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(L("delete"), role: .destructive) {
                        if let template { model.deleteTemplate(template) }
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                ExerciseLibraryView { exercise in
                    // Three sets is the usual starting point, and it is easier
                    // to remove one than to add three.
                    for _ in 0..<3 { sets.append(StrengthSet(exerciseID: exercise.id)) }
                    picking = false
                }
            }
        }
    }
}

struct SessionHistoryView: View {
    @Environment(AppModel.self) private var model
    private var finished: [StrengthSession] {
        model.sessions.filter { $0.end != nil }.sorted { $0.start > $1.start }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(finished) { session in
                    NavigationLink { SessionDetail(session: session) } label: {
                        Card(spacing: 8) {
                            HStack {
                                Text(session.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(session.start.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                Text("\(session.exerciseOrder.count) " + L("exercises"))
                                Text("\(session.sets.count) " + L("series"))
                                Text(number(StrengthHistoryEngine.volume(session.sets)) + " kg")
                                Text(duration(session.minutes))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L("history"))
        .task { await model.loadExercises() }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: StrengthSession
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(session.exerciseOrder, id: \.self) { id in
                    Card(spacing: 10) {
                        HStack(spacing: 12) {
                            if let exercise = model.exercise(id) {
                                ExerciseThumbnail(exercise: exercise, size: 46)
                            }
                            Text(model.exercise(id)?.name ?? id).font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        ForEach(Array(session.sets.filter { $0.exerciseID == id }.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("\(index + 1)").font(.caption.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                                Text("\(set.reps) × " + number(set.weightKg, digits: 1) + " kg")
                                    .font(.subheadline).monospacedDigit()
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadExercises() }
    }
}

struct PlateCalculatorView: View {
    @State private var total = 60.0
    @State private var bar = 20.0
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card(spacing: 12) {
                    Label(L("plateCalculator"), systemImage: "circle.grid.cross").font(AppTypography.cardTitle)
                    HStack {
                        Text(L("totalWeight")).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", value: $total, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .font(.title3.weight(.bold)).monospacedDigit().frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    Picker(L("barWeight"), selection: $bar) {
                        ForEach([20.0, 15.0, 10.0, 7.5], id: \.self) { Text(number($0, digits: 1) + " kg").tag($0) }
                    }.pickerStyle(.segmented)
                }
                let result = StrengthEngine.plates(total: total, bar: bar)
                Card(spacing: 10) {
                    Text(L("perSide")).font(.caption).foregroundStyle(.secondary)
                    if result.plates.isEmpty {
                        Text(L("justTheBar")).font(.subheadline)
                    } else {
                        FlowRow(spacing: 8) {
                            ForEach(Array(result.plates.enumerated()), id: \.offset) { _, plate in
                                Text(number(plate, digits: 2))
                                    .font(.subheadline.weight(.bold)).monospacedDigit()
                                    .frame(width: 54, height: 54)
                                    .background(AppColors.accentSoft, in: Circle())
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    if result.remainder > 0.01 {
                        Text(L("plateRemainder") + " " + number(result.remainder, digits: 2) + " kg")
                            .font(.caption).foregroundStyle(AppColors.warn)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .pulsePage()
        .navigationTitle(L("plateCalculator"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
