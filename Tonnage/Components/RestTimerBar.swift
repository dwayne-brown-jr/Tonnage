import SwiftUI
import TonnageCore

/// Floating rest-timer bar: a glowing accent countdown ring + label + controls.
/// Sits above the tab bar while a rest is active.
struct RestTimerBar: View {
    @Environment(RestTimer.self) private var timer

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.phase == .done ? "Rest Complete" : "Resting").dsLabel()
                Text(displayLabel)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: DS.Spacing.sm)
            controls
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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
            Circle().stroke(Color.surfaceElevated2, lineWidth: 6)
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
            pill("+30s") { timer.addTime(30) }
            pill("Skip", prominent: true) { withAnimation(DS.spring) { timer.skip() } }
        } else {
            pill("Done", prominent: true) { withAnimation(DS.spring) { timer.skip() } }
        }
    }

    private func pill(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(prominent ? Color.onAccent : Color.textPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(prominent ? Color.accent : Color.surfaceElevated2)
                )
        }
        .buttonStyle(.plain)
    }

    private func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
