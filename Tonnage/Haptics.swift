import UIKit

/// Thin wrapper over UIKit feedback generators for meaningful, native-feeling events.
///
/// Generators are REUSED and re-`prepare()`d after each event so the Taptic Engine stays warm.
/// The old code created a fresh generator per call and never prepared it — that cold-starts the
/// engine on every tap, so the haptic lands a beat late and taps feel laggy/inconsistent. Warm,
/// reused generators make each tap register instantly. Always fired from the UI/main thread, so
/// the type is @MainActor — matching the generators' own main-actor initializers.
@MainActor
enum Haptics {
    private static let impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light:  UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy:  UIImpactFeedbackGenerator(style: .heavy),
        .rigid:  UIImpactFeedbackGenerator(style: .rigid),
        .soft:   UIImpactFeedbackGenerator(style: .soft)
    ]
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = impacts[style] ?? UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        generator.prepare()            // keep warm for the next tap
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Warm all generators up front (e.g. when an interactive screen appears) so even the very
    /// first tap after idle is instant.
    static func warmUp() {
        impacts.values.forEach { $0.prepare() }
        notification.prepare()
        selectionGenerator.prepare()
    }
}
