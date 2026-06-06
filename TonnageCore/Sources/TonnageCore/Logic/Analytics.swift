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

    public struct MuscleVolume: Sendable, Identifiable, Equatable {
        /// `nil` = "Other" — movements we don't recognize (custom/ad-hoc names), kept so
        /// volume is never silently dropped.
        public let group: MuscleGroup?
        /// Hard sets = completed working (non-cardio) sets in the window.
        public let sets: Int
        public var id: String { group?.rawValue ?? "other" }
        public var label: String { group?.label ?? "Other" }
    }

    /// Evidence-based weekly hard-set landmarks per muscle (hypertrophy): ~10 is the
    /// minimum effective volume, ~20 the top of the productive range for most lifters.
    public static let weeklySetsMEV = 10
    public static let weeklySetsMAV = 20

    /// Hard (completed, non-cardio) sets per muscle group for the given workouts — the
    /// caller filters the window (e.g. one week). Cardio is excluded; unrecognized
    /// movements roll up into "Other". Ordered by the muscle enum with Other last; groups
    /// with zero sets are omitted.
    public static func setsPerMuscle(_ workouts: [LoggedWorkout]) -> [MuscleVolume] {
        var counts: [MuscleGroup?: Int] = [:]
        for w in workouts where w.dayType == .lift {
            for ex in (w.exercises ?? []) where !ex.isCardio {
                let done = ex.completedSetCount
                guard done > 0 else { continue }
                counts[ExerciseLibrary.muscleGroup(for: ex.name), default: 0] += done
            }
        }
        var result = MuscleGroup.allCases.compactMap { g -> MuscleVolume? in
            guard g != .cardio, let c = counts[g], c > 0 else { return nil }
            return MuscleVolume(group: g, sets: c)
        }
        if let other = counts[nil], other > 0 {
            result.append(MuscleVolume(group: nil, sets: other))
        }
        return result
    }

    /// The latest week within `workouts` that has any completed lifting (nil if none).
    public static func latestLoggedWeek(_ workouts: [LoggedWorkout]) -> Int? {
        workouts.filter { $0.dayType == .lift && $0.completedSetCount > 0 }.map(\.weekNumber).max()
    }

    public struct WeekSummary: Sendable, Equatable {
        public let week: Int
        public let sessions: Int
        public let sets: Int
        public let volume: Double
    }

    /// Sessions / hard sets / tonnage for a single week (warm-ups + rest already excluded
    /// by the underlying accessors). The caller passes the block-scoped workouts.
    public static func weekSummary(_ workouts: [LoggedWorkout], week: Int) -> WeekSummary {
        let wk = workouts.filter { $0.weekNumber == week }
        return WeekSummary(week: week,
                           sessions: sessionsLogged(wk),
                           sets: totalSets(wk),
                           volume: totalVolume(wk))
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
