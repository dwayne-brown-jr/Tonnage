import Foundation

/// "Are you actually doing the work?" for one mesocycle. Plays in DATA alongside the
/// volume + progression charts so showing up is itself a tracked metric.
public struct BlockAdherence: Sendable, Equatable {
    /// Distinct (week, session-name) slots in this block where the athlete logged at least
    /// one completed set. Rest days are standalone calendar entries, not sessions, so they
    /// don't count here.
    public let sessionsCompleted: Int
    /// `sessionsPerWeek × weeks` for the block (default 4 × 5 = 20).
    public let sessionsPlanned: Int
    /// Unique calendar days inside the block on which any lifting actually happened.
    public let trainingDays: Int

    public var completionPct: Double {
        sessionsPlanned > 0 ? Double(sessionsCompleted) / Double(sessionsPlanned) : 0
    }

    public init(sessionsCompleted: Int, sessionsPlanned: Int, trainingDays: Int) {
        self.sessionsCompleted = sessionsCompleted
        self.sessionsPlanned = sessionsPlanned
        self.trainingDays = trainingDays
    }
}

public enum AdherenceEngine {
    /// Computes adherence for one block. Only completed lift sessions count toward
    /// `sessionsCompleted` and `trainingDays`; rest days are standalone calendar entries,
    /// tracked in history but neutral to the ratio.
    public static func computeBlock(
        workouts: [LoggedWorkout],
        blockNumber: Int,
        sessionsPerWeek: Int,
        weeks: Int = 5,
        calendar: Calendar = .current
    ) -> BlockAdherence {
        let blockWorkouts = workouts.filter { $0.blockNumber == blockNumber }
        var completedSlots = Set<String>()
        var trainingDays = Set<Date>()

        for w in blockWorkouts where w.dayType == .lift && w.completedSetCount > 0 {
            completedSlots.insert("\(w.weekNumber)-\(w.sessionName)")
            trainingDays.insert(calendar.startOfDay(for: w.date))
        }

        return BlockAdherence(
            sessionsCompleted: completedSlots.count,
            sessionsPlanned: max(0, sessionsPerWeek * weeks),
            trainingDays: trainingDays.count
        )
    }
}
