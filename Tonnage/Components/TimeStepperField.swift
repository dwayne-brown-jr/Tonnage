import SwiftUI
import TonnageCore

/// −/value/+ field for durations, displayed mm:ss. Steps by 30s; tap the value to
/// type "mm:ss" or a plain minute count. Matches `StepperField`'s look.
struct TimeStepperField: View {
    @Binding var seconds: Int
    var step: Int = 30
    var range: ClosedRange<Int> = 0...(24 * 3600)

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus") { adjust(-step) }

            VStack(spacing: 0) {
                if editing {
                    TextField("", text: $draft)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.center)
                        .font(DSFont.number)
                        .foregroundStyle(Color.accent)
                        .focused($focused)
                        .onSubmit(commit)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { commit() }.fontWeight(.semibold)
                            }
                        }
                } else {
                    Text(formatted)
                        .font(DSFont.number)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEditing() }
                }
                Text("time")
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minWidth: 56)
            .padding(.vertical, DS.Spacing.sm)
            .onChange(of: focused) { _, isFocused in
                if !isFocused && editing { commit() }
            }

            stepButton(systemName: "plus") { adjust(step) }
        }
        .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(focused ? Color.accent : Color.hairline, lineWidth: focused ? 1.5 : DS.Stroke.hairline)
        )
        .animation(DS.snappySpring, value: focused)
    }

    private var formatted: String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
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

    private func adjust(_ delta: Int) {
        seconds = min(max(seconds + delta, range.lowerBound), range.upperBound)
        Haptics.impact(.light)
    }

    private func beginEditing() {
        draft = seconds == 0 ? "" : formatted
        editing = true
        focused = true
    }

    private func commit() {
        seconds = min(max(parse(draft), range.lowerBound), range.upperBound)
        editing = false
        focused = false
    }

    /// "12:30" → 750s · "12" → 720s (minutes) · "" → 0.
    private func parse(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            let m = Int(parts.first ?? "") ?? 0
            let s = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            return m * 60 + min(s, 59)
        }
        return (Int(trimmed) ?? 0) * 60
    }
}

#Preview("TimeStepperField") {
    struct Demo: View {
        @State var t = 600
        var body: some View {
            TimeStepperField(seconds: $t)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surface)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
