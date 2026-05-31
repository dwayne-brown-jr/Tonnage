import SwiftUI
import TonnageCore

/// First-launch (and Settings-reachable) explainer for how Tonnage decides your
/// workouts: the split, the 5-week block, and the top-set / RPE progression engine.
/// Swipeable, brutalist, skimmable — no walls of text.
struct OnboardingView: View {
    /// Called when the user finishes or skips. Caller dismisses + records completion.
    var onFinish: () -> Void
    /// Label for the final-page primary button ("Start Training" on first run,
    /// "Done" when re-read from Settings).
    var finishTitle: String = "Start Training"

    @Environment(HealthKitManager.self) private var health
    @AppStorage(ProfileStore.Key.split) private var splitRaw = SplitPreset.upperLower.rawValue
    @State private var page = 0
    @State private var connecting = false
    private let lastPage = 5

    private var split: SplitPreset { SplitPreset(rawValue: splitRaw) ?? .upperLower }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    splitPage.tag(1)
                    blockPage.tag(2)
                    callPage.tag(3)
                    topSetPage.tag(4)
                    recoveryPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(DS.spring, value: page)
                controls
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Text("TONNAGE")
                .font(.system(.caption2, weight: .bold)).kerning(3)
                .foregroundStyle(Color.accent)
            Spacer()
            Button {
                Haptics.impact(.light)
                onFinish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.surfaceElevated2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private var controls: some View {
        VStack(spacing: DS.Spacing.lg) {
            HStack(spacing: 6) {
                ForEach(0...lastPage, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accent : Color.textTertiary.opacity(0.4))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(DS.snappySpring, value: page)

            Button {
                if page < lastPage {
                    Haptics.impact(.light)
                    withAnimation(DS.spring) { page += 1 }
                } else {
                    Haptics.success()
                    onFinish()
                }
            } label: {
                Text(page < lastPage ? "Next" : finishTitle)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: Page scaffold

    private func scaffold(icon: String, kicker: String, title: String,
                          @ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(Color.accent.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(kicker).dsLabel()
                    Text(title)
                        .font(DSFont.displayXL)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(DSFont.body)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pages

    private var welcomePage: some View {
        scaffold(icon: "dumbbell.fill", kicker: "How it works", title: "Built to\nprogress you") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("Tonnage runs your split in 5-week blocks — and pre-fills every lift with a suggested weight off your own top sets.")
                bodyText("No guessing what to load. Just show up, hit the call, log your effort.")
            }
        }
    }

    private var splitPage: some View {
        scaffold(icon: "square.grid.2x2.fill", kicker: "Day to day", title: "Your split") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("Pick the split that fits your week — Full Body, Upper/Lower, or Push/Pull/Legs. You choose the day; the exercises, sets, reps, and effort targets stay consistent so they're actually progressable.")
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(split.sessionSpecs, id: \.name) { spec in
                        splitRow(spec.name.uppercased(), spec.focus)
                    }
                }
                bodyText("Set to \(split.label) (\(split.daysPerWeek) days/week) — change it anytime in Settings.")
            }
        }
    }

    private func splitRow(_ name: String, _ focus: String) -> some View {
        HStack {
            Text(name).font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
            Spacer()
            Text(focus).font(DSFont.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var blockPage: some View {
        scaffold(icon: "chart.line.uptrend.xyaxis", kicker: "Week to week", title: "The 5-week wave") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("Each block ramps up, then deloads. The week sets the intent:")
                VStack(spacing: DS.Spacing.sm) {
                    phaseRow("W1", "RAMP", "Ease in — leave 3–4 in reserve")
                    phaseRow("W2", "BUILD", "Add load if last week was clean")
                    phaseRow("W3", "PUSH", "Add load again, or a rep")
                    phaseRow("W4", "PEAK", "True top sets, no grinders")
                    phaseRow("W5", "DELOAD", "~60% load, stay crisp")
                }
            }
        }
    }

    private func phaseRow(_ week: String, _ phase: String, _ detail: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Text(week)
                .font(DSFont.numberSm).foregroundStyle(Color.onAccent)
                .frame(width: 34, height: 26)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(phase).font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.textPrimary)
                Text(detail).font(DSFont.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var callPage: some View {
        scaffold(icon: "scope", kicker: "The progression", title: "The Coach's Call") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("Every lift is pre-filled with a suggested weight × reps — based on last week's top set and how many reps you left in the tank:")
                VStack(spacing: DS.Spacing.sm) {
                    ruleRow("3+ left", "had room", "+5 lb")
                    ruleRow("2 left", "on target", "+5 lb or +1 rep")
                    ruleRow("0–1 left", "near max", "hold, chase +1 rep")
                }
                bodyText("So log your reps left after the top set — that's the dial the engine turns.")
            }
        }
    }

    private func ruleRow(_ rpe: String, _ feel: String, _ result: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(rpe).font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                Text(feel).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: DS.Spacing.sm)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.textTertiary)
            Text(result)
                .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.accent)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var topSetPage: some View {
        scaffold(icon: "trophy.fill", kicker: "What anchors it", title: "Your top set\nleads") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("The heaviest set of each lift is the anchor everything keys off.")
                bodyText("Start a new block and it re-ramps from your best of the last one — strength carries forward, it never resets to zero.")
                bodyText("Need to change something? Edit or swap any exercise for a given week; the next week reverts to the plan.")
            }
        }
    }

    // MARK: Readiness (the daily wedge — explain it AND let them connect right here)

    private var recoveryPage: some View {
        scaffold(icon: "waveform.path.ecg", kicker: "Your daily edge", title: "Train with\nyour recovery") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                bodyText("Each morning Tonnage reads your recovery from Apple Health and scores your readiness 0–100. Run down? The engine automatically holds your loads instead of chasing PRs. Primed? Green light.")
                VStack(spacing: DS.Spacing.sm) {
                    signalRow("heart.fill", "HRV", "Recovery vs. your baseline")
                    signalRow("waveform.path.ecg", "Resting HR", "Elevated = under-recovered")
                    signalRow("bed.double.fill", "Sleep", "Last night vs. a 7.5h target")
                }
                connectControl
                Text("Optional — and you can connect any time in Settings. Without it, everything else still works.")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func signalRow(_ icon: String, _ name: String, _ detail: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.textPrimary)
                Text(detail).font(DSFont.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    @ViewBuilder private var connectControl: some View {
        if !health.isAvailable {
            Label("Apple Health isn't available on this device", systemImage: "info.circle")
                .font(DSFont.caption).foregroundStyle(Color.textTertiary)
        } else if health.hasRequested {
            Label("Apple Health connected", systemImage: "checkmark.seal.fill")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Color.success)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(Color.success.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        } else {
            Button(action: connectHealth) {
                HStack(spacing: DS.Spacing.sm) {
                    if connecting {
                        ProgressView().tint(Color.onAccent)
                    } else {
                        Image(systemName: "heart.fill").font(.system(size: 15, weight: .bold))
                    }
                    Text(connecting ? "Connecting…" : "Connect Apple Health")
                        .font(.system(.subheadline, weight: .bold))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(connecting)
        }
    }

    private func connectHealth() {
        guard !connecting else { return }
        connecting = true
        Haptics.impact(.light)
        Task {
            await health.requestAuthorization()
            connecting = false
            Haptics.success()
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onFinish: {})
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
