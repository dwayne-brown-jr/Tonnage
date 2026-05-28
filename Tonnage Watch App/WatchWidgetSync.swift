import Foundation
import WidgetKit
import TonnageCore

/// Writes the watch's known training state (current block + selected week) into the
/// shared App Group container so the watch complication can render it, then refreshes
/// WidgetKit. Per-week totals aren't aggregated on the wrist, so they stay 0 — the
/// complication shows block/week and acts as a quick launch into the app.
@MainActor
enum WatchWidgetSync {
    static func refresh() {
        let block = UserDefaults.standard.object(forKey: "currentBlock") as? Int ?? 1
        let week  = UserDefaults.standard.object(forKey: "watch.week") as? Int ?? 1
        WidgetSnapshot(block: block, week: week, sessionName: "", sessionFocus: "",
                       weekSets: 0, weekReps: 0, weekVolume: 0).write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
