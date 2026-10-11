import SwiftUI

/// Semantic, dark-only palette. Raw hex lives ONLY in this file — views reference
/// names (`.surface`, `.accent`, …), never literals.
///
/// The surface ladder is tuned so adjacent steps clear ~1.3:1 contrast, the floor at
/// which a surface change is perceptible. The previous ramp sat at 1.09–1.14:1 and
/// read as one flat sheet.
public extension Color {

    /// Base app background — near-black, not pure black (reads as surface, not void).
    static let surface          = Color(hex: 0x0C0C0F)
    /// One step up — cards, rows. 1.30:1 vs `surface`.
    static let surfaceElevated  = Color(hex: 0x26262B)
    /// Two steps up — controls, nested panels, pressed states. 1.33:1 vs `surfaceElevated`.
    static let surfaceElevated2 = Color(hex: 0x3A3A41)

    /// 17.90:1 on `surface`, 10.34:1 on `surfaceElevated2`.
    static let textPrimary      = Color(hex: 0xF5F5F4)
    /// Lifted from #9A9A9F. 4.94:1 on `surfaceElevated2` — clears AA for normal
    /// text on every surface in the ladder.
    static let textSecondary    = Color(hex: 0xABABB2)
    /// Lifted from #636368, which failed AA everywhere (3.27:1 at best). Now
    /// 6.01:1 on `surface` and 4.63:1 on `surfaceElevated`.
    /// NOT AA-normal on `surfaceElevated2` (3.47:1) — use `textSecondary` for small
    /// text sitting on the top surface.
    static let textTertiary     = Color(hex: 0x8E8E96)

    /// Hot-orange signature accent (#FF4500). 5.68:1 on `surface`, 4.38:1 on
    /// `surfaceElevated`, 3.28:1 on `surfaceElevated2` (large text / icons only).
    static let accent           = Color(hex: 0xFF4500)
    /// Foreground placed ON an accent fill. Warm near-black at 5.60:1.
    /// NEVER white — white on this orange is 3.44:1 and fails AA.
    static let onAccent         = Color(hex: 0x140D08)

    /// Hairline strokes / dividers. Was 0.08, which was invisible on the old ramp.
    static let hairline         = Color.white.opacity(0.14)

    /// 8.81:1 on `surface`, 5.09:1 on `surfaceElevated2`.
    static let success          = Color(hex: 0x35C75A)
    /// 5.73:1 on `surface`, 3.31:1 on `surfaceElevated2` (large text / icons only).
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
