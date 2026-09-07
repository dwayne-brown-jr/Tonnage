import Foundation

/// How long you've been away from lifting, and how much to scale loads on the way back.
///
/// The progression engine otherwise reasons purely off your last logged top set with no
/// sense of when it happened, so a lifter returning after months away would be handed
/// their pre-layoff working weights — the session most likely to hurt them.
public struct Layoff: Sendable, Equatable {
    /// Whole days since the most recent logged lift.
    public let days: Int
    /// Fraction of the last working load to suggest on return (0.6–1.0).
    public let loadMultiplier: Double

    public init(days: Int, loadMultiplier: Double) {
        self.days = days
        self.loadMultiplier = loadMultiplier
    }

    /// Below this, normal week-to-week progression still applies — a missed week is not a layoff.
    public static let significantDays = 14

    /// True once the gap is long enough to override normal progression.
    public var isSignificant: Bool { days >= Self.significantDays }

    /// Human phrasing for the gap — "3 weeks", "2 months".
    public var summary: String {
        if days < 14 { return "\(days) day\(days == 1 ? "" : "s")" }
        if days < 60 {
            let weeks = Int((Double(days) / 7).rounded())
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        }
        let months = Int((Double(days) / 30.44).rounded())
        return "\(months) month\(months == 1 ? "" : "s")"
    }

    /// The multiplier as a whole percentage, for display ("~70%").
    public var loadPercent: Int { Int((loadMultiplier * 100).rounded()) }
}

public enum LayoffEngine {

    /// Strength holds up well for roughly two weeks off, then erodes — fast at first for
    /// neural drive, slower after. These tiers deliberately stay conservative: suggesting
    /// too little costs one easy session, suggesting too much can cost months.
    /// The 0.6 floor matches the app's existing deload load, so a long return reads as a
    /// ramp week rather than a new concept.
    public static func loadMultiplier(daysSinceLastLift days: Int) -> Double {
        switch days {
        case ..<Layoff.significantDays: 1.00   // a missed week is not detraining
        case ..<21:                     0.90   // 2–3 weeks
        case ..<42:                     0.80   // 3–6 weeks
        case ..<84:                     0.70   // 6–12 weeks
        default:                        0.60   // 12+ weeks — treat as starting over
        }
    }

    /// Days between the last logged lift and `now`, or nil when nothing has been logged.
    public static func daysSinceLastLift(workouts: [LoggedWorkout], now: Date = .now,
                                         calendar: Calendar = .current) -> Int? {
        let lifted = workouts.filter { $0.dayType == .lift && $0.completedSetCount > 0 }
        guard let latest = lifted.map(\.date).max() else { return nil }
        let from = calendar.startOfDay(for: latest)
        let to = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: from, to: to).day else { return nil }
        return max(0, days)
    }

    /// The current layoff, or nil when nothing has been logged yet (a brand-new user is
    /// not "returning" — they have no loads to scale down).
    public static func assess(workouts: [LoggedWorkout], now: Date = .now,
                              calendar: Calendar = .current) -> Layoff? {
        guard let days = daysSinceLastLift(workouts: workouts, now: now, calendar: calendar) else { return nil }
        return Layoff(days: days, loadMultiplier: loadMultiplier(daysSinceLastLift: days))
    }
}
