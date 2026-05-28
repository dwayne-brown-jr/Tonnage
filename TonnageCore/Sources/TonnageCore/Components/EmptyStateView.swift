import SwiftUI

/// Designed empty state — used by scaffold tabs now and by real lists later.
/// Never leave a blank screen.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)

            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DSFont.title)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty state") {
    ZStack {
        Color.surface.ignoresSafeArea()
        EmptyStateView(
            systemImage: "dumbbell.fill",
            title: "No Sets Yet",
            message: "Log a set to start tracking your progression."
        )
    }
    .preferredColorScheme(.dark)
}
