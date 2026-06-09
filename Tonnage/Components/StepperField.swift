import SwiftUI
import TonnageCore

/// Compact −/value/+ stepper with tap-to-type editing. Built for fast, one-handed,
/// mid-workout number entry: pre-filled defaults mean you usually just nudge ±step,
/// but tapping the value brings up a keypad for big jumps.
struct StepperField: View {
    @Binding var value: Double
    var step: Double
    var range: ClosedRange<Double> = 0...2000
    var unit: String = ""
    var isDecimal: Bool = false

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus") { adjust(-step) }

            valueLabel
                .frame(minWidth: 52)

            stepButton(systemName: "plus") { adjust(step) }
        }
        .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(focused ? Color.accent : Color.hairline, lineWidth: focused ? 1.5 : DS.Stroke.hairline)
        )
        .animation(DS.snappySpring, value: focused)
        // One VoiceOver "adjustable" element: swipe up/down to change by `step`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit.isEmpty ? "Value" : unit)
        .accessibilityValue("\(format(value)) \(unit)".trimmingCharacters(in: .whitespaces))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(step)
            case .decrement: adjust(-step)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var valueLabel: some View {
        VStack(spacing: 0) {
            if editing {
                TextField("", text: $draft)
                    .keyboardType(isDecimal ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .font(DSFont.number)
                    .monospacedDigit()                 // match the Text so the swap doesn't shift width
                    .foregroundStyle(Color.accent)
                    .focused($focused)
                    .onSubmit(commit)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { commit() }
                                .fontWeight(.semibold)
                        }
                    }
            } else {
                Text(format(value))
                    .font(DSFont.number)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .onChange(of: focused) { _, isFocused in
            if !isFocused && editing { commit() }
        }
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ delta: Double) {
        value = clamp(value + delta)
        Haptics.impact(.light)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }

    private func beginEditing() {
        draft = value == 0 ? "" : format(value)
        editing = true
        focused = true
    }

    private func commit() {
        if let parsed = Double(draft.replacingOccurrences(of: ",", with: ".")) {
            value = clamp(isDecimal ? parsed : parsed.rounded())
        }
        editing = false
        focused = false
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview("StepperField") {
    struct Demo: View {
        @State var w = 135.0
        @State var r = 6.0
        var body: some View {
            HStack(spacing: DS.Spacing.md) {
                StepperField(value: $w, step: 5, unit: "lb")
                StepperField(value: $r, step: 1, unit: "reps")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
