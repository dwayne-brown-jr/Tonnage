import SwiftUI
import SwiftData
import TonnageCore

/// App shell: five-area tab bar (TRAIN / COACH / MOVE / DATA / SETTINGS), plus the
/// floating rest-timer bar and the shared RestTimer / HealthKit environment objects.
struct RootView: View {
    private enum AppTab: Hashable { case train, coach, move, data, settings }
    @State private var selection: AppTab = .train
    @State private var restTimer = RestTimer()
    @State private var health = HealthKitManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @AppStorage("hasCompletedOnboarding") private var hasOnboarded = false
    @State private var showOnboarding = false
    @State private var showProfile = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabs
            if restTimer.isVisible {
                RestTimerBar()
                    .padding(.bottom, 64)
            }
        }
        .environment(restTimer)
        .environment(health)
        .animation(DS.spring, value: restTimer.isVisible)
        .onChange(of: scenePhase) { _, phase in restTimer.handleScenePhase(phase) }
        .task {
            if !hasOnboarded {
                showOnboarding = true
            } else if !ProfileStore.isComplete {
                showProfile = true   // onboarded before the profile existed → capture it now
            }
            if health.hasRequested {
                await health.refresh()
                await health.importExternalWorkouts(into: modelContext)
            }
#if DEBUG
            health.applyDemoRecoveryIfEnabled()
#endif
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
                if !ProfileStore.isComplete {
                    // Present the profile step just after onboarding dismisses.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        showProfile = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showProfile) {
            ProfileSetupView { showProfile = false }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Train", systemImage: "dumbbell.fill", value: .train) {
                TrainView()
            }
            Tab("Coach", systemImage: "bubble.left.and.text.bubble.right.fill", value: .coach) {
                CoachView()
            }
            Tab("Move", systemImage: "figure.walk", value: .move) {
                MoveView()
            }
            Tab("Data", systemImage: "chart.xyaxis.line", value: .data) {
                DataView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tint(.accent)
    }
}

#Preview("Root – Dark") {
    RootView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
