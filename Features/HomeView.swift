import SwiftUI
import PulseCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var calendarOpen = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting()).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(L("dailyOverview")).font(.title2.weight(.bold))
                    }
                    Spacer()
                    Button { model.route = "journal" } label: { Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(AppColors.accent).padding(14).background(AppColors.accent.opacity(0.1), in: Circle()) }.accessibilityLabel(L("journal"))
                }
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").padding(10) }
                    Spacer()
                    Button { calendarOpen = true } label: { HStack(spacing: 6) { Text(Calendar.current.isDateInToday(model.selectedDate) ? L("today") : model.selectedDate.formatted(.dateTime.day().month(.abbreviated))); Image(systemName: "chevron.down").font(.caption) }.font(.subheadline.weight(.semibold)) }
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").padding(10) }.disabled(Calendar.current.isDateInToday(model.selectedDate))
                }.foregroundStyle(.primary)
                DaySignalCard(snapshot: model.today)
                Card(accent: AppColors.metric(.recovery)) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach([Metric.strain, .recovery, .sleep]) { metric in
                            Button { model.route = metric.rawValue } label: {
                                VStack(spacing: 10) {
                                    Text(L(metric.rawValue)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ScoreRing(metric: metric, value: model.today.score(metric).value, size: 76)
                                    Text(L(model.today.score(metric).value == nil ? "calibrating" : category(metric))).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                    if model.today.score(metric).value != nil {
                                        ConfidenceBadge(percent: model.today.score(metric).confidencePercent, compact: true)
                                    }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityIdentifier("score-" + metric.rawValue)
                        }
                    }
                }
                if model.preferences.enabledCards.contains("energy") {
                    Button { model.route = "energy" } label: { BodyBatteryCompactCard(snapshot: model.today) }
                        .buttonStyle(.plain).accessibilityIdentifier("battery-detail")
                }
                if model.preferences.enabledCards.contains("stress") {
                    Button { model.route = "stress" } label: { StressTodayCard(snapshot: model.today) }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    quickAction("journal", symbol: "book.closed.fill") { model.route = "journal" }
                    quickAction("workouts", symbol: "dumbbell.fill") { model.route = "strength" }
                    quickAction("trends", symbol: "chart.xyaxis.line") { model.tab = "trends" }
                }
                ForEach(model.preferences.enabledCards.filter { $0 != "energy" && $0 != "stress" }, id: \.self) { card in cardView(card) }
                Text(model.currentSnapshot.map { L("updated") + " " + $0.updatedAt.formatted(date: .abbreviated, time: .shortened) } ?? L("connectForData")).font(.caption2).foregroundStyle(.secondary).padding(.vertical, 8)
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }.pulsePage().navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { VeyraBrandMark(compact: true) }
            ToolbarItem(placement: .topBarLeading) { Menu { ForEach(["active", "sick", "injured", "break"], id: \.self) { status in Button(L(status)) { model.preferences.status = status; model.savePreferences() } } } label: { Label(L(model.preferences.status), systemImage: "heart.text.square.fill").font(.caption).foregroundStyle(AppColors.accent) }.accessibilityLabel(L("status")) }
            ToolbarItem(placement: .topBarTrailing) { Button { model.route = "settings" } label: { Image(systemName: "person.crop.circle").font(.title3) }.accessibilityLabel(L("settings")) }
        }
        .refreshable { await model.sync() }
        .sheet(isPresented: $calendarOpen) { @Bindable var model = model; NavigationStack { DatePicker(L("date"), selection: $model.selectedDate, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical).padding().toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { calendarOpen = false } } } .presentationDetents([.medium]) } }
    }
    private func shift(_ offset: Int) { if let day = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDate) { model.selectedDate = day } }
    private func quickAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(AppColors.accent)
                Text(L(title)).font(.caption2.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 78).padding(6).background(AppColors.surfaceRaised, in: .rect(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        return L(hour < 12 ? "goodMorning" : hour < 19 ? "goodAfternoon" : "goodEvening")
    }
    private func category(_ metric: Metric) -> String {
        MetricNarrator.band(model.today.score(metric).value ?? 0)
    }
    @ViewBuilder private func cardView(_ id: String) -> some View {
        switch id {
        case "health": Button { model.tab = "biology" } label: { Card { SectionTitle(title: "healthMonitor", symbol: "heart.text.clipboard"); HStack { ForEach(["hrv", "rhr", "respiratory", "oxygen"], id: \.self) { key in VStack(alignment: .leading, spacing: 7) { Text(L(key)).font(.caption2).foregroundStyle(.secondary); Text(number(model.today.vital(key)?.value, digits: key == "respiratory" ? 1 : 0)).font(.title3.weight(.semibold)); Capsule().fill(AppColors.accent.opacity(0.3)).frame(height: 4) }.frame(maxWidth: .infinity, alignment: .leading) } } } }.buttonStyle(.plain)
        case "activity": Button { model.tab = "fitness" } label: { Card { SectionTitle(title: "activity", symbol: "figure.walk"); ValueRow(title: "steps", value: number(model.today.vital("steps")?.value)); ValueRow(title: "activeEnergy", value: number(model.today.vital("activeEnergy")?.value) + " kcal"); ValueRow(title: "workouts", value: String(model.today.workouts.count)) } }.buttonStyle(.plain)
        case "journal": Button { model.route = "journal" } label: { Card { SectionTitle(title: "journal", symbol: "book.closed"); Text(L("journalPrompt")).font(.subheadline).foregroundStyle(.secondary) } }.buttonStyle(.plain)
        default: EmptyView()
                    }
                }
}

/// The day's headline. It used to be painted with a fixed night-blue gradient
/// and white text, which turned it into a black slab on a white screen; it now
/// uses the metric's own scene so it reads in both appearances.
private struct DaySignalCard: View {
    let snapshot: DailySnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var energy: Double? { snapshot.score(.energy).value }
    private var stress: Double? { snapshot.score(.stress).value }
    private var recovery: Double? { snapshot.score(.recovery).value }

    private var state: (title: String, detail: String, symbol: String, scene: MetricScene, metric: Metric) {
        if let energy, energy < 35 { return ("signalLowEnergyTitle", "signalLowEnergyDetail", "leaf.fill", .energy, .energy) }
        if let stress, stress >= 70 { return ("signalHighStressTitle", "signalHighStressDetail", "waveform.path.ecg", .stress, .stress) }
        if let recovery, recovery >= 70 { return ("signalReadyTitle", "signalReadyDetail", "figure.run", .recovery, .recovery) }
        return ("signalLearningTitle", "signalLearningDetail", "sparkles", .recovery, .recovery)
    }

    var body: some View {
        let state = state
        Card(scene: state.scene, accent: AppColors.metric(state.metric)) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: state.symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("todayRhythm")).font(.caption.weight(.semibold)).opacity(0.72)
                    Text(L(state.title)).font(.headline.weight(.bold))
                    Text(L(state.detail)).font(.caption).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: energy)
        .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: stress)
        .accessibilityElement(children: .combine)
    }
}
