import SwiftUI
import TonnageCore

/// Floating rest-timer bar: a glowing accent countdown ring + label + controls.
/// Sits above the tab bar while a rest is active.
struct RestTimerBar: View {
    @Environment(RestTimer.self) private var timer

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.phase == .done ? "Rest Complete" : "Resting").dsLabel()
                // Wraps to a second line rather than truncating — the exercise name is
                // the point of this label.
                Text(displayLabel)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
        .padding(.leading, DS.Spacing.md)
        .padding(.trailing, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        // Opaque top step, not a material: the bar floats over cards, and a blur at card
        // brightness let the content scrolling beneath read through at the same level.
        .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(Color.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.accent.opacity(0.25), radius: 18, x: 0, y: 6)
        .padding(.horizontal, DS.Spacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var displayLabel: String {
        if timer.phase == .done { return "Go — next set" }
        return timer.label.isEmpty ? "Next set" : timer.label
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.surfaceElevated, lineWidth: 6)   // track recessed into the bar
            Circle()
                .trim(from: 0, to: timer.phase == .done ? 1 : timer.progress)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.accent.opacity(0.6), radius: 6)
                .animation(.linear(duration: 0.25), value: timer.progress)
            if timer.phase == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color.accent)
                    .symbolEffect(.bounce, value: timer.phase == .done)
            } else {
                Text(mmss(timer.remainingSeconds))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: 54, height: 54)
    }

    @ViewBuilder private var controls: some View {
        if timer.phase == .running {
            pill("+30") { timer.addTime(30) }
                .accessibilityLabel("Add 30 seconds")
            pill("Skip", prominent: true) { withAnimation(DS.spring) { timer.skip() } }
        } else {
            pill("Done", prominent: true) { withAnimation(DS.spring) { timer.skip() } }
        }
    }

    private func pill(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(prominent ? Color.onAccent : Color.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, minHeight: 44)    // full tap target; never squeezed by the label
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(prominent ? Color.accent : Color.surfaceElevated)
                )
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
