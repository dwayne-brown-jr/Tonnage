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
    let onToggleComplete: () -> Void
    let onToggleWarmup: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .font(DSFont.numberSm)
                .foregroundStyle(set.isWarmup ? Color.textTertiary : (set.completed ? Color.accent : Color.textTertiary))
                .frame(width: 16)

            ForEach(metrics) { metric in
                control(for: metric)
            }

            Spacer(minLength: 0)

            CompleteButton(completed: set.completed, action: onToggleComplete)
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(set.isWarmup ? 0.8 : (set.completed ? 1 : 0.92))
        .contextMenu {
            Button(action: onToggleWarmup) {
                Label(set.isWarmup ? "Mark as Working Set" : "Mark as Warm-up",
                      systemImage: set.isWarmup ? "dumbbell" : "flame")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Set", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private func control(for metric: SetMetric) -> some View {
        switch metric {
        case .weight:
            StepperField(value: $set.weight, step: 5, range: 0...2000, unit: "lb")
        case .reps:
            StepperField(value: doubleBinding(\.reps), step: 1, range: 0...100, unit: "reps")
        case .rpe:
            RPEChip(rpe: $set.rpe)
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
                Text("LEFT")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 44)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reps left in reserve")
        .accessibilityValue(rpe.map { CoachEngine.repsLeftLabel(fromRPE: $0) } ?? "Not logged")
        .accessibilityHint("Pick how many reps you had left")
    }
}
