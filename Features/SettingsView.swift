import SwiftUI
import PulseCore

/// A settings row that reads at a glance: coloured symbol, title, optional
/// current value. The previous screen was one flat `Form` of dense sections
/// with no symbols, which made everything look equally important.
struct SettingsRow<Destination: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    var value: String? = nil
    @ViewBuilder var destination: Destination
    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(L(title))
                Spacer(minLength: 8)
                if let value { Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                SettingsRow(title: "health", symbol: "heart.fill", tint: .pink,
                            value: model.preferences.healthConnected ? L("connected") : L("notConnected")) { HealthSettingsView() }
                SettingsRow(title: "appleWatch", symbol: "applewatch", tint: .gray,
                            value: model.connectivity.reachable ? L("connected") : nil) { WatchSettingsView() }
            }
            Section {
                SettingsRow(title: "profileAndGoals", symbol: "person.fill", tint: AppColors.accent) { ProfileSettingsView() }
                SettingsRow(title: "appearance", symbol: "paintbrush.fill", tint: .indigo,
                            value: L(model.preferences.darkMode)) { AppearanceSettingsView() }
                SettingsRow(title: "notifications", symbol: "bell.fill", tint: .orange) { CheckinView() }
            }
            Section {
                SettingsRow(title: "dataAndPrivacy", symbol: "lock.fill", tint: .blue) { DataSettingsView() }
                SettingsRow(title: "diagnostics", symbol: "stethoscope", tint: .teal,
                            value: "\(model.history.count) " + L("days")) { DiagnosticsView() }
                SettingsRow(title: "about", symbol: "info.circle.fill", tint: .secondary) { AboutView() }
            }
        }
        .scrollContentBackground(.hidden)
        .pulsePage()
        .navigationTitle(L("settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.savePreferences() }
    }
}

struct HealthSettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.preferences.healthConnected {
                    LabeledContent(L("status")) { Label(L("connected"), systemImage: "checkmark.circle.fill").foregroundStyle(AppColors.accent) }
                } else {
                    Button(L("connectHealth")) { Task { await model.connectHealth() } }
                }
                LabeledContent(L("lastSync"), value: model.preferences.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                Button(L("syncNow")) { Task { await model.sync() } }.disabled(model.syncing)
            } header: { Text(L("appleHealth")) } footer: { Text(L("healthConnectionDetail")) }

            Section(L("sync")) {
                Picker(L("autoSync"), selection: $model.preferences.autoSyncMinutes) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker(L("importHistory"), selection: $model.preferences.importDays) {
                    ForEach([30, 90, 180, 365], id: \.self) { Text("\($0) " + L("days")).tag($0) }
                }
            }

            Section {
                TextField(L("sleepSourceIdentifier"), text: $model.preferences.sleepSource)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            } header: { Text(L("sleepSource")) } footer: { Text(L("sleepSourceDetail")) }

            Section {
                Toggle(L("writeHealth"), isOn: $model.preferences.writeHealth)
            } footer: { Text(L("writeHealthDetail")) }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("healthAndSync"))
        .onDisappear { model.savePreferences() }
    }
}

/// One place per value, editable where it is shown. The previous version
/// printed a read-only age at the top and hid the date picker that controls it
/// in a separate section further down, offered no way to set biological sex at
/// all, and had a "refresh from Health" button that silently did nothing
/// whenever a value was already present.
struct ProfileSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importResult: AppModel.CharacteristicsResult?
    @State private var importing = false

    private var age: Double? { WellnessAgeEngine.age(from: model.preferences.birthDate) }
    /// The most recent sample Health has for a measurement. Weight and height
    /// are readings, not settings: they are changed on the scale, not here.
    private func latest(_ key: String) -> Vital? {
        model.history.flatMap(\.vitals).last { $0.id == key }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                DatePicker(selection: Binding(
                    get: { model.preferences.birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date() },
                    set: { model.preferences.birthDate = $0; model.savePreferences() }
                ), in: ...Date(), displayedComponents: .date) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("birthDate"))
                        // The age lives with the control that sets it rather
                        // than in a separate read-only row.
                        Text(age.map { number($0) + " " + L("years") } ?? L("notSet"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Picker(selection: Binding(
                    get: { model.preferences.biologicalSex ?? "unset" },
                    set: { model.preferences.biologicalSex = $0 == "unset" ? nil : $0; model.savePreferences() }
                )) {
                    Text(L("notSet")).tag("unset")
                    Text(L("female")).tag("female")
                    Text(L("male")).tag("male")
                    Text(L("other")).tag("other")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("biologicalSex"))
                        Text(L("biologicalSexUse")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("profile"))
            } footer: {
                Text(L("profileEditableDetail"))
            }

            Section {
                Button {
                    importing = true
                    Task {
                        importResult = await model.importCharacteristics(overwrite: true)
                        importing = false
                    }
                } label: {
                    HStack {
                        Label(L("refreshFromHealth"), systemImage: "arrow.clockwise")
                        Spacer()
                        if importing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(importing)

                if let importResult {
                    switch importResult {
                    case .updated:
                        Label(L("profileImported"), systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(AppColors.accent)
                    case .alreadyCurrent:
                        Label(L("profileAlreadyCurrent"), systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    case .unavailable:
                        // Saying so beats a button that appears to do nothing.
                        Label(L("profileNothingInHealth"), systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(AppColors.warn)
                    }
                }
            } footer: {
                Text(L("profileFromHealthDetail"))
            }

            Section {
                LabeledContent(L("weight"), value: latest("weight").map { number($0.value, digits: 1) + " kg" } ?? "—")
                LabeledContent(L("height"), value: latest("height").map { number($0.value, digits: 2) + " m" } ?? "—")
                NavigationLink(L("bodyComposition")) { BodyView() }
            } header: {
                Text(L("measurements"))
            } footer: {
                Text(L("measurementsDetail"))
            }

            Section(L("goals")) {
                Stepper(value: $model.preferences.baseSleep, in: 360...600, step: 15) {
                    LabeledContent(L("sleepNeed"), value: duration(model.preferences.baseSleep))
                }
                LabeledContent(L("maximumHR")) {
                    TextField("bpm", value: $model.preferences.maximumHR, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker(L("status"), selection: $model.preferences.status) {
                    ForEach(["active", "sick", "injured", "break"], id: \.self) { Text(L($0)).tag($0) }
                }
            } footer: { Text(L("statusDetail")) }

            Section {
                Toggle(L("enableCycle"), isOn: $model.preferences.cycle)
                if model.preferences.cycle { NavigationLink(L("cycle")) { CycleView() } }
            } footer: { Text(L("cycleDisclaimer")) }
        }
        .scrollContentBackground(.hidden).pulsePage()
        .navigationTitle(L("profileAndGoals"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.importCharacteristics() }
        .onDisappear {
            model.preferences.maximumHR = Statistics.clamp(model.preferences.maximumHR, 100, 240)
            model.savePreferences()
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Picker(L("theme"), selection: $model.preferences.darkMode) {
                ForEach(["system", "light", "dark"], id: \.self) { Text(L($0)).tag($0) }
            }.pickerStyle(.inline)
            Picker(L("language"), selection: $model.preferences.language) {
                Text("Español").tag("es"); Text("English").tag("en")
            }.onChange(of: model.preferences.language) { _, value in
                UserDefaults.standard.set(value, forKey: "appLanguage")
            }
            Toggle(L("imperial"), isOn: $model.preferences.imperial)
            NavigationLink(L("editHome")) { HomeCustomization() }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("appearance"))
        .onDisappear { model.savePreferences() }
    }
}

struct WatchSettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section(L("connection")) {
                LabeledContent(L("status"), value: L(model.connectivity.reachable ? "connected" : "notConnected"))
                LabeledContent(L("lastWatchSync"), value: model.connectivity.lastReceived?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                Button(L("resendToWatch")) { model.publish() }
            }
            Section { NavigationLink(L("smartAlarm")) { AlarmView() } } footer: { Text(L("watchAlarmDetail")) }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("appleWatch"))
    }
}

struct DataSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section(L("export")) {
                Button { model.perform { exportURL = try model.export(csv: false) } } label: { Label(L("exportJSON"), systemImage: "curlybraces") }
                Button { model.perform { exportURL = try model.export(csv: true) } } label: { Label(L("exportCSV"), systemImage: "tablecells") }
                if let exportURL { ShareLink(item: exportURL) { Label(L("shareExport"), systemImage: "square.and.arrow.up") } }
            }
            Section { Text(L("privacyDetail")).font(.footnote).foregroundStyle(.secondary) }
            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label(L("deleteLocalData"), systemImage: "trash") }
            }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("dataAndPrivacy"))
        .confirmationDialog(L("deleteDataConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("deleteLocalData"), role: .destructive) { model.deleteLocalData(); model.route = nil }
            Button(L("cancel"), role: .cancel) {}
        } message: { Text(L("deleteDataDetail")) }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section { VStack(spacing: 10) { VeyraBrandMark(); Text("1.0.0").font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            Section { Text(L("independentApp")).font(.footnote).foregroundStyle(.secondary) }
            Section(L("connections")) {
                ForEach(["Apple Health", "Oura", "Strava", "Garmin", "Withings"], id: \.self) { provider in
                    LabeledContent(provider, value: L(provider == "Apple Health" ? "integrated" : "viaAppleHealth"))
                }
            }
            Section { Text(L("externalConnectionDetail")).font(.footnote).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("about"))
    }
}

struct HomeCustomization: View {
    @Environment(AppModel.self) private var model
    private let cards = ["health", "stress", "energy", "activity", "journal"]
    var body: some View {
        List {
            Section(L("visibleCards")) {
                ForEach(model.preferences.enabledCards, id: \.self) { Text(L($0)) }
                    .onMove { model.preferences.enabledCards.move(fromOffsets: $0, toOffset: $1); model.savePreferences() }
                    .onDelete { model.preferences.enabledCards.remove(atOffsets: $0); model.savePreferences() }
            }
            Section(L("hiddenCards")) {
                ForEach(cards.filter { !model.preferences.enabledCards.contains($0) }, id: \.self) { card in
                    Button { model.preferences.enabledCards.append(card); model.savePreferences() } label: { Label(L(card), systemImage: "plus.circle") }
                }
            }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("editHome")).toolbar { EditButton() }
    }
}

struct AlarmView: View {
    @Environment(AppModel.self) private var model
    @State private var time = Date()
    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(L("enableAlarm"), isOn: $model.preferences.alarm.enabled)
                DatePicker(L("wakeTime"), selection: $time, displayedComponents: .hourAndMinute)
                    .onChange(of: time) { _, time in
                        model.preferences.alarm.hour = Calendar.current.component(.hour, from: time)
                        model.preferences.alarm.minute = Calendar.current.component(.minute, from: time)
                    }
            }
            Section {
                Picker(L("smartWindow"), selection: $model.preferences.alarm.windowMinutes) {
                    ForEach([0, 15, 20, 30], id: \.self) { Text($0 == 0 ? L("off") : "\($0) min").tag($0) }
                }
                Picker(L("snooze"), selection: $model.preferences.alarm.snoozeMinutes) {
                    ForEach([0, 5, 10], id: \.self) { Text($0 == 0 ? L("off") : "\($0) min").tag($0) }
                }
            } footer: { Text(L("watchAlarmDetail")) }
            Section {
                Button(L("syncAlarm")) { model.savePreferences() }
                LabeledContent(L("lastWatchSync"), value: model.connectivity.lastReceived?.formatted(date: .abbreviated, time: .shortened) ?? L("unavailable"))
            }
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("smartAlarm"))
        .onAppear { time = Calendar.current.date(bySettingHour: model.preferences.alarm.hour, minute: model.preferences.alarm.minute, second: 0, of: Date()) ?? Date() }
        .onDisappear { model.savePreferences() }
    }
}

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section {
                LabeledContent(L("dailySummaries"), value: "\(model.history.count)")
                LabeledContent(L("algorithmVersion"), value: "\(DailyEngine.algorithmVersion)")
                LabeledContent(L("schemaVersion"), value: "1.0.0")
                LabeledContent(L("lastSync"), value: model.preferences.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                LabeledContent(L("lastWatchSync"), value: model.connectivity.lastReceived?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            }
            Section(L("latestSamples")) {
                ForEach(model.currentSnapshot?.vitals ?? []) { vital in
                    LabeledContent(L(vital.id), value: vital.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Button(L("recalculate7")) { Task { await model.sync(force: true, days: 7) } }
                Button(L("recalculate30")) { Task { await model.sync(force: true, days: 30) } }
                Button(L("rebuildCache")) { Task { await model.sync(force: true) } }
            }.disabled(model.syncing)
        }
        .scrollContentBackground(.hidden).pulsePage().navigationTitle(L("diagnostics"))
    }
}
