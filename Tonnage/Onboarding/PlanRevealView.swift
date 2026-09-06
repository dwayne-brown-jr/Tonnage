import SwiftUI
import TonnageCore

/// First-run payoff — the "personalized outcome reveal." After the profile + split + plan build,
/// this reflects the athlete's own choices back and sells the outcome before TRAIN, so onboarding
/// ends on value ("here's YOUR plan") instead of dumping them into a screen.
struct PlanRevealView: View {
    var onFinish: () -> Void

    private var profile: CoachProfile { ProfileStore.current }
    private var split: SplitPreset { ProfileStore.split }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Spacer(minLength: 0)

                ZStack {
                    Circle().fill(Color.accent.opacity(0.15))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
                .frame(width: 72, height: 72)

                Text("Plan ready").dsLabel()
                Text(headline)
                    .font(.system(size: 34, weight: .heavy).width(.condensed))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DS.Spacing.sm)

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    revealRow("square.grid.2x2.fill", "\(split.label) — \(split.daysPerWeek) days a week")
                    revealRow("scope", "Every lift comes pre-loaded with a suggested weight off your own top sets — no guessing what to put on the bar.")
                    revealRow("chart.line.uptrend.xyaxis", "5-week blocks: Week 1 eases you in, and by Week 4 you're chasing true top sets — built for \(goalText).")
                    revealRow("waveform.path.ecg", "Each morning it reads your recovery and holds or pushes your loads to match.")
                }

                Spacer(minLength: 0)

                Button(action: onFinish) {
                    Text("Start Training")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }

    private var headline: String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Your plan is\nbuilt" : "\(name), your\nplan is built"
    }

    /// Goal phrased to fit "built for ___". Falls back to a neutral phrase if unset.
    private var goalText: String {
        let g = profile.goal.label.lowercased()
        return g.isEmpty ? "steady progress" : g
    }

    private func revealRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
                .frame(width: 24)
            Text(text)
                .font(DSFont.callout)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview("Plan reveal") {
    PlanRevealView(onFinish: {})
        .preferredColorScheme(.dark)
}
