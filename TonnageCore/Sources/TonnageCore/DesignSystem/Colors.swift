import SwiftUI

/// Semantic, dark-only palette. Raw hex lives ONLY in this file — views reference
/// names (`.surface`, `.accent`, …), never literals.
public extension Color {

    /// Base app background — near-black, not pure black (reads as surface, not void).
    static let surface          = Color(hex: 0x0B0B0D)
    /// One step up — cards, rows.
    static let surfaceElevated  = Color(hex: 0x161618)
    /// Two steps up — controls, nested panels, pressed states.
    static let surfaceElevated2 = Color(hex: 0x222226)

    static let textPrimary      = Color(hex: 0xF5F5F4)
    static let textSecondary    = Color(hex: 0x9A9A9F)
    static let textTertiary     = Color(hex: 0x636368)

    /// Hot-orange signature accent (#FF4500).
    static let accent           = Color(hex: 0xFF4500)
    /// Foreground placed ON an accent fill — ALWAYS white for legibility.
    static let onAccent         = Color.white

    /// Hairline strokes / dividers.
    static let hairline         = Color.white.opacity(0.08)

    static let success          = Color(hex: 0x35C75A)
    static let danger           = Color(hex: 0xFF453A)
}

extension Color {
    /// 0xRRGGBB convenience. Internal — keeps hex confined to the palette definition.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
