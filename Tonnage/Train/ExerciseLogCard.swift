import SwiftUI
import SwiftData
import TonnageCore

/// Expandable exercise card: collapsed shows prescription + progress + Coach's Call
/// teaser; expanded reveals the call banner, last-week reference, and set logging.
struct ExerciseLogCard: View {
    @Bindable var exercise: LoggedExercise
    let guidance: ExerciseGuidance?
    @Binding var expandedID: PersistentIdentifier?
    let store: TrainStore

    @Environment(RestTimer.self) private var restTimer

    @State private var showingDirections = false
    @State private var showingPlates = false
    @State private var formMode: ExerciseFormMode?

    private var isExpanded: Bool { expandedID == exercise.persistentModelID }
    private var metrics: [SetMetric] { ExerciseLibrary.metrics(for: exercise.name, isCardio: exercise.isCardio) }

    private var prescription: String {
        if exercise.isCardio { return "\(exercise.repRange) · \(exercise.rpeTarget)" }
        return "\(exercise.prescribedSets) × \(exercise.repRange) · \(CoachEngine.repsLeftTarget(from: exercise.rpeTarget)) left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                expandedBody
                    .padding(.top, DS.Spacing.md)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(isExpanded ? Color.accent.opacity(0.35) : Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .sheet(isPresented: $showingDirections) {
            ExerciseDirectionsSheet(name: exercise.name, isCardio: exercise.isCardio,
                                    coachNote: exercise.prescriptionNotes)
        }
        .sheet(isPresented: $showingPlates) {
            PlateCalculatorSheet(initialTarget: initialPlateTarget)
        }
        .sheet(item: $formMode) { mode in
            EditExerciseSheet(store: store, exercise: exercise, mode: mode)
        }
    }

    private var initialPlateTarget: Double {
        let heaviest = (exercise.sets ?? []).map(\.weight).max() ?? 0
        return heaviest > 0 ? heaviest : 135
    }

    // MARK: Header

    /// Whole row toggles expand; the info button and ••• menu tap independently.
    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.xs) {
                    if exercise.isCompound { tag("COMPOUND") }
                    if exercise.isCardio { tag("CARDIO") }
                }
                Text(exercise.name)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(prescription)
                    .font(DSFont.numberSm)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: DS.Spacing.xs)
            progressBadge
            iconButton("info.circle") { showingDirections = true }
            actionsMenu
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .padding(.leading, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DS.spring) {
                expandedID = isExpanded ? nil : exercise.persistentModelID
            }
            Haptics.impact(.light)
        }
    }

    private var actionsMenu: some View {
        Menu {
            if !exercise.isCardio {
                Button { showingPlates = true } label: { Label("Plate Calculator", systemImage: "circle.hexagongrid.fill") }
            }
            Button { formMode = .edit } label: { Label("Edit Prescription", systemImage: "slider.horizontal.3") }
            Button { formMode = .swap } label: { Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath") }
            Divider()
            Button(role: .destructive) {
                withAnimation(DS.spring) { store.removeExercise(exercise) }
            } label: { Label("Remove", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressBadge: some View {
        let done = exercise.completedSetCount
        let total = (exercise.sets ?? []).count
        let complete = exercise.isFullyLogged
        return Text("\(done)/\(total)")
            .font(DSFont.numberSm)
            .monospacedDigit()
            .foregroundStyle(complete ? Color.onAccent : Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(complete ? Color.success : Color.surfaceElevated2))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .kerning(0.8)
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let call = guidance?.call { coachsCallBanner(call) }
            if let last = guidance?.last { lastWeekLine(last) }
            if !exercise.prescriptionNotes.isEmpty {
                Label(exercise.prescriptionNotes, systemImage: "text.alignleft")
                    .font(.system(.caption))
                    .foregroundStyle(Color.textSecondary)
                    .labelStyle(.titleAndIcon)
            }

            Divider().overlay(Color.hairline)

            VStack(spacing: DS.Spacing.xs) {
                ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.persistentModelID) { i, set in
                    VStack(spacing: 4) {
                        if let result = nextSetCue(forIndex: i) {
                            nextSetCueChip(result.cue, targetWeight: result.weight, set: set)
                        }
                        SetRow(
                            set: set,
                            index: i + 1,
                            metrics: metrics,
                            onToggleComplete: { toggleComplete(set) },
                            onDelete: { store.deleteSet(set, from: exercise) }
                        )
                    }
                }
            }

            Button {
                store.addSet(to: exercise)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleComplete(_ set: LoggedSet) {
        withAnimation(DS.spring) { set.completed.toggle() }
        if set.completed {
            Haptics.success()
            if !exercise.isCardio {
                restTimer.startRest(forCompound: exercise.isCompound, label: exercise.name)
            }
        } else {
            Haptics.impact(.rigid)
        }
        store.save()
    }

    // MARK: Set-to-set cue

    /// The reactive cue to show above set `i` — only when it's the next set to do and
    /// the set just before it was completed with a logged RPE. `weight` is the
    /// suggested load (previous set's weight + the cue's delta).
    private func nextSetCue(forIndex i: Int) -> (cue: NextSetCue, weight: Double)? {
        guard !exercise.isCardio, i > 0 else { return nil }
        let sets = exercise.orderedSets
        guard i < sets.count, !sets[i].completed else { return nil }
        let prev = sets[i - 1]
        guard prev.completed, let rpe = prev.rpe else { return nil }
        let target = CoachEngine.targetRPE(forSetIndex: i - 1, in: exercise.rpeTarget)
        let cue = CoachEngine.nextSetCue(loggedRPE: rpe, targetRPE: target, isCompound: exercise.isCompound,
                                         holdProgression: store.readinessHoldsProgression)
        return (cue, max(0, prev.weight + cue.weightDeltaLb))
    }

    /// Tappable cue chip: applying it sets the next set's weight to the suggestion.
    private func nextSetCueChip(_ cue: NextSetCue, targetWeight: Double, set: LoggedSet) -> some View {
        let canApply = cue.weightDeltaLb != 0
        return Button {
            guard canApply else { return }
            withAnimation(DS.snappySpring) { set.weight = targetWeight }
            store.save()
            Haptics.impact(.light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cueIcon(cue.direction)).font(.system(size: 11, weight: .black))
                Text(cue.label).font(.system(.caption, weight: .bold))
                if canApply {
                    Text("· tap → \(CoachEngine.fmt(targetWeight)) lb")
                        .font(.system(.caption2, weight: .medium)).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(cueForeground(cue.direction))
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 5)
            .background(cueBackground(cue.direction), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canApply)
    }

    private func cueIcon(_ d: NextSetCue.Direction) -> String {
        switch d {
        case .up:   "arrow.up"
        case .hold: "equal"
        case .down: "arrow.down"
        }
    }
    private func cueForeground(_ d: NextSetCue.Direction) -> Color {
        switch d {
        case .up:   Color.onAccent
        case .hold: Color.textSecondary
        case .down: Color.danger
        }
    }
    private func cueBackground(_ d: NextSetCue.Direction) -> Color {
        switch d {
        case .up:   Color.accent
        case .hold: Color.surfaceElevated2
        case .down: Color.danger.opacity(0.16)
        }
    }

    private func coachsCallBanner(_ call: CoachsCall) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: emphasisIcon(call.emphasis))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("COACH'S CALL").dsLabel()
                Text(call.headline)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.accent).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func lastWeekLine(_ last: LastTopSet) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("LAST WK").dsLabel()
            Text("\(CoachEngine.fmt(last.weight)) × \(last.reps)")
                .font(DSFont.numberSm)
                .foregroundStyle(Color.textSecondary)
            if let rpe = last.rpe {
                Text("· \(CoachEngine.repsLeftLabel(fromRPE: rpe)) left")
                    .font(DSFont.numberSm)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func emphasisIcon(_ e: CoachsCall.Emphasis) -> String {
        switch e {
        case .ramp:     "arrow.up.forward.circle.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .hold:     "equal.circle.fill"
        case .deload:   "arrow.down.circle.fill"
        case .neutral:  "info.circle.fill"
        }
    }
}
