import SwiftUI
import TonnageCore

/// Standard pinned screen header for the secondary tabs (Coach / Move / Data /
/// Settings): a compact condensed title with an optional trailing accessory, on the
/// page's own surface so it reads like TRAIN's header. (TRAIN uses its own collapsing
/// header, which carries the TONNAGE wordmark.)
struct TonnageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        Text(title)
            .font(DSFont.screenTitle)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The accessory floats over the right edge, centered on the title, so its size
            // (a pill on Coach, a round button on Data) can never move the title — every
            // tab's title sits in exactly the same spot.
            .overlay(alignment: .trailing) { trailing() }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.md)
            // Same solid surface as the page, like TRAIN's header: no grey band or divider,
            // and content scrolling underneath stays hidden behind the title.
            .background(Color.surface)
    }
}
