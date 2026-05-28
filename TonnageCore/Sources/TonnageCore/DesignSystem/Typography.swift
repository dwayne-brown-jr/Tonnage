import SwiftUI

/// Type scale. Built on text-style system fonts so everything scales with Dynamic
/// Type for free. Headers use a heavy CONDENSED width (brutalist poster feel);
/// all numbers + metadata use a MONOSPACED design.
///
/// NOTE: this is the seam for a bundled display font. Swapping the `.system(...)`
/// display faces for `Font.custom("BigShouldersDisplay-…", size:, relativeTo:)`
/// later changes only this file.
public enum DSFont {

    // Display / headers — heavy + condensed.
    public static var displayXL: Font { .system(.largeTitle, design: .default, weight: .heavy).width(.condensed) }
    public static var display:   Font { .system(.title,      design: .default, weight: .heavy).width(.condensed) }
    public static var title:     Font { .system(.title2,     design: .default, weight: .bold ).width(.condensed) }
    public static var headline:  Font { .system(.headline) }

    // Body text.
    public static var body:      Font { .system(.body) }
    public static var callout:   Font { .system(.callout,  weight: .medium) }
    public static var caption:   Font { .system(.caption,  weight: .medium) }

    // Numbers + metadata — monospaced.
    public static var numberXL:  Font { .system(.largeTitle,  design: .monospaced, weight: .bold) }
    public static var number:    Font { .system(.title3,      design: .monospaced, weight: .semibold) }
    public static var numberSm:  Font { .system(.subheadline, design: .monospaced, weight: .medium) }
    public static var mono:      Font { .system(.caption,     design: .monospaced, weight: .medium) }
}

// MARK: - Label styling

/// Small uppercase, tracked, secondary-colored label. Use `.dsLabel()` rather than
/// hand-typing ALL-CAPS strings, so casing/tracking stay consistent app-wide.
public struct DSLabelModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(DSFont.caption)
            .textCase(.uppercase)
            .kerning(0.9)
            .foregroundStyle(Color.textSecondary)
    }
}

public extension View {
    func dsLabel() -> some View { modifier(DSLabelModifier()) }
}
