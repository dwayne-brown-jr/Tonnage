import Foundation

/// Pure progression/volume analytics over logged workouts. Kept free of SwiftUI /
/// SwiftData querying so it's unit-testable; the view fetches workouts and passes them in.
public enum Analytics {

    public struct WeekVolume: Sendable, Identifiable, Equatable {
        public let week: Int
        public let volume: Double
        public var id: Int { week }
    }

    public struct TopSetPoint: Sendable, Identifiable, Equatable {
        public let week: Int
        public let weight: Double
        public let reps: Int
        public var id: Int { week }
        /// Epley estimated 1RM.
        public var estimatedOneRepMax: Double { weight * (1 + Double(reps) / 30) }
    }

    /// Total tonnage per week across the block (0 for weeks with no logged volume).
    public static func weeklyVolume(_ workouts: [LoggedWorkout], weeks: Int = 5) -> [WeekVolume] {
        (1...weeks).map { week in
            let volume = workouts.filter { $0.weekNumber == week }.reduce(0.0) { $0 + $1.totalVolume }
            return WeekVolume(week: week, volume: volume)
        }
    }

    /// Distinct exercise names that have at least one completed set, in first-seen order.
    public static func loggedExerciseNames(_ workouts: [LoggedWorkout]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for workout in workouts.sorted(by: { $0.weekNumber < $1.weekNumber }) {
            for exercise in workout.orderedExercises where exercise.topSet != nil {
                if seen.insert(exercise.name).inserted { result.append(exercise.name) }
            }
        }
        return result
    }

    /// Top-set (heaviest completed set) per week for one exercise, ascending by week.
    public static func topSetSeries(for name: String, in workouts: [LoggedWorkout]) -> [TopSetPoint] {
        workouts
            .sorted { $0.weekNumber < $1.weekNumber }
            .compactMap { workout in
                guard let exercise = workout.exercises?.first(where: { $0.name == name }),
                      let top = exercise.topSet else { return nil }
                return TopSetPoint(week: workout.weekNumber, weight: top.weight, reps: top.reps)
            }
    }

    // Block summary.
    public static func totalVolume(_ workouts: [LoggedWorkout]) -> Double {
        workouts.reduce(0) { $0 + $1.totalVolume }
    }
    public static func totalSets(_ workouts: [LoggedWorkout]) -> Int {
        workouts.reduce(0) { $0 + $1.completedSetCount }
    }
    public static func sessionsLogged(_ workouts: [LoggedWorkout]) -> Int {
        workouts.filter { $0.completedSetCount > 0 }.count
    }
}
