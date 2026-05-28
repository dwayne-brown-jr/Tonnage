import SwiftUI
import TonnageCore

/// "Tell your coach about you" — captures the athlete profile that personalizes the
/// AI coach. Shown once after first-run onboarding, and re-editable from Settings.
struct ProfileSetupView: View {
    var onFinish: () -> Void
    var finishTitle: String = "Start Training"

    @AppStorage(ProfileStore.Key.name) private var name = ""

    private var canFinish: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .fill(Color.accent.opacity(0.14))
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.accent)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Your coach").dsLabel()
                            Text("Tell your coach\nabout you")
                                .font(DSFont.displayXL)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Just enough to tailor your coaching. This stays on your device — your workouts and your coach are yours alone.")
                                .font(DSFont.callout)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ProfileFields()
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)

                Button {
                    Haptics.success()
                    onFinish()
                } label: {
                    Text(finishTitle)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .opacity(canFinish ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canFinish)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
            }
        }
    }
}

#Preview("Profile setup") {
    ProfileSetupView(onFinish: {})
        .preferredColorScheme(.dark)
}
