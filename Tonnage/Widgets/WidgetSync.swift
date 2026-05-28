import Foundation
import SwiftData
import WidgetKit
import TonnageCore

/// Bridges the app's SwiftData store to the home-screen widget. Rebuilds the shared
/// `WidgetSnapshot` from the current selection + this week's totals, writes it to the
/// App Group container, and nudges WidgetKit to refresh its timelines.
@MainActor
enum WidgetSync {
    static func refresh(context: ModelContext, block: Int, week: Int,
                        sessionName: String, sessionFocus: String) {
        let totals = weekTotals(context: context, block: block, week: week)
        WidgetSnapshot(block: block, week: week,
                       sessionName: sessionName, sessionFocus: sessionFocus,
                       weekSets: totals.sets, weekReps: totals.reps, weekVolume: totals.volume)
            .write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sums completed work across every logged session in the given block + week.
    private static func weekTotals(context: ModelContext, block: Int, week: Int)
        -> (sets: Int, reps: Int, volume: Double) {
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week }
        )
        let workouts = (try? context.fetch(descriptor)) ?? []
        return workouts.reduce(into: (0, 0, 0.0)) { acc, w in
            acc.sets += w.completedSetCount
            acc.reps += w.totalReps
            acc.volume += w.totalVolume
        }
    }
}
