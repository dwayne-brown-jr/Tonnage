import SwiftUI
import SwiftData
import TonnageCore

/// One logged set, rendered from the exercise's metric list: strength shows
/// weight × reps + RPE; cardio shows time / distance / flights as appropriate.
/// Ends with the signature completion toggle (spring + accent fill + haptic).
struct SetRow: View {
    @Bindable var set: LoggedSet
    /// Display label for the set number — "1", "2"… for working sets, "W" for warm-ups.
    let label: String
    let metrics: [SetMetric]
    /// What this set looked like in the last comparable session (working sets only) —
    /// shown as a tappable ghost line that fills weight + reps in one tap.
    var ghost: LastTopSet? = nil
    /// The previous completed set's logged effort, surfaced as a "same as last set"
    /// shortcut in the reps-left menu.
    var previousRPE: Double? = nil
    let onToggleComplete: () -> Void
    let onToggleWarmup: () -> Void
    let onDelete: () -> Void
    var onApplyGhost: ((LastTopSet) -> Void)? = nil
    /// Called after set metadata (note, AMRAP) changes so the owner can persist.
    var onMetaChanged: (() -> Void)? = nil
    /// Inserts a drop set right after this one (nil hides the menu item, e.g. cardio).
    var onAddDropSet: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editingNote = false
    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            controlsRow
            if set.isAMRAP {
                amrapLine
            }
            if let ghost, !set.completed, !set.isWarmup {
                ghostLine(ghost)
            }
            if let note = set.note, !note.isEmpty {
                noteLine(note)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(set.isWarmup ? 0.8 : (set.completed ? 1 : 0.92))
        .contextMenu {
            Button(action: onToggleWarmup) {
                Label(set.isWarmup ? "Mark as Working Set" : "Mark as Warm-up",
                      systemImage: set.isWarmup ? "dumbbell" : "flame")
            }
            if let onAddDropSet, !set.isWarmup {
                Button(action: onAddDropSet) {
                    Label("Add Drop Set", systemImage: "arrow.down.right")
                }
            }
            if !set.isWarmup {
                Button {
                    set.isAMRAP.toggle()
                    onMetaChanged?()
                    Haptics.selection()
                } label: {
                    Label(set.isAMRAP ? "Unmark AMRAP" : "Mark as AMRAP", systemImage: "bolt")
                }
            }
            Button {
                noteDraft = set.note ?? ""
                editingNote = true
            } label: {
                Label((set.note?.isEmpty ?? true) ? "Add Note" : "Edit Note", systemImage: "note.text")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Set", systemImage: "trash")
            }
        }
        .alert("Set Note", isPresented: $editingNote) {
            TextField("e.g. felt heavy, grip gave out", text: $noteDraft)
            Button("Save") {
                let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                set.note = trimmed.isEmpty ? nil : trimmed
                onMetaChanged?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A short note just for this set.")
        }
    }

    /// "Go to failure" marker under the inputs.
    private var amrapLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
            Text("AMRAP — as many reps as possible")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.accent)
        .padding(.leading, 16 + DS.Spacing.sm)
        .padding(.vertical, 2)
        .accessibilityLabel("AMRAP set: as many reps as possible")
    }

    /// Per-set note, shown under the inputs. Tap to edit.
    private func noteLine(_ note: String) -> some View {
        Button {
            noteDraft = note
            editingNote = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(.system(size: 9, weight: .bold))
                Text(note)
                    .font(.system(size: 11))
                    .italic()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.leading, 16 + DS.Spacing.sm)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set note: \(note)")
        .accessibilityHint("Tap to edit")
    }

    /// The set label, its metric controls, and the complete button. Every DSFont is
    /// text-style based, so the controls grow with Dynamic Type — at accessibility sizes a
    /// single row of two steppers plus the RPE chip and the button exceeds the screen width,
    /// which forces the whole TRAIN page wider than its viewport and clips it on both edges.
    /// Stack them instead once the text gets that large.
    @ViewBuilder private var controlsRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    setLabel
                    Spacer(minLength: 0)
                    CompleteButton(completed: set.completed, action: onToggleComplete)
                }
                ForEach(metrics) { metric in
                    control(for: metric).frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                setLabel
                ForEach(metrics) { metric in
                    control(for: metric)
                }
                Spacer(minLength: 0)
                CompleteButton(completed: set.completed, action: onToggleComplete)
            }
        }
    }

    private var setLabel: some View {
        Text(label)
            .font(DSFont.numberSm)
            .foregroundStyle(set.isWarmup ? Color.textTertiary : (set.completed ? Color.accent : Color.textTertiary))
            .lineLimit(1)
            .frame(minWidth: 16, alignment: .leading)
    }

    /// "LAST WK 225 × 5" under the inputs — tap to fill this set with last week's numbers.
    private func ghostLine(_ ghost: LastTopSet) -> some View {
        Button {
            onApplyGhost?(ghost)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .bold))
                Text("LAST WK \(CoachEngine.fmt(ghost.weight)) × \(ghost.reps)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                Text("· tap to use")
                    .font(.system(size: 11))
                    .opacity(0.7)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.leading, 16 + DS.Spacing.sm)   // align under the inputs, past the set label
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last week: \(CoachEngine.fmt(ghost.weight)) pounds for \(ghost.reps) reps")
        .accessibilityHint("Fills this set with last week's weight and reps")
    }

    @ViewBuilder private func control(for metric: SetMetric) -> some View {
        switch metric {
        case .weight:
            StepperField(value: $set.weight, step: 5, range: 0...2000, unit: "lb")
        case .reps:
            StepperField(value: doubleBinding(\.reps), step: 1, range: 0...100, unit: "reps")
        case .rpe:
            // Nudge: a completed working set with no reps-left logged loses the data the
            // progression engine runs on — outline the chip so it's clearly worth a tap.
            RPEChip(rpe: $set.rpe,
                    needsAttention: set.completed && set.rpe == nil && !set.isWarmup,
                    previousRPE: previousRPE)
        case .time:
            TimeStepperField(seconds: intOptionalBinding(\.durationSeconds))
        case .distance:
            StepperField(value: doubleOptionalBinding(\.distanceMiles), step: 0.1, range: 0...200, unit: "mi", isDecimal: true)
        case .flights:
            StepperField(value: intOptionalDoubleBinding(\.flights), step: 1, range: 0...999, unit: "flights")
        }
    }

    // MARK: Binding adapters

    private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<LoggedSet, Int>) -> Binding<Double> {
        Binding(get: { Double(set[keyPath: keyPath]) }, set: { set[keyPath: keyPath] = Int($0) })
    }
    private func doubleOptionalBinding(_ keyPath: ReferenceWritableKeyPath<LoggedSet, Double?>) -> Binding<Double> {
        Binding(get: { set[keyPath: keyPath] ?? 0 }, set: { set[keyPath: keyPath] = $0 })
    }
    private func intOptionalBinding(_ keyPath: ReferenceWritableKeyPath<LoggedSet, Int?>) -> Binding<Int> {
        Binding(get: { set[keyPath: keyPath] ?? 0 }, set: { set[keyPath: keyPath] = $0 })
    }
    private func intOptionalDoubleBinding(_ keyPath: ReferenceWritableKeyPath<LoggedSet, Int?>) -> Binding<Double> {
        Binding(get: { Double(set[keyPath: keyPath] ?? 0) }, set: { set[keyPath: keyPath] = Int($0) })
    }
}

/// Filled-accent completion control with a satisfying spring + bounce. 44pt tap target.
private struct CompleteButton: View {
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(completed ? Color.accent : Color.surfaceElevated2)
                Circle().strokeBorder(completed ? Color.clear : Color.textTertiary, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.onAccent)
                    .opacity(completed ? 1 : 0)
                    .scaleEffect(completed ? 1 : 0.5)
            }
            .frame(width: 34, height: 34)
            .scaleEffect(completed ? 1.0 : 0.94)
            .shadow(color: completed ? Color.accent.opacity(0.5) : .clear, radius: 8, y: 2)
            .symbolEffect(.bounce, value: completed)
            .frame(width: 44, height: 44)        // ≥44pt tap target (HIG / sweaty fingers)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.spring, value: completed)
        .accessibilityLabel(completed ? "Completed set" : "Mark set complete")
    }
}

/// Tap-to-pick effort chip, logged as "reps left" (reps in reserve). Stored as RPE
/// under the hood (RPE = 10 − reps left) — the scale the progression engine reads —
/// but the user only ever sees reps left.
private struct RPEChip: View {
    @Binding var rpe: Double?
    var needsAttention: Bool = false
    /// The previous set's logged effort — offered as a one-tap "same as last set" shortcut.
    var previousRPE: Double? = nil

    /// Whole reps-left choices, each mapped to the RPE the engine/store uses.
    private let options: [(label: String, rpe: Double?)] = [
        ("Skip", nil),
        ("0 · all-out", 10),
        ("1 left", 9),
        ("2 left", 8),
        ("3 left", 7),
        ("4+ · easy", 6),
    ]

    var body: some View {
        Menu {
            if let prev = previousRPE, rpe == nil {
                Button {
                    rpe = prev
                    Haptics.selection()
                } label: {
                    Label("Same as last set · \(CoachEngine.repsLeftLabel(fromRPE: prev)) left",
                          systemImage: "clock.arrow.circlepath")
                }
                Divider()
            }
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                Button {
                    rpe = option.rpe
                    Haptics.selection()
                } label: {
                    Text(option.label)
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text(rpe.map { CoachEngine.repsLeftLabel(fromRPE: $0) } ?? "—")
                    .font(DSFont.numberSm)
                    .monospacedDigit()
                    .foregroundStyle(rpe == nil ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("LEFT")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            // A hard 44pt width broke "LEFT" mid-word once Dynamic Type grew past it.
            .frame(minWidth: 44)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay {
                if needsAttention {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reps left in reserve")
        .accessibilityValue(rpe.map { CoachEngine.repsLeftLabel(fromRPE: $0) } ?? "Not logged")
        .accessibilityHint("Pick how many reps you had left")
    }
}
