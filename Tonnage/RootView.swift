import SwiftUI
import SwiftData
import UIKit
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
    /// Set when a user goes through the NEW onboarding. Lets us resume an interrupted
    /// first-run (finish profile/split) without dragging existing users — who predate the
    /// split feature and never set this — into the split picker.
    @AppStorage("didEnterFirstRunSetup") private var didEnterSetup = false
    /// One-time merge of logged exercise-name variants ("Dumbbell Incline Press" →
    /// "Incline DB Press") so PRs/ghosts/charts share one history per movement.
    @AppStorage("migration.canonicalNames.v1") private var canonicalNamesMigrated = false
    @AppStorage("currentBlock") private var currentBlock = 1
    @State private var showOnboarding = false
    @State private var showProfile = false
    @State private var showSplitPicker = false
    @State private var showCoachingUpdate = false
    @State private var showBuildPlan = false
    @State private var showPlanReveal = false   // first-run payoff after the plan is built
    /// True only during the genuine first-run sequence, so the split picker is offered to
    /// new users but never auto-shown to people who onboarded before this feature.
    @State private var firstRunFlow = false
    /// Hide the floating rest-timer bar while a keyboard is up — otherwise the bar, the keyboard,
    /// and the field being edited stack up at the bottom and clutter the screen. The timer keeps
    /// running; it just gets out of the way and reappears when the keyboard dismisses.
    @State private var keyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabs
            if restTimer.isVisible && !keyboardVisible {
                RestTimerBar()
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(restTimer)
        .environment(health)
        .animation(DS.spring, value: restTimer.isVisible)
        .animation(DS.spring, value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: scenePhase) { _, phase in
            restTimer.handleScenePhase(phase)
            // Re-read recovery on foreground so readiness reflects last night's data once a ring/
            // watch has synced it to Health — not just the cold-launch read. (Skips the demo feed.)
            if phase == .active, health.hasRequested {
#if DEBUG
                if health.isDemoRecovery { return }
#endif
                Task { await health.refresh() }
            }
        }
        .task {
            SharedProfile.syncFromProfile()   // mirror starting point to Tonnage Fuel
            // Heal any session template that lost its exercises (older build / partial sync) so a
            // session never shows up empty. No-op when every session is populated.
            repairEmptySessions(modelContext, split: ProfileStore.split)
#if DEBUG
            // UI-test hook: launch with `-uitesting` to bypass the first-run gates and seed
            // demo data, so XCUITest smoke flows land on a populated TRAIN deterministically.
            if ProcessInfo.processInfo.arguments.contains("-uitesting") {
                hasOnboarded = true; hasChosenSplit = true; hasAnsweredIntake = true; didEnterSetup = true
                DemoData.seedTrainingData(in: modelContext)
                await health.setDemoRecovery(true)
            }
#endif
            // Legacy users predate the split feature (didEnterSetup was never set). Their
            // current program IS their split — record it as chosen so the first-run gating
            // never dangles; Settings → Training Split remains the way to change it.
            if hasOnboarded && !didEnterSetup && !hasChosenSplit {
                hasChosenSplit = true
            }
            if !canonicalNamesMigrated {
                canonicalNamesMigrated = true
                migrateCanonicalExerciseNames()
            }
            if !hasOnboarded {
                showOnboarding = true
            } else if !ProfileStore.isComplete {
                // Resume the chain for a new user whose first-run was interrupted; existing
                // users (didEnterSetup == false) just fill the profile, no chaining.
                firstRunFlow = didEnterSetup
                showProfile = true
            } else if didEnterSetup && !hasChosenSplit {
                // New user got through onboarding/profile but never picked a split (app was
                // killed in the hand-off) — resume setup instead of stranding them.
                firstRunFlow = true
                showSplitPicker = true
            } else if !hasAnsweredIntake {
                showCoachingUpdate = true   // existing user → one-time "what's new" intake
            }
            if health.hasRequested {
                await health.upgradeAuthorizationIfNeeded()   // prompt once for newly-added read types (temp, respiratory)
                await health.refresh()
                await health.importExternalWorkouts(into: modelContext)
            }
#if DEBUG
            health.applyDemoRecoveryIfEnabled()
#endif
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onFinish: {
                hasOnboarded = true
                didEnterSetup = true   // mark this as a new-onboarding user so setup can resume
                showOnboarding = false
                firstRunFlow = true
                if !ProfileStore.isComplete {
                    // Present the profile step just after onboarding dismisses.
                    presentAfterDismiss { showProfile = true }
                } else if !hasChosenSplit {
                    presentAfterDismiss { showSplitPicker = true }
                }
            }, firstRun: true)
            .environment(health)   // covers don't reliably inherit @Observable env
        }
        .fullScreenCover(isPresented: $showProfile) {
            ProfileSetupView {
                showProfile = false
                hasAnsweredIntake = true   // the profile form already includes the coaching intake
                seedBodyweightToHealth()   // the weight they just typed starts the recomp trend
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
        .fullScreenCover(isPresented: $showBuildPlan, onDismiss: {
            // Whether they built a custom plan or skipped, end first-run on the personalized
            // reveal — the "here's YOUR plan" payoff — then into TRAIN.
            if firstRunFlow {
                firstRunFlow = false
                presentAfterDismiss { showPlanReveal = true }
            }
        }) {
            PlanBlockSheet(currentBlockNumber: currentBlock, mode: .buildInitial) { }
        }
        .fullScreenCover(isPresented: $showPlanReveal) {
            PlanRevealView { showPlanReveal = false }
        }
        .fullScreenCover(isPresented: $showCoachingUpdate) {
            CoachingUpdateView {
                hasAnsweredIntake = true
                showCoachingUpdate = false
            }
        }
    }

    /// Rewrite logged + template exercise names to their library-canonical form so
    /// past name variants merge into one history. Conservative: unknown names untouched.
    private func migrateCanonicalExerciseNames() {
        var changed = false
        for ex in (try? modelContext.fetch(FetchDescriptor<LoggedExercise>())) ?? [] {
            let canonical = ExerciseLibrary.canonicalDisplayName(for: ex.name)
            if canonical != ex.name { ex.name = canonical; changed = true }
        }
        for t in (try? modelContext.fetch(FetchDescriptor<ExerciseTemplate>())) ?? [] {
            let canonical = ExerciseLibrary.canonicalDisplayName(for: t.name)
            if canonical != t.name { t.name = canonical; changed = true }
        }
        if changed { modelContext.saveOrReport() }
    }

    /// Re-present a sheet shortly after another dismisses (a single live fullScreenCover
    /// at a time needs the gap, or the next one silently no-ops).
    private func presentAfterDismiss(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    /// Onboarding already asks for bodyweight and uses it for the strength-standard BW
    /// ratios — write it to Health once so the recomp trend starts on day one instead of
    /// showing an empty card that asks for a number the app was already given. Never
    /// overwrites: skipped when Health already has a weight on file.
    private func seedBodyweightToHealth() {
        let pounds = Double(UserDefaults.standard.integer(forKey: ProfileStore.Key.weight))
        guard pounds > 0, health.bodyweight.isEmpty else { return }
        Task { await health.saveBodyMass(pounds: pounds) }
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
