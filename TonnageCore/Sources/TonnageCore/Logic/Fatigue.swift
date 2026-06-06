import Foundation

/// Training-load bookkeeping derived from logged history. Right now it's the "days trained
/// without a full rest" streak — the thing that makes logging a rest day actually *do*
/// something: a Full Rest resets the streak, which clears the rest/deload nudges.
public enum FatigueEngine {

    /// How many consecutive days we nudge a full rest after.
    public static let restNudgeThreshold = 6

    public static func recommendsRest(_ streak: Int) -> Bool { streak >= restNudgeThreshold }

    /// Consecutive calendar days up to `asOf` on which the athlete trained (a lift with at
    /// least one completed set) without a logged Full Rest breaking the run. Rules walking
    /// backwards from today:
    /// - a **Full Rest** day ends the streak (returns what came after it),
    /// - a **lift** day extends it,
    /// - an **Active Rest** day is a light day: it neither extends nor breaks the run,
    /// - a **gap** (a past day with nothing logged) ends the streak,
    /// - **today** with nothing logged yet is allowed — we keep looking back.
    public static func trainingStreak(workouts: [LoggedWorkout], asOf date: Date = .now,
                                      calendar: Calendar = .current) -> Int {
        var trained = Set<Date>(), activeRest = Set<Date>(), fullRest = Set<Date>()
        for w in workouts {
            let day = calendar.startOfDay(for: w.date)
            switch w.dayType {
            case .lift where w.completedSetCount > 0: trained.insert(day)
            case .activeRest:                         activeRest.insert(day)
            case .fullRest:                           fullRest.insert(day)
            default:                                  break
            }
        }

        let today = calendar.startOfDay(for: date)
        var streak = 0
        var cursor = today
        for _ in 0..<400 {                                  // safety bound
            if fullRest.contains(cursor) { break }
            if trained.contains(cursor) {
                streak += 1
            } else if activeRest.contains(cursor) {
                // light day — carry the streak through without counting it
            } else if cursor != today {
                break                                        // a real gap ends the run
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
