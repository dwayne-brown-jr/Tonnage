import SwiftUI

/// Brutalist surface card: elevated dark fill, hairline stroke, near-sharp corner,
/// subtle depth. The base container for grouped content across the app.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = DS.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    }
}

#Preview("Card") {
    ZStack {
        Color.surface.ignoresSafeArea()
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("TONNAGE").dsLabel()
                Text("Total Volume").font(DSFont.title).foregroundStyle(Color.textPrimary)
                Text("18,420 lb").font(DSFont.numberXL).foregroundStyle(Color.accent)
            }
        }
        .padding(DS.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
