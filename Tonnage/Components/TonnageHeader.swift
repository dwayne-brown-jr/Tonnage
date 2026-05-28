import SwiftUI
import TonnageCore

/// Standard pinned screen header for the secondary tabs (Coach / Move / Data /
/// Settings): a big condensed title with an optional trailing accessory, on a
/// translucent material with a hairline divider. No "TONNAGE" wordmark — the tab bar
/// already is the app's identity. (TRAIN uses its own collapsing large-title header.)
struct TonnageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DSFont.display)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline)
        }
    }
}
