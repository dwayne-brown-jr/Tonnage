import Foundation
import WatchKit

/// Wrist-haptic rest timer. Counts down and buzzes when it's time for the next set.
@MainActor
@Observable
final class WatchRestTimer {
    private(set) var remaining = 0
    private(set) var total = 0
    /// When the rest ends — drive countdown text with `Text(timerInterval:)` against
    /// this so the display keeps ticking under the Always-On (luminance-reduced)
    /// watch face, where our 1 s task loop is throttled.
    private(set) var endDate: Date?
    private var task: Task<Void, Never>?

    var isRunning: Bool { remaining > 0 }
    var progress: Double { total > 0 ? Double(remaining) / Double(total) : 0 }

    func start(seconds: Int) {
        total = seconds
        remaining = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        WKInterfaceDevice.current().play(.start)
        task?.cancel()
        task = Task { @MainActor in
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            endDate = nil
            WKInterfaceDevice.current().play(.notification)   // time for the next set
        }
    }

    func add(_ seconds: Int) {
        guard isRunning else { return }
        total += seconds
        remaining += seconds
        endDate = endDate.map { $0.addingTimeInterval(TimeInterval(seconds)) }
    }

    func skip() {
        task?.cancel()
        remaining = 0
        total = 0
        endDate = nil
    }
}
