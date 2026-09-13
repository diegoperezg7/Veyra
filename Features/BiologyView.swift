import SwiftUI
import Charts
import UniformTypeIdentifiers
import PulseCore
struct BiologyView: View {
    @Environment(AppModel.self) private var model
    var body: some View { ScrollView { VStack(spacing: 18) {
        NavigationLink { WellnessAgeView() } label: { WellnessAgeHeadline() }.buttonStyle(.plain)
        BiologyHero(vitals: [latest("hrv"), latest("rhr"), latest("oxygen"), latest("respiratory")].compactMap { $0 })
        NavigationLink { BodyView() } label: { BodyCompositionCard(weight: latest("weight"), bodyFat: latest("bodyFat"), leanMass: latest("leanMass"), bmi: latest("bmi"), waist: latest("waist")) }.buttonStyle(.plain)
        Card { Text(L("healthMonitor")).font(AppTypography.cardTitle); ForEach(["hrv", "rhr", "respiratory", "temperature", "oxygen", "vo2", "glucose", "systolic", "diastolic"], id: \.self) { key in NavigationLink { VitalDetailView(key: key) } label: { ValueRow(title: key, value: latest(key).map { number($0.value, digits: 1) + " " + $0.unit } ?? "—", symbol: vitalSymbol(key)) }.buttonStyle(.plain) }; Text(L("latestAvailableDetail")).font(.caption).foregroundStyle(.secondary) }
        if !screening.isEmpty { ScreeningCard(signals: screening) }
        Card(accent: AppColors.accent) { VStack(alignment: .leading, spacing: 10) { Label(L("dataSources"), systemImage: "arrow.triangle.2.circlepath").font(AppTypography.cardTitle); Text(L("scalesDetail")).font(.subheadline).foregroundStyle(.secondary); Label("Apple Health", systemImage: "checkmark.circle").font(.caption).foregroundStyle(AppColors.accent); Text(L("scalesReadOnly")).font(.caption).foregroundStyle(.secondary); Button { Task { await model.connectHealth() } } label: { Label(model.syncing ? L("connecting") : L("syncNow"), systemImage: model.syncing ? "hourglass" : "arrow.clockwise") }.buttonStyle(.borderedProminent).tint(AppColors.accent).disabled(model.syncing) } }
        Button { model.route = "documents" } label: { Card { SectionTitle(title: "healthRecords", symbol: "doc.text"); Text(L("healthRecordsDetail")).font(.subheadline).foregroundStyle(.secondary); Text("\(model.documents.count) " + L("documents")).font(.caption) } }.buttonStyle(.plain)
        Button { model.route = "cycle" } label: { Card { SectionTitle(title: "cycle", symbol: "circle.dotted"); Text(L(model.preferences.cycle ? "cycleEnabled" : "cycleOptional")).font(.subheadline).foregroundStyle(.secondary) } }.buttonStyle(.plain)
    }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24) }.pulsePage().navigationTitle(L("biology")).navigationBarTitleDisplayMode(.inline) }
    private func latest(_ key: String) -> Vital? { model.latestVital(key) }
    /// Readings that carry a published reference band. Built from whatever the
    /// history holds, so the card only appears once something can be said.
    private var screening: [ScreeningSignal] {
        ScreeningSignals.build(history: model.history, vitals: model.vitalSeries, birthDate: model.preferences.birthDate, sex: model.preferences.biologicalSex)
    }
    private func vitalSymbol(_ key: String) -> String { switch key { case "hrv", "rhr": "heart"; case "respiratory", "oxygen": "lungs"; case "temperature": "thermometer.medium"; default: "waveform.path" } }
}

/// The headline of the Biology tab. The wellness age is the number the user
/// actually comes here for, so it leads the screen instead of sitting in a
/// small link at the bottom.
struct WellnessAgeHeadline: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let estimate = model.wellnessAge
        Card(scene: .recovery, accent: .purple) {
            HStack {
                Label(L("wellnessAge"), systemImage: "sparkles").font(AppTypography.cardTitle)
                Spacer()
                if let estimate { ConfidenceBadge(percent: estimate.report.percent, compact: true, onScene: true) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.5)
            }
            if let estimate {
                BiologicalAgeHeadline(estimate: estimate, onScene: true)
                if let fitness = estimate.fitnessAge {
                    Text(L("fitnessAge") + ": " + number(fitness, digits: 0) + " " + L("years"))
                        .font(.caption).opacity(0.85)
                }
            } else {
                Text(L("calibrating")).font(.system(size: 36, weight: .bold))
                Text(L(model.preferences.birthDate == nil ? "wellnessAgeNeedsBirthDate" : "wellnessAgeNeedsSignal"))
                    .font(.footnote).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { model.recalibrateWellnessAge() }
    }
}

private struct BiologyHero: View {
    let vitals: [Vital]
    var body: some View {
        // Plain surface: the wellness-age card directly above already carries a
        // photograph, and two scenes in a row read as wallpaper.
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("todayReading"), systemImage: "waveform.path.ecg.rectangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppColors.accent)
                    Text(L("vitalsWithContext")).font(AppTypography.cardTitle)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(vitals.prefix(4)) { vital in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(vital.id)).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(number(vital.value, digits: vital.id == "respiratory" ? 1 : 0))
                            .font(.title3.weight(.bold)).monospacedDigit()
                        Text(vital.unit).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppColors.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
                }
            }
            Text(L("vitalsLatestDetail")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BodyCompositionCard: View {
    let weight: Vital?
    let bodyFat: Vital?
    let leanMass: Vital?
    let bmi: Vital?
    let waist: Vital?
    var body: some View {
        Card(accent: Color(red: 0.28, green: 0.60, blue: 0.92)) {
            HStack {
                Label(L("bodyComposition"), systemImage: "figure.stand").font(AppTypography.cardTitle)
                Spacer()
                Text("Apple Health").font(.caption2.weight(.semibold)).foregroundStyle(AppColors.accent).padding(.horizontal, 9).padding(.vertical, 5).background(AppColors.accent.opacity(0.10), in: Capsule())
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                composition("weight", weight)
                composition("bodyFat", bodyFat)
                composition("leanMass", leanMass)
                composition("bmi", bmi)
            }
            if let waist { ValueRow(title: "waist", value: number(waist.value, digits: 2) + " " + waist.unit, symbol: "ruler") }
            Text(L("scalesSetup")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func composition(_ key: String, _ vital: Vital?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(key)).font(.caption).foregroundStyle(.secondary)
            Text(vital.map { number($0.value, digits: 1) } ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
            Text(vital?.unit ?? "").font(.caption2).foregroundStyle(AppColors.accent)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(AppColors.accent.opacity(0.065), in: .rect(cornerRadius: 16))
    }
}
struct VitalDetailView: View {
    @Environment(AppModel.self) private var model
    var key: String
    @State private var range = 30
    var body: some View {
        let values = model.vitalSeries[key] ?? []
        let points = values.suffix(range)
        let spread = (points.map(\.value).max() ?? 1) - (points.map(\.value).min() ?? 0)
        let padding = max(abs(spread) * 0.25, max(abs(points.last?.value ?? 1) * 0.04, 0.5))
        let lower = max(0, (points.map(\.value).min() ?? 0) - padding)
        let upper = (points.map(\.value).max() ?? 1) + padding
        let baseline = BaselineEngine.calculate(Array(values.dropLast().suffix(42)).map(\.value))
        ScrollView { VStack(spacing: 18) { Card { Text(number(values.last?.value, digits: 1)).font(AppTypography.score); Text(values.last?.unit ?? "").foregroundStyle(.secondary); if let date = values.last?.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; ValueRow(title: "baseline", value: number(baseline?.median, digits: 1)); if let baseline, let last = values.last { ValueRow(title: "deviation", value: number(last.value - baseline.median, digits: 1)) } }
            Card { Picker(L("range"), selection: $range) { Text("7D").tag(7); Text("30D").tag(30); Text("3M").tag(90); Text("1Y").tag(365) }.pickerStyle(.segmented); HealthTrendChart(points: points.map { TimelinePoint(date: $0.date, value: $0.value) }, metric: .recovery, height: 230, maximumGap: 3 * 86400, yDomain: lower...upper) }
            if ["bodyFat", "leanMass", "weight"].contains(key), let prediction = TrendEngine.projection(values.map { .init(date: $0.date, value: $0.value) }) { Card { ValueRow(title: "projection30", value: number(prediction, digits: 1) + " " + (values.last?.unit ?? "")); Text(L("projectionDetail")).font(.caption).foregroundStyle(.secondary) } }
        }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24) }.pulsePage().navigationTitle(L(key))
    }
}
/// A wellness-age estimate from the first day onward. It used to refuse to say
/// anything until fourteen days of sleep and steps existed, which meant a new
/// user saw only a placeholder; the uncertainty is now carried by the
/// confidence percentage and the plausible range instead of by silence.
/// The estimate is stored and recalibrated weekly, not recomputed on every
/// redraw, so the number the user sees is stable between recalibrations. A
/// button forces one when they want it sooner.
struct WellnessAgeView: View {
    @Environment(AppModel.self) private var model
    @State private var justRecalibrated = false
    var body: some View {
        let estimate = model.wellnessAge
        ScrollView {
            VStack(spacing: 18) {
                Card(scene: .recovery, accent: .purple) {
                    HStack {
                        Label(L("experimentalEstimate"), systemImage: "sparkles").font(.caption.weight(.semibold))
                        Spacer()
                        if let estimate { ConfidenceBadge(percent: estimate.report.percent, onScene: true) }
                    }
                    if let estimate {
                        BiologicalAgeHeadline(estimate: estimate, onScene: true)
                    } else {
                        Text(L("calibrating")).font(.system(size: 38, weight: .bold))
                        Text(L(model.preferences.birthDate == nil ? "wellnessAgeNeedsBirthDate" : "wellnessAgeNeedsSignal"))
                            .font(.footnote).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let estimate {
                    Card {
                        Text(L("whereYouSit")).font(AppTypography.cardTitle)
                        BiologicalAgeChart(estimate: estimate)
                        Text(L("wellnessAgeRange")
                                .replacingOccurrences(of: "{0}", with: number(estimate.range.lowerBound, digits: 1))
                                .replacingOccurrences(of: "{1}", with: number(estimate.range.upperBound, digits: 1)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let fitness = estimate.fitnessAge {
                        let vo2 = estimate.contributors.first { $0.id == "vo2" }?.value
                        let saturated = vo2.map { WellnessAgeEngine.fitnessAgeSaturates(vo2: $0, sex: model.preferences.biologicalSex) } ?? false
                        Card {
                            HStack {
                                Label(L("fitnessAge"), systemImage: "lungs.fill").font(AppTypography.cardTitle)
                                Spacer()
                                Text((saturated ? "≤ " : "") + number(fitness, digits: 0) + " " + L("years"))
                                    .font(.headline).monospacedDigit()
                                    .foregroundStyle(AppColors.ageTint(fitness - estimate.chronologicalAge))
                            }
                            if let vo2 {
                                ValueRow(title: "vo2", value: number(vo2, digits: 1) + " ml/kg/min", symbol: "lungs")
                                if let expected = WellnessAgeEngine.expectedVO2(age: estimate.chronologicalAge, sex: model.preferences.biologicalSex) {
                                    ValueRow(title: "expectedForYourAge", value: number(expected, digits: 1) + " ml/kg/min")
                                }
                            }
                            Text(L(saturated ? "fitnessAgeSaturated" : "fitnessAgeDetail"))
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Card {
                    HStack {
                        Label(L("recalibrate"), systemImage: "arrow.clockwise").font(AppTypography.cardTitle)
                        Spacer()
                        if justRecalibrated {
                            Label(L("updated"), systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppColors.accent)
                        }
                    }
                    if let estimate {
                        ValueRow(title: "lastCalibration", value: estimate.date.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let next = model.nextWellnessAgeDate {
                        ValueRow(title: "nextCalibration", value: next.formatted(date: .abbreviated, time: .omitted))
                    }
                    Text(L("recalibrateDetail")).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        justRecalibrated = model.recalibrateWellnessAge(force: true)
                    } label: {
                        Label(L("recalibrateNow"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(AppColors.accentVivid)
                    .disabled(model.preferences.birthDate == nil)
                }

                if model.wellnessAges.count >= 2 {
                    Card {
                        Text(L("wellnessAgeHistory")).font(AppTypography.cardTitle)
                        HealthTrendChart(
                            points: model.wellnessAges.map { TimelinePoint(date: $0.date, value: $0.age) },
                            metric: .recovery, height: 150, maximumGap: 40 * 86_400,
                            yDomain: yDomain, showsReferenceBand: false
                        )
                    }
                }

                if model.preferences.birthDate == nil {
                    Card {
                        Label(L("birthDate"), systemImage: "calendar").font(AppTypography.cardTitle)
                        Text(L("birthDateDetail")).font(.footnote).foregroundStyle(.secondary)
                        Button(L("profileAndGoals")) { model.route = "settings" }
                            .buttonStyle(.bordered).tint(AppColors.accent)
                    }
                }

                // What each signal is doing to the number, in years. This
                // replaced a card that listed each signal's raw reading in
                // years: those did not add up to the difference from your real
                // age, so they could not explain it.
                if let estimate {
                    Card(spacing: 12) {
                        Label(L("whatMovesYourAge"), systemImage: "arrow.up.arrow.down")
                            .font(AppTypography.cardTitle)
                        if let effects = estimate.effects, !effects.isEmpty {
                            ForEach(effects) { effect in
                                AgeEffectRow(effect: effect)
                                if effect.id != effects.last?.id { Divider().overlay(AppColors.divider) }
                            }
                            Text(L("whatMovesYourAgeDetail")).font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(estimate.contributors) { contributor in
                                AgeSignalRow(contributor: contributor)
                            }
                        }
                        ForEach(estimate.report.limitations, id: \.self) { limitation in
                            Label(L(limitation), systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Card {
                    Label(L("aboutMetric"), systemImage: "info.circle").font(.subheadline.weight(.medium))
                    Text(L("wellnessAgeMethod")).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
        }
        .pulsePage().navigationTitle(L("wellnessAge"))
        .task { model.recalibrateWellnessAge() }
    }
    private var yDomain: ClosedRange<Double>? {
        let ages = model.wellnessAges.map(\.age)
        guard let low = ages.min(), let high = ages.max() else { return nil }
        let padding = max(1.5, (high - low) * 0.3)
        return (low - padding)...(high + padding)
    }
}

private struct DeltaVsChronological: View {
    let estimate: WellnessAgeEstimate
    var body: some View {
        let delta = estimate.age - estimate.chronologicalAge
        let younger = delta < 0
        HStack(spacing: 6) {
            Image(systemName: younger ? "arrow.down.right" : "arrow.up.right").font(.caption.weight(.bold))
            Text(L(younger ? "wellnessAgeYounger" : "wellnessAgeOlder")
                    .replacingOccurrences(of: "{0}", with: number(abs(delta), digits: 1)))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct CycleView: View {
    @Environment(AppModel.self) private var model
    @State private var date = Date()
    var body: some View { @Bindable var model = model
        let manual = model.entries.filter { $0.kind == "cycle" }.map(\.date)
        let starts = Set(model.cycleStarts + manual).sorted()
        Form { Toggle(L("enableCycle"), isOn: $model.preferences.cycle).onChange(of: model.preferences.cycle) { _, enabled in model.savePreferences(); if enabled { Task { await model.connectHealth() } } }
            Text(L("cycleDisclaimer")).font(.footnote).foregroundStyle(.secondary)
            if model.preferences.cycle {
                Section { ValueRow(title: "nextPeriod", value: CycleEngine.nextPeriod(starts: starts).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? L("calibrating")); DatePicker(L("periodStart"), selection: $date, in: ...Date(), displayedComponents: .date); Button(L("logPeriod")) { Task { var entry = LogEntry(kind: "cycle", title: L("periodStart")); entry.date = Calendar.current.startOfDay(for: date); await model.addEntry(entry) } } }
                Section(L("history")) { ForEach(starts, id: \.self) { Text($0.formatted(date: .complete, time: .omitted)) } }
            }
        }.navigationTitle(L("cycle"))
    }
}
struct DocumentsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var loading = false
    @State private var pending: HealthDocument?
    @State private var pendingData: Data?
    @State private var reviewed = false
    var body: some View { List {
        Section { Button { importing = true } label: { Label(L("importDocument"), systemImage: "plus") }.disabled(loading); if loading { ProgressView(L("readingDocument")) } }
        ForEach(model.documents) { document in NavigationLink { DocumentDetail(document: document) } label: { Label { VStack(alignment: .leading, spacing: 5) { Text(document.name); Text(document.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "doc.text") } } }
        if model.documents.isEmpty { EmptyMetricState(title: "noDocuments", detail: "healthRecordsDetail") }
    }.navigationTitle(L("healthRecords")).fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
        Task { do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; loading = true; defer { loading = false }; let data = try Data(contentsOf: url); guard data.count <= 30_000_000 else { model.errorMessage = L("documentTooLarge"); return }; let text = try await OCRService.documentText(data, pdf: url.pathExtension.lowercased() == "pdf"); pendingData = data; pending = .init(name: url.deletingPathExtension().lastPathComponent, fileName: UUID().uuidString + "." + url.pathExtension, text: text); reviewed = false } catch { model.errorMessage = L("documentImportError") } }
    }.sheet(item: $pending) { document in NavigationStack { DocumentReview(document: document) { reviewedDocument in do { guard let data = pendingData else { return }; let dir = AppModel.documentsDirectory; try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]); try data.write(to: dir.appendingPathComponent(reviewedDocument.fileName), options: [.atomic, .completeFileProtection]); model.saveDocument(reviewedDocument); pending = nil; pendingData = nil } catch { model.errorMessage = L("saveError") } } } }
    }
}
struct DocumentReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var document: HealthDocument
    var onSave: (HealthDocument) -> Void
    @State private var confirmed = false
    var body: some View { Form { TextField(L("name"), text: $document.name); Section(L("reviewOCR")) { TextEditor(text: $document.text).frame(minHeight: 220); Text(L("reviewOCRDetail")).font(.footnote) }; Section(L("biomarkers")) { ForEach($document.biomarkers) { $marker in VStack { TextField(L("name"), text: $marker.name); HStack { TextField(L("value"), value: $marker.value, format: .number).keyboardType(.decimalPad); TextField(L("unit"), text: $marker.unit) } } }; Button(L("addBiomarker")) { document.biomarkers.append(.init(name: "", value: 0, unit: "")) } }; Toggle(L("reviewed"), isOn: $confirmed); Button(L("save")) { onSave(document) }.disabled(!confirmed || document.name.isEmpty || document.biomarkers.contains { $0.name.isEmpty || !$0.value.isFinite || $0.unit.isEmpty }) }.navigationTitle(L("reviewDocument")).toolbar { Button(L("cancel")) { dismiss() } } }
}
struct DocumentDetail: View {
    let document: HealthDocument
    var body: some View { List { Section { Text(document.text).textSelection(.enabled) }; Section(L("biomarkers")) { ForEach(document.biomarkers) { marker in ValueRow(title: marker.name, value: number(marker.value, digits: 2) + " " + marker.unit) } }; Section { ShareLink(item: AppModel.documentsDirectory.appendingPathComponent(document.fileName)) { Label(L("shareDocument"), systemImage: "square.and.arrow.up") } } }.navigationTitle(document.name) }
}


/// One signal, its measurement, what would be expected at the user's age, and
/// which way it pushes the estimate. A bare value told the user nothing about
/// whether it was helping or hurting.
private struct AgeSignalRow: View {
    let contributor: Contributor
    /// The engine encodes years as `50 - years * 5`, so this recovers them.
    private var years: Double? { contributor.score.map { (50 - $0) / 5 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(contributor.id)).font(.subheadline.weight(.medium))
                Spacer()
                if let value = contributor.value {
                    Text(number(value, digits: value < 100 ? 1 : 0) + " " + contributor.unit)
                        .font(.subheadline).monospacedDigit()
                } else {
                    Text(L("unavailable")).font(.subheadline).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                if let baseline = contributor.baseline {
                    Text(L("expectedForYourAge") + ": " + number(baseline, digits: baseline < 100 ? 1 : 0))
                }
                Spacer()
                if let years, abs(years) >= 0.1 {
                    Text((years < 0 ? "−" : "+") + number(abs(years), digits: 1) + " " + L("years"))
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.ageTint(years))
                }
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}


/// One signal's contribution to the estimate, in years. Negative is good: it
/// means that signal is making you younger than your birthday says.
private struct AgeEffectRow: View {
    var effect: AgeEffect

    private var helps: Bool { effect.years < 0 }
    private var tint: Color { helps ? AppColors.accent : AppColors.metric(.strain) }
    /// Anything under a tenth of a year is noise, not a finding.
    private var meaningful: Bool { abs(effect.years) >= 0.05 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meaningful ? (helps ? "arrow.down" : "arrow.up") : "equal")
                .font(.caption.weight(.bold))
                .foregroundStyle(meaningful ? tint : Color.secondary)
                .frame(width: 24, height: 24)
                .background((meaningful ? tint : Color.secondary).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(L(effect.key)).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(number(effect.value, digits: effect.value < 100 ? 1 : 0) + " " + effect.unit)
                    if let expected = effect.expected {
                        Text("·")
                        Text(L("reference") + " " + number(expected, digits: expected < 100 ? 1 : 0))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(meaningful
                 ? (effect.years > 0 ? "+" : "−") + number(abs(effect.years), digits: 1) + " " + L("yearsShort")
                 : "—")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(meaningful ? tint : Color.secondary)
        }
        .padding(.vertical, 4)
    }
}
