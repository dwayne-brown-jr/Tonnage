import SwiftUI
import TonnageCore

/// The day's training-readiness glance at the top of TRAIN — score ring, band, and a
/// one-line note. Tap (handled by the parent) opens the full Recovery screen. A
/// chevron signals it drills in.
struct ReadinessCard: View {
    let readiness: Readiness
    /// Tapping the card body opens the Recovery screen (handled by the parent).
    var onOpen: () -> Void = {}
    @State private var showInfo = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack {
                Circle().stroke(bandColor.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(readiness.score ?? 0) / 100)
                    .stroke(bandColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(readiness.score.map(String.init) ?? "—")
                    .font(DSFont.number)
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    Text("READINESS").dsLabel()
                    Text(readiness.headline)
                        .font(.system(.caption, weight: .heavy).width(.condensed))
                        .foregroundStyle(bandColor)
                    infoButton
                }
                Text(readiness.trainingNote)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(bandColor.opacity(0.30), lineWidth: DS.Stroke.hairline)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness \(readiness.score.map(String.init) ?? "unavailable"), \(readiness.headline). \(readiness.trainingNote)")
        .accessibilityHint("Opens recovery details")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: "Explain the readiness score") { showInfo = true }
    }

    /// Subtle "i" that pops over a plain-language explainer + the band legend, so the
    /// number is never a mystery — without forcing a trip into the Recovery screen.
    private var infoButton: some View {
        Button {
            showInfo = true
            Haptics.selection()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain the readiness score")
        .popover(isPresented: $showInfo) {
            ReadinessInfoPopover()
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.surfaceElevated)
        }
    }

    private var bandColor: Color {
        switch readiness.band {
        case .primed, .ready: Color.success
        case .compromised:    Color.accent
        case .drained:        Color.danger
        case .unknown:        Color.textTertiary
        }
    }
}

/// The explainer shown from the card's "i" — what the score is, plus the band legend.
private struct ReadinessInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Readiness")
                    .font(DSFont.title)
                    .foregroundStyle(Color.textPrimary)
                Text("A 0–100 read of how recovered you are today — your HRV, resting heart rate, and sleep measured against your own baselines. It steers how hard to train, and isn't a medical score.")
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                band(Color.success, "80–100", "Primed", "Chase your top sets.")
                band(Color.success, "65–79",  "Ready", "Progress as planned.")
                band(Color.accent,  "45–64",  "Under-recovered", "Hold loads — maybe cut a set.")
                band(Color.danger,  "0–44",   "Drained", "Active rest or go lighter.")
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 290)
    }

    private func band(_ color: Color, _ range: String, _ name: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(range).font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                    Text(name).font(.system(.caption, weight: .bold)).foregroundStyle(color)
                }
                Text(note).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Readiness") {
    VStack(spacing: 16) {
        ReadinessCard(readiness: ReadinessEngine.evaluate(
            ReadinessInputs(hrvMs: 78, hrvBaselineMs: 65, restingHR: 52, restingHRBaseline: 56,
                            sleepHours: 7.8, trainedYesterday: false)))
        ReadinessCard(readiness: ReadinessEngine.evaluate(
            ReadinessInputs(hrvMs: 42, hrvBaselineMs: 65, restingHR: 64, restingHRBaseline: 56,
                            sleepHours: 5.4, trainedYesterday: true)))
    }
    .padding()
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
