import SwiftUI
import TonnageCore

/// One-time "what's new" flow shown to existing users after they update to the build that
/// added the coaching intake. Leads with *why* it was added, reassures that their current
/// plan/progress are untouched, then collects the new answers (the same questions new
/// users get at setup, via the shared `CoachingIntakeFields`).
struct CoachingUpdateView: View {
    /// Called when the user saves — caller records that the intake was answered.
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        header
                        whatChanged
                        CoachingIntakeFields()
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                finishButton
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(Color.accent.opacity(0.14))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("What's new").dsLabel()
                Text("Your coach got\nsmarter")
                    .font(DSFont.displayXL)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var whatChanged: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Tonnage now builds your training around where you're starting and what you want to grow — not a one-size template. Answer a few quick questions and your coach and future blocks will tailor to you.")
                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Your current plan, block, and progress stay exactly as they are — nothing changes unless you choose to re-plan.",
                  systemImage: "checkmark.shield.fill")
                .font(DSFont.caption).foregroundStyle(Color.textTertiary)
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
    }

    private var finishButton: some View {
        Button {
            Haptics.success()
            onFinish()
        } label: {
            Text("Save & Continue")
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .background(.ultraThinMaterial)
    }
}

#Preview("Coaching update") {
    CoachingUpdateView(onFinish: {})
        .preferredColorScheme(.dark)
}
