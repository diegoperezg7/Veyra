import SwiftUI
import Charts
import PulseCore

/// Everything the scale reports, in one place: the current figures, how each
/// has moved, where they sit on a published reference scale, and a weigh-in
/// reminder. Renpho and similar scales reach Veyra through Apple Health.
struct BodyView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 90

    private var days: [DailySnapshot] {
        Array(model.history.suffix(range))
    }
    private func series(_ key: String) -> [TimelinePoint] {
        days.compactMap { day in day.vital(key).map { TimelinePoint(date: day.date, value: $0.value) } }
    }
    private var assessment: BodyAssessment {
        BodyCompositionEngine.assess(
            weight: series("weight").map(\.value),
            bodyFat: series("bodyFat").map(\.value),
            leanMass: series("leanMass").map(\.value),
            bmi: series("bmi").map(\.value),
            sex: model.preferences.biologicalSex,
            observations: series("weight").count
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    Picker(L("range"), selection: $range) {
                        ForEach([30, 90, 180, 365], id: \.self) { days in
                            Text(days == 365 ? "1Y" : days == 180 ? "6M" : days == 90 ? "3M" : "30D").tag(days)
                        }
                    }.pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        figure("weight", "kg", 1)
                        figure("bodyFat", "%", 1)
                        figure("leanMass", "kg", 1)
                        figure("bmi", "", 1)
                    }
                }

                ForEach(["weight", "bodyFat", "leanMass"], id: \.self) { key in
                    let points = series(key)
                    if points.count >= 2 { measureCard(key, points) }
                }

                if !assessment.bands.isEmpty { referenceCard }

                Card {
                    Label(L("weighInReminder"), systemImage: "bell").font(AppTypography.cardTitle)
                    WeighInReminder()
                }

                Card {
                    Label(L("dataSources"), systemImage: "arrow.triangle.2.circlepath").font(AppTypography.cardTitle)
                    Text(L("scalesDetail")).font(.subheadline).foregroundStyle(.secondary)
                    Text(L("scalesSetup")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Saying this plainly is better than the user wondering why
                    // half of what the scale shows never appears.
                    Text(L("scalesUnsupportedFields")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
        }
        .pulsePage().navigationTitle(L("body")).navigationBarTitleDisplayMode(.inline)
    }

    private func figure(_ key: String, _ unit: String, _ digits: Int) -> some View {
        let points = series(key)
        let change = assessment.changes[key]
        return VStack(alignment: .leading, spacing: 5) {
            Text(L(key)).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(number(points.last?.value, digits: digits)).font(.title2.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let change, abs(change) >= 0.05 {
                // Down is not automatically good — lean mass falling is not a
                // win — so the arrow states direction and never a judgement.
                HStack(spacing: 3) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down").font(.caption2.weight(.bold))
                    Text(number(abs(change), digits: digits) + " " + unit).monospacedDigit()
                }
                .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(L("noChange")).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func measureCard(_ key: String, _ points: [TimelinePoint]) -> some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.25, max(abs(high) * 0.02, 0.3))
        return Card {
            HStack {
                Text(L(key)).font(AppTypography.cardTitle)
                Spacer()
                Text(number(points.last?.value, digits: 1)).font(.headline).monospacedDigit()
            }
            HealthTrendChart(points: points, metric: .recovery, height: 150,
                             maximumGap: 10 * 86_400,
                             yDomain: (low - padding)...(high + padding),
                             showsAverage: points.count >= 14)
            if let projection = TrendEngine.projection(points) {
                Text(L("projection30") + ": " + number(projection, digits: 1))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var referenceCard: some View {
        Card {
            Text(L("referenceScales")).font(AppTypography.cardTitle)
            ForEach(assessment.bands) { band in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(L(band.key)).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(number(band.value, digits: 1) + " " + band.unit).monospacedDigit()
                        Text(L(band.band)).font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(AppColors.accentSoft, in: Capsule())
                            .foregroundStyle(AppColors.accent)
                    }
                    BandScale(position: band.position)
                }
                .padding(.vertical, 3)
            }
            if model.preferences.biologicalSex == nil {
                Label(L("bodyFatNeedsSex"), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            Text(L("referenceScalesDetail")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A thin scale with the current position marked. Deliberately unlabelled with
/// "good"/"bad": the band name above it already says where the value sits.
private struct BandScale: View {
    let position: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: AppColors.scaleGradient, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .opacity(0.55)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(AppColors.ink.opacity(0.35), lineWidth: 1.5))
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .offset(x: proxy.size.width * min(1, max(0, position)) - 6.5)
            }
            .frame(height: 13)
        }
        .frame(height: 13)
        .accessibilityHidden(true)
    }
}

/// Schedules a repeating daily reminder. Weighing at a consistent time is what
/// makes a weight series comparable day to day.
struct WeighInReminder: View {
    @Environment(AppModel.self) private var model
    @AppStorage("weighIn.enabled") private var enabled = false
    @AppStorage("weighIn.hour") private var hour = 8
    @AppStorage("weighIn.minute") private var minute = 0
    @State private var time = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("enableWeighInReminder"), isOn: $enabled)
            if enabled {
                DatePicker(L("time"), selection: $time, displayedComponents: .hourAndMinute)
            }
            Text(L("weighInReminderDetail")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        .onChange(of: time) { _, value in
            hour = Calendar.current.component(.hour, from: value)
            minute = Calendar.current.component(.minute, from: value)
            if enabled { schedule() }
        }
        .onChange(of: enabled) { _, value in
            if value { schedule() } else { NotificationService.cancel("weighIn") }
        }
    }
    private func schedule() {
        Task {
            do { try await NotificationService.schedule(id: "weighIn", title: "Veyra", body: L("weighInReminderBody"), date: time, repeats: true) }
            catch { model.errorMessage = L("notificationError") }
        }
    }
}
