import SwiftUI
import SwiftData
import UIKit
import TonnageCore

/// The core screen: pick week + session + day-type, then log sets with last-week
/// ghosts, the Coach's Call, and live tonnage stats.
struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(\.openURL) private var openURL
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query private var allWorkouts: [LoggedWorkout]   // for the days-since-rest training streak

    @AppStorage("currentBlock") private var currentBlock = 1
    // Shared with COACH so it can answer about the exact session/day on screen.
    @AppStorage("train.focusWeek") private var focusWeek = 1
    @AppStorage("train.focusSession") private var focusSession = ""
    @AppStorage("train.focusDayType") private var focusDayType = DayType.lift.rawValue
    @State private var store = TrainStore()
    @State private var selectedBlock = 1
    // Persisted so a relaunch / force-quit resumes the same week, session, and day type
    // instead of snapping back to Week 1.
    @AppStorage("train.week") private var week = 1
    @AppStorage("train.sessionIndex") private var sessionIndex = 0
    // Day type is a transient mode, NOT persisted — it resets to Lift each launch so the
    // screen never gets stuck showing a rest day.
    @State private var dayType: DayType = .lift
    // Which calendar day a rest is being logged for. Defaults to today; backdate it to
    // record a rest you took but didn't log (e.g. yesterday). Resets to today each launch.
    @State private var restDate: Date = .now
    @State private var expandedID: PersistentIdentifier?
    @State private var sessionSaved = false
    @State private var saveFailed = false
    @State private var collapse: CGFloat = 0   // 0 = large title expanded, 1 = collapsed to compact bar
    @State private var showRecovery = false
    @State private var showPlanBlock = false
    @State private var showReplanBlock = false
    @State private var confirmNewBlock = false
    @State private var shareItem: ShareImageItem?

    private var program: Program? { programs.first }
    private var sessions: [SessionTemplate] { program?.orderedSessions ?? [] }
    private var session: SessionTemplate? {
        sessions.indices.contains(sessionIndex) ? sessions[sessionIndex] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        largeHeader
                        contentStack
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    collapse = min(1, max(0, y / 64))
                }

                compactBar
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.accent)
        .task {
            store.configure(context)
            selectedBlock = currentBlock
            if !sessions.indices.contains(sessionIndex) { sessionIndex = 0 }   // saved index may be stale
            store.readinessHoldsProgression = readiness.holdsProgression
            reload()
        }
        .onChange(of: readiness.holdsProgression) { _, holds in
            store.readinessHoldsProgression = holds
            // Only re-derive the Coach's Call when nothing's logged yet — never disrupt
            // an in-progress session (which would reset the expanded card).
            if (store.workout?.completedSetCount ?? 0) == 0 { reload() }
        }
        .onChange(of: selectedBlock) { reload() }
        .onChange(of: currentBlock) { PhoneConnectivity.shared.pushContext() }   // sync active block to watch
        .onChange(of: week) { reload() }
        .onChange(of: sessionIndex) { reload() }
        .onChange(of: dayType) { old, new in
            if old == .lift && new != .lift { restDate = .now }   // each rest-logging session starts at today
            reload()
        }
        .onChange(of: restDate) {
            guard dayType != .lift else { return }   // rest date only matters in rest mode
            store.loadRest(block: selectedBlock, week: week, date: restDate)
        }
        .onChange(of: sessions.count) {
            if !sessions.indices.contains(sessionIndex) { sessionIndex = 0 }
            reload()
        }
        .onChange(of: store.workout?.completedSetCount) {
            refreshWidget()                          // keep home-screen widget totals live
            PhoneConnectivity.shared.pushContext()   // mirror logged sets to the watch
        }
        .onDisappear { store.pruneIfEmpty(store.workout) }
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .sheet(isPresented: $showPlanBlock) {
            PlanBlockSheet(currentBlockNumber: currentBlock) { startNewBlock() }
        }
        .sheet(isPresented: $showReplanBlock) {
            PlanBlockSheet(currentBlockNumber: currentBlock, mode: .replanCurrent) { reload() }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.image]) }
        .confirmationDialog("Start Block \(String(format: "%02d", currentBlock + 1))?",
                            isPresented: $confirmNewBlock, titleVisibility: .visible) {
            Button("Start Empty Block", role: .destructive) { startNewBlock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves you to a fresh empty Block \(String(format: "%02d", currentBlock + 1)), Week 1. Your current block is kept — switch back anytime from the block menu.")
        }
    }

    /// Share the session you just logged as a branded card.
    @MainActor private func shareWorkoutButton(_ workout: LoggedWorkout) -> some View {
        Button {
            if let img = ShareCardRenderer.image(WorkoutShareCard(workout: workout)) {
                Haptics.impact(.light)
                shareItem = ShareImageItem(image: img)
            }
        } label: {
            Label("Share Workout", systemImage: "square.and.arrow.up")
                .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func startNewBlock() {
        store.pruneIfEmpty(store.workout)
        currentBlock += 1
        selectedBlock = currentBlock
        week = 1
        Haptics.success()
    }

    // MARK: Content

    private var readiness: Readiness { health.currentReadiness() }

    @ViewBuilder private var contentStack: some View {
        VStack(spacing: DS.Spacing.lg) {
            // Always shown — even with no data it reads as a "Connect Apple Health"
            // prompt and keeps the Recovery screen discoverable.
            ReadinessCard(readiness: readiness,
                          today: TodayPlan.verdict(band: readiness.band, focus: session?.name, dayType: dayType,
                                                   trainingStreak: FatigueEngine.trainingStreak(workouts: allWorkouts))) {
                showRecovery = true
            }
            switch dayType {
            case .lift:
                SessionStatsBar(workout: store.workout)
                if let workout = store.workout {
                    ForEach(workout.orderedExercises, id: \.persistentModelID) { exercise in
                        ExerciseLogCard(
                            exercise: exercise,
                            guidance: store.guidance[exercise.name],
                            expandedID: $expandedID,
                            store: store
                        )
                    }
                    SessionNotesField(workout: workout)
                    if workout.completedSetCount > 0 {
                        saveSessionButton(workout)
                        shareWorkoutButton(workout)
                    }
                }
            case .activeRest, .fullRest:
                RestDayView(
                    dayType: dayType,
                    isLogged: store.workout?.dayType == dayType,
                    date: $restDate,
                    onLog: {
                        store.logRestDay(block: selectedBlock, week: week, dayType: dayType, date: restDate)
                    },
                    onBackToWorkout: {
                        withAnimation(DS.snappySpring) { dayType = .lift }
                    }
                )
            }
            // Surface the headline AI feature when the block is wrapping up, so it isn't
            // hidden behind the block dropdown.
            if dayType == .lift && week >= 5 { planNextBlockButton }
        }
    }

    private var planNextBlockButton: some View {
        Button { showPlanBlock = true } label: {
            Label("Plan Block \(String(format: "%02d", currentBlock + 1)) with Coach", systemImage: "brain.head.profile")
                .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(Color.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Header (large title scrolls; compact bar pins + fades in)

    private var largeHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRAIN")
                    .font(DSFont.displayXL)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                blockMenu
            }
            WeekSelector(week: $week)
            // A rest day isn't a session, so hide the Upper/Lower picker in rest mode.
            if !sessions.isEmpty && dayType == .lift {
                SessionSelector(sessions: sessions, index: $sessionIndex)
            }
            DayTypeToggle(dayType: $dayType)
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var contextLine: String {
        let s = session?.name ?? ""
        return "BLOCK \(String(format: "%02d", selectedBlock)) · W\(week)" + (s.isEmpty ? "" : " · \(s)")
    }

    private var compactBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TRAIN")
                .font(.system(.headline, weight: .heavy).width(.condensed))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(contextLine)
                .font(DSFont.mono)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline)
        }
        .opacity(collapse)
        .allowsHitTesting(false)
    }

    private var blockMenu: some View {
        Menu {
            ForEach(Array(1...currentBlock), id: \.self) { b in
                Button { selectedBlock = b } label: {
                    Label("Block \(String(format: "%02d", b))", systemImage: selectedBlock == b ? "checkmark" : "")
                }
            }
            Divider()
            Button { showPlanBlock = true } label: {
                Label("Plan Block \(String(format: "%02d", currentBlock + 1)) (Coach)",
                      systemImage: "brain.head.profile")
            }
            Button { showReplanBlock = true } label: {
                Label("Re-plan This Block (Coach)", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive) { confirmNewBlock = true } label: {
                Label("Start Empty Block", systemImage: "plus.circle")
            }
        } label: {
            HStack(spacing: 3) {
                Text("BLOCK \(String(format: "%02d", selectedBlock))")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Color.accent)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func saveSessionButton(_ workout: LoggedWorkout) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Button {
                Task {
                    if !health.hasRequested { await health.requestAuthorization() }
                    let ok = await health.saveLiftingSession(start: workout.date, end: .now)
                    if ok {
                        withAnimation(DS.spring) { sessionSaved = true; saveFailed = false }
                        Haptics.success()
                    } else {
                        withAnimation(DS.spring) { saveFailed = true }
                        Haptics.warning()
                    }
                }
            } label: {
                Label(sessionSaved ? "Saved to Apple Health" : "Save Session to Apple Health",
                      systemImage: sessionSaved ? "checkmark.circle.fill" : "heart.fill")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(sessionSaved ? Color.success : Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(sessionSaved ? Color.surfaceElevated : Color.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(sessionSaved)
            if saveFailed {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Couldn't save. Allow Workouts for Tonnage in Settings → tap to open.")
                        .font(.system(.caption2)).foregroundStyle(Color.accent)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reload() {
        guard let session else { return }
        sessionSaved = false
        saveFailed = false
        publishFocus(session)
        switch dayType {
        case .lift:
            store.loadLift(block: selectedBlock, week: week, session: session)
            if let workout = store.workout {
                expandedID = workout.orderedExercises.first(where: { !$0.isFullyLogged })?.persistentModelID
                    ?? workout.orderedExercises.first?.persistentModelID
            }
        case .activeRest, .fullRest:
            store.loadRest(block: selectedBlock, week: week, date: restDate)
        }
        refreshWidget()
    }

    /// Mirror the current TRAIN selection to shared storage so COACH can answer about
    /// the exact session and day type the athlete is looking at.
    private func publishFocus(_ session: SessionTemplate) {
        focusWeek = week
        focusSession = session.subtitle.isEmpty ? session.name : "\(session.name) — \(session.subtitle)"
        focusDayType = dayType.rawValue
    }

    /// Push the current block/week/session + week totals to the home-screen widget.
    private func refreshWidget() {
        guard let session else { return }
        WidgetSync.refresh(context: context, block: selectedBlock, week: week,
                           sessionName: session.name, sessionFocus: session.subtitle)
    }
}

// MARK: - Rest day

private struct RestDayView: View {
    let dayType: DayType
    let isLogged: Bool
    @Binding var date: Date
    let onLog: () -> Void
    let onBackToWorkout: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var dayLabel: String {
        isToday ? "Today"
                : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: dayType == .activeRest ? "figure.walk.motion" : "bed.double.fill")
                .font(.system(size: 46, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)

            VStack(spacing: DS.Spacing.xs) {
                Text(dayType == .activeRest ? "Active Recovery" : "Full Rest")
                    .font(DSFont.title)
                    .foregroundStyle(Color.textPrimary)
                Text(dayType == .activeRest
                     ? "Easy conditioning today — log walks or stairs in MOVE. It counts toward fatigue, not load."
                     : "Recovery is training. Eat, sleep, hydrate — let the work catch up.")
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Pick the day this rest is for — defaults to today, or backdate a missed rest.
            HStack {
                Text("Rest Day").dsLabel()
                Spacer()
                DatePicker("", selection: $date, in: ...Date.now, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.accent)
            }
            .padding(.horizontal, DS.Spacing.sm)

            Button(action: onLog) {
                Label(isLogged ? "Rest Logged for \(dayLabel)" : "Log Rest for \(dayLabel)",
                      systemImage: isLogged ? "checkmark.circle.fill" : "square.and.pencil")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(isLogged ? Color.success : Color.onAccent)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(isLogged ? Color.surfaceElevated : Color.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLogged)

            // Clear way back to logging lifts — subtle before you log, the obvious next
            // step (accent) once the rest is logged, so it's never a dead-end.
            Button(action: onBackToWorkout) {
                Label("Back to Workout", systemImage: "arrow.uturn.backward")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(isLogged ? Color.onAccent : Color.textSecondary)
                    .frame(maxWidth: isLogged ? .infinity : nil)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(isLogged ? Color.accent : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .padding(DS.Spacing.lg)
    }
}

// MARK: - Notes

private struct SessionNotesField: View {
    @Bindable var workout: LoggedWorkout
    @Environment(\.modelContext) private var context
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Session Notes").dsLabel()
            TextField("How did it feel? Sleep, energy, pumps, niggles…",
                      text: $workout.notes, axis: .vertical)
                .font(DSFont.body)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2...6)
                .focused($focused)
                .padding(DS.Spacing.md)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(focused ? Color.accent : Color.hairline, lineWidth: focused ? 1.5 : DS.Stroke.hairline)
                )
                .toolbar {
                    if focused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }.fontWeight(.bold)
                        }
                    }
                }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { try? context.save() }   // persist (+ visible exit) when editing ends
        }
    }
}

#Preview("Train") {
    TrainView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(RestTimer())
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
