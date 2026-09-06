import Foundation
import ActivityKit
import TonnageCore

/// Drives the rest-timer Live Activity (Lock Screen + Dynamic Island). No-ops cleanly
/// where Live Activities are unavailable or disabled.
@MainActor
enum RestLiveActivity {
    // Qualified: `Activity` alone collides with TonnageCore.Activity (the MOVE model).
    private static var current: ActivityKit.Activity<RestTimerAttributes>?

    static func start(endDate: Date, exerciseName: String, totalSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()   // never run two at once
        let state = RestTimerAttributes.ContentState(endDate: endDate, exerciseName: exerciseName, totalSeconds: totalSeconds)
        current = try? ActivityKit.Activity.request(
            attributes: RestTimerAttributes(),
            content: .init(state: state, staleDate: endDate.addingTimeInterval(5))
        )
    }

    static func update(endDate: Date, exerciseName: String, totalSeconds: Int) {
        guard let activity = current else { return }
        let state = RestTimerAttributes.ContentState(endDate: endDate, exerciseName: exerciseName, totalSeconds: totalSeconds)
        // ActivityKit predates Sendable annotations but documents update/end as callable
        // from any async context — box the non-Sendable values to cross into the Task.
        let boxed = UncheckedSendable((activity, ActivityContent(state: state, staleDate: endDate.addingTimeInterval(5))))
        Task {
            let (activity, content) = boxed.value
            await activity.update(content)
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        let boxed = UncheckedSendable(activity)
        Task { await boxed.value.end(nil, dismissalPolicy: .immediate) }
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
