import SwiftUI

/// Core layout + motion tokens.
///
/// Tonnage's tone is brutalist gym-poster: tight, deliberate radii and generous
/// padding. Every view pulls from here — no inline magic numbers.
public enum DS {

    /// 4pt base spacing scale.
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    /// Corner-radius family. Brutalist tone favors small/sharp corners.
    public enum Radius {
        public static let none: CGFloat = 0
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let full: CGFloat = 999
    }

    public enum Stroke {
        public static let hairline: CGFloat = 1
    }

    // MARK: Motion

    /// Default spring for most state changes (set completion, expand/collapse).
    public static let spring = Animation.spring(response: 0.40, dampingFraction: 0.82)
    /// Snappier spring for small, frequent interactions (steppers, toggles).
    public static let snappySpring = Animation.spring(response: 0.26, dampingFraction: 0.78)
}
