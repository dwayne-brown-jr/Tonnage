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
    @AppStorage("hasChosenSplit") private var hasChosenSplit = false
    @AppStorage("hasAnsweredCoachingIntake") private var hasAnsweredIntake = false
    @AppStorage("currentBlock") private var currentBlock = 1
    @State private var showOnboarding = false
    @State private var showProfile = false
    @State private var showSplitPicker = false
    @State private var showCoachingUpdate = false
    @State private var showBuildPlan = false
    /// True only during the genuine first-run sequence, so the split picker is offered to
    /// new users but never auto-shown to people who onboarded before this feature.
    @State private var firstRunFlow = false

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
            SharedProfile.syncFromProfile()   // mirror starting point to Tonnage Fuel
            if !hasOnboarded {
                showOnboarding = true
            } else if !ProfileStore.isComplete {
                showProfile = true   // onboarded before the profile existed → capture it now
            } else if !hasAnsweredIntake {
                showCoachingUpdate = true   // existing user → one-time "what's new" intake
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
                firstRunFlow = true
                if !ProfileStore.isComplete {
                    // Present the profile step just after onboarding dismisses.
                    presentAfterDismiss { showProfile = true }
                } else if !hasChosenSplit {
                    presentAfterDismiss { showSplitPicker = true }
                }
            }
            .environment(health)   // covers don't reliably inherit @Observable env
        }
        .fullScreenCover(isPresented: $showProfile) {
            ProfileSetupView {
                showProfile = false
                hasAnsweredIntake = true   // the profile form already includes the coaching intake
                // First-run only: chain into the split picker after the profile step.
                if firstRunFlow && !hasChosenSplit {
                    presentAfterDismiss { showSplitPicker = true }
                }
            }
        }
        .fullScreenCover(isPresented: $showSplitPicker) {
            SplitPickerSheet {
                // First-run: offer Coach to build a personalized starting plan.
                if firstRunFlow { presentAfterDismiss { showBuildPlan = true } }
            }
        }
        .fullScreenCover(isPresented: $showBuildPlan, onDismiss: { firstRunFlow = false }) {
            PlanBlockSheet(currentBlockNumber: currentBlock, mode: .buildInitial) { }
        }
        .fullScreenCover(isPresented: $showCoachingUpdate) {
            CoachingUpdateView {
                hasAnsweredIntake = true
                showCoachingUpdate = false
            }
        }
    }

    /// Re-present a sheet shortly after another dismisses (a single live fullScreenCover
    /// at a time needs the gap, or the next one silently no-ops).
    private func presentAfterDismiss(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            action()
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
