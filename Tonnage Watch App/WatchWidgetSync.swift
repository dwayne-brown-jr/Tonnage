import Foundation
import WidgetKit
import TonnageCore

/// Writes the watch's known training state (current block, selected week and that
/// week's totals) into the shared App Group container so the watch complication can
/// render it, then refreshes WidgetKit. Totals come from the sessions the phone synced
/// (which include everything logged on the watch, once merged), plus any session
/// in progress on the wrist that hasn't come back yet.
@MainActor
enum WatchWidgetSync {
    static func refresh(inProgress: WorkoutPayload? = nil) {
        let block = UserDefaults.standard.object(forKey: "currentBlock") as? Int ?? 1
        let week  = UserDefaults.standard.object(forKey: "watch.week") as? Int ?? 1
        var workouts = WatchConnectivityClient.shared.loggedWorkouts
        if let inProgress {
            // The live session replaces the phone's (older) copy of the same session.
            workouts.removeAll { $0.weekNumber == inProgress.weekNumber && $0.sessionName == inProgress.sessionName }
            workouts.append(inProgress)
        }
        let totals = WidgetSnapshot.weekTotals(workouts, week: week)
        WidgetSnapshot(block: block, week: week, sessionName: "", sessionFocus: "",
                       weekSets: totals.sets, weekReps: totals.reps, weekVolume: totals.volume).write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
