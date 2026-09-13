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
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach([Metric.strain, .recovery, .sleep]) { metric in
                            Button { model.route = metric.rawValue } label: {
                                // Ring first, name under it: the number is the
                                // subject and the label identifies it.
                                VStack(spacing: 12) {
                                    ScoreRing(metric: metric, value: model.today.score(metric).value, size: 86)
                                    Text(L(metric.rawValue))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColors.ink)
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityIdentifier("score-" + metric.rawValue)
                        }
                    }
                }
                // Guidance sits under the scores it is drawn from, not above them.
                DaySignalCard(snapshot: model.today, history: model.history)
                if model.preferences.enabledCards.contains("stress") || model.preferences.enabledCards.contains("energy") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("stressAndEnergy")).font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        if model.preferences.enabledCards.contains("stress") {
                            Button { model.route = "stress" } label: { StressTodayCard(snapshot: model.today) }
                                .buttonStyle(.plain)
                        }
                        if model.preferences.enabledCards.contains("energy") {
                            Button { model.route = "energy" } label: { BodyBatteryCompactCard(snapshot: model.today) }
                                .buttonStyle(.plain).accessibilityIdentifier("battery-detail")
                        }
                    }
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
    @ViewBuilder private func cardView(_ id: String) -> some View {
        switch id {
        case "health": Button { model.tab = "biology" } label: { Card { SectionTitle(title: "healthMonitor", symbol: "heart.text.clipboard"); HStack { ForEach(["hrv", "rhr", "respiratory", "oxygen"], id: \.self) { key in VStack(alignment: .leading, spacing: 7) { Text(L(key)).font(.caption2).foregroundStyle(.secondary); Text(number(model.today.vital(key)?.value, digits: key == "respiratory" ? 1 : 0)).font(.title3.weight(.semibold)); Capsule().fill(AppColors.accent.opacity(0.3)).frame(height: 4) }.frame(maxWidth: .infinity, alignment: .leading) } } } }.buttonStyle(.plain)
        case "activity": Button { model.tab = "fitness" } label: { Card { SectionTitle(title: "activity", symbol: "figure.walk"); ValueRow(title: "steps", value: number(model.today.vital("steps")?.value)); ValueRow(title: "activeEnergy", value: number(model.today.vital("activeEnergy")?.value) + " kcal"); ValueRow(title: "workouts", value: String(model.today.workouts.count)) } }.buttonStyle(.plain)
        case "journal": Button { model.route = "journal" } label: { Card { SectionTitle(title: "journal", symbol: "book.closed"); Text(L("journalPrompt")).font(.subheadline).foregroundStyle(.secondary) } }.buttonStyle(.plain)
        default: EmptyView()
                    }
                }
}

/// Personal guidance: a cross-metric read of the day and one thing to do about
/// it. A single score cannot say "poor sleep but strong recovery", and that
/// contrast is usually the useful sentence.
private struct DaySignalCard: View {
    let snapshot: DailySnapshot
    let history: [DailySnapshot]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scene: MetricScene {
        if let energy = snapshot.score(.energy).value, energy < 35 { return .energy }
        if let stress = snapshot.score(.stress).value, stress >= 65 { return .stress }
        if let recovery = snapshot.score(.recovery).value, recovery >= 65 { return .recovery }
        return .sleep
    }

    var body: some View {
        let briefing = MetricNarrator.briefing(snapshot: snapshot, history: history)
        Card(scene: scene, accent: AppColors.accent) {
            HStack {
                Label(L("personalAdvice"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold)).opacity(0.85)
                Spacer()
            }
            Text(localized(briefing.headline))
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(briefing.detail) { line in
                Text(localized(line))
                    .font(.subheadline)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: snapshot.score(.recovery).value)
        .accessibilityElement(children: .combine)
    }
}

