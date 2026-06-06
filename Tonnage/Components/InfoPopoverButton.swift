import SwiftUI
import TonnageCore

/// A subtle "i" that pops a plain-language explainer — the "why this matters" pattern,
/// reusable across metric cards so no number is ever a mystery.
struct InfoPopoverButton: View {
    let title: String
    let message: String
    @State private var show = false

    var body: some View {
        Button {
            show = true
            Haptics.selection()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(title)
                    .font(DSFont.title)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.lg)
            .frame(width: 290)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Color.surfaceElevated)
        }
    }
}
