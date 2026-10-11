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
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DSFont.screenTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same solid surface as the page, like TRAIN's header: no grey band or divider,
        // and content scrolling underneath stays hidden behind the title.
        .background(Color.surface)
    }
}
