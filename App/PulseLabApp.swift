import SwiftUI
import PulseCore

@main struct PulseLabApp: App {
    @State private var model: AppModel?
    @State private var loadError = false
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { RootView().environment(model).preferredColorScheme(model.preferences.darkMode == "dark" ? .dark : model.preferences.darkMode == "light" ? .light : nil).environment(\.locale, Locale(identifier: model.preferences.language)) }
                else if loadError { ContentUnavailableView { Label(L("storageError"), systemImage: "externaldrive.badge.exclamationmark") } description: { Text(L("storageErrorDetail")) } actions: { Button(L("retry")) { load() } } }
                else { ProgressView().task { load() } }
            }
        }
    }
    private func load() {
        do {
            let created = try AppModel(store: LocalStore(inMemory: ProcessInfo.processInfo.arguments.contains("--uitesting")))
            created.registerBackgroundRefresh()
            model = created
            loadError = false
        } catch { loadError = true }
    }
}
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab(L("home"), systemImage: "house", value: "home") { NavigationStack { HomeView() } }
            Tab(L("fitness"), systemImage: "figure.run", value: "fitness") { NavigationStack { FitnessView() } }
            Tab(L("biology"), systemImage: "heart.text.clipboard", value: "biology") { NavigationStack { BiologyView() } }
            Tab(L("trends"), systemImage: "chart.xyaxis.line", value: "trends") { NavigationStack { TrendsView() } }
        }
        .tint(AppColors.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: Binding(get: { model.route != nil }, set: { if !$0 { model.route = nil } })) {
            NavigationStack { RouteView(route: model.route ?? "").toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("close"), systemImage: "xmark") { model.route = nil }.labelStyle(.iconOnly) } } }
        }
        .fullScreenCover(isPresented: Binding(get: { !model.preferences.onboarded }, set: { _ in })) { OnboardingView() }
        .alert(L("attention"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button(L("ok")) { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .onOpenURL { model.handleURL($0) }
        .overlay(alignment: .top) { SyncPill().zIndex(10) }
        .task(id: "\(phase)-\(model.preferences.autoSyncMinutes)") {
            guard phase == .active, model.preferences.onboarded, model.preferences.healthConnected, !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
            #if targetEnvironment(simulator)
            // HealthKit is unavailable in unsigned simulator builds. A real device
            // will perform the initial sync and continue on the configured interval.
            model.publish()
            #else
            model.registerObservers()
            await model.sync()
            while !Task.isCancelled {
                let seconds = UInt64(max(1, model.preferences.autoSyncMinutes)) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: seconds)
                guard !Task.isCancelled else { return }
                await model.sync()
            }
            #endif
        }
        .onChange(of: phase) { _, phase in
            if phase == .active && model.preferences.onboarded { model.publish() }
            if phase == .background { model.scheduleBackgroundRefresh() }
        }
    }
}
struct RouteView: View {
    var route: String
    var body: some View {
        if let metric = Metric(rawValue: route) { MetricDetailView(metric: metric) }
        else {
            switch route {
            case "settings": SettingsView()
            case "profile": ProfileSettingsView()
            case "wellnessAge": WellnessAgeView()
            case "journal": JournalView()
            case "alarm": AlarmView()
            case "plan": TrainingPlanView()
            case "checkin": CheckinView()
            case "workout", "strength": StrengthView()
            case "activeStrength": ActiveStrengthView()
            case "documents": DocumentsView()
            case "cycle": CycleView()
            case "body": BodyView()
            case "health": BiologyView()
            default: ContentUnavailableView(L("noData"), systemImage: "square.stack")
            }
        }
    }
}
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Spacer()
                if step == 0 {
                    VeyraBrandMark().frame(width: 250, height: 95).shadow(color: AppColors.accent.opacity(0.25), radius: 16)
                } else {
                    Image(systemName: step == 1 ? "lock.shield" : "heart.fill").font(.system(size: 58, weight: .light)).foregroundStyle(AppColors.accent)
                }
                if step != 0 { Text(L(step == 1 ? "yourData" : "connectHealth")).font(AppTypography.title) }
                Text(L(step == 0 ? "welcomeDetail" : step == 1 ? "privacyDetail" : "calibrationDetail")).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.syncing { ProgressView(value: model.progress); Text(L("importing")).font(.caption) }
                Spacer()
                if step < 2 { PrimaryButton(title: "continue") { step += 1 } }
                else {
                    PrimaryButton(title: "connectHealth") { Task { await model.connectHealth() } }.disabled(model.syncing)
                    Button(L("startWithoutHealth")) { model.preferences.onboarded = true; model.savePreferences() }.frame(maxWidth: .infinity).padding(.bottom)
                }
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { index in Capsule().fill(index == step ? AppColors.accent : Color.secondary.opacity(0.2)).frame(width: index == step ? 24 : 8, height: 6) } }.frame(maxWidth: .infinity)
            }.padding(30).background {
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    LinearGradient(colors: [AppColors.accent.opacity(0.13), .clear, Color.purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                    Circle().fill(AppColors.accent.opacity(0.10)).frame(width: 260).blur(radius: 80).offset(x: -120, y: -240)
                    Circle().fill(Color.purple.opacity(0.08)).frame(width: 300).blur(radius: 90).offset(x: 150, y: 240)
                }
            }.tint(AppColors.accent)
        }.interactiveDismissDisabled()
    }
}

/// The sync indicator: a pill at the top centre with a determinate ring, the
/// current phase, and a brief confirmation before it leaves. The old version
/// was an indeterminate spinner beside a percentage that only advanced once
/// every thirty days of import.
struct SyncPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDone = false

    var body: some View {
        Group {
            if model.syncing {
                content(progress: model.progress,
                        title: L(model.syncPhase ?? "syncingNow"),
                        detail: model.syncDetail,
                        done: false)
            } else if showingDone {
                content(progress: 1, title: L("syncUpToDate"), detail: nil, done: true)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.syncing)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showingDone)
        .onChange(of: model.syncCompletedAt) { _, value in
            guard value != nil else { return }
            showingDone = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                showingDone = false
            }
        }
    }

    private func content(progress: Double, title: String, detail: String?, done: Bool) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(AppColors.accent.opacity(0.2), lineWidth: 2.5)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(AppColors.accent)
                } else {
                    Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 17, height: 17)
            Text(title).font(.caption.weight(.semibold))
            if let detail {
                Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else if !done {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
