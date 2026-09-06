#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity payload for the rest timer. Shared between the app (which starts /
/// updates / ends the Activity) and the widget extension (which renders it on the
/// Lock Screen and in the Dynamic Island).
public struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// When the rest ends — the UI uses `Text(timerInterval:)` so it counts down
        /// live without the app pushing every second.
        public var endDate: Date
        public var exerciseName: String
        public var totalSeconds: Int

        public init(endDate: Date, exerciseName: String, totalSeconds: Int) {
            self.endDate = endDate
            self.exerciseName = exerciseName
            self.totalSeconds = totalSeconds
        }
    }

    public init() {}
}
#endif
