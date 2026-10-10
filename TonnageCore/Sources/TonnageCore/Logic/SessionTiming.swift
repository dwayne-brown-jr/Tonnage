import Foundation

/// Longest session `sessionInterval` will believe.
public let maxSessionHours: Double = 12

public extension LoggedWorkout {
    /// When the session ran, for Apple Health. Starts at the workout's date (re-anchored to
    /// the first working set when it's logged today) and ends a minute after the last
    /// completed set, so a session that runs past midnight keeps its start date and gets
    /// its real length. With no set times to go on: today's sessions end now, backdated
    /// ones get `fallbackMinutes`.
    func sessionInterval(now: Date = .now, fallbackMinutes: Double = 45,
                         calendar: Calendar = .current) -> DateInterval {
        let start = date
        // Set times more than 12 h out belong to a session logged after the fact (a
        // backdated workout filled in today), not to how long it ran.
        let latest = start.addingTimeInterval(maxSessionHours * 3600)
        let lastSet = (exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.completed && $0.timestamp > start && $0.timestamp <= latest }
            .map(\.timestamp)
            .max()
        if let lastSet {
            return DateInterval(start: start, end: max(lastSet.addingTimeInterval(60), start.addingTimeInterval(60)))
        }
        if calendar.isDate(start, inSameDayAs: now), now > start {
            return DateInterval(start: start, end: now)
        }
        return DateInterval(start: start, duration: fallbackMinutes * 60)
    }
}

public extension WidgetSnapshot {
    /// This week's completed working sets, reps and volume from synced payloads (the
    /// watch complication's source). Warm-ups don't count.
    static func weekTotals(_ workouts: [WorkoutPayload], week: Int) -> (sets: Int, reps: Int, volume: Double) {
        var totals = (sets: 0, reps: 0, volume: 0.0)
        for w in workouts where w.weekNumber == week {
            for e in w.exercises where !e.isCardio {
                for s in e.sets where s.completed && !(s.isWarmup ?? false) {
                    totals.sets += 1
                    totals.reps += s.reps
                    totals.volume += s.weight * Double(s.reps)
                }
            }
        }
        return totals
    }
}
