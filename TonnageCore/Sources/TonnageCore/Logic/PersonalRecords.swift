import Foundation

/// A moment when an exercise's estimated 1RM was beaten — surfaced as a PR card in
/// DATA so progress feels concrete, not just "the bar went up a little."
public struct PRMoment: Identifiable, Sendable, Equatable {
    public let exerciseName: String
    public let weight: Double
    public let reps: Int
    public let estimatedOneRM: Double
    public let date: Date
    public let weekNumber: Int
    public let blockNumber: Int
    public let isCompound: Bool

    /// Composite ID — multiple PRs can happen on the same date for different exercises.
    public var id: String { "\(exerciseName)-\(Int(date.timeIntervalSince1970))" }

    public init(exerciseName: String, weight: Double, reps: Int, estimatedOneRM: Double,
                date: Date, weekNumber: Int, blockNumber: Int, isCompound: Bool) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.estimatedOneRM = estimatedOneRM
        self.date = date
        self.weekNumber = weekNumber
        self.blockNumber = blockNumber
        self.isCompound = isCompound
    }
}

/// Detects PR moments across logged history. A "PR" = a completed set whose Epley
/// e1RM strictly beats every prior completed set of the same exercise. The very first
/// completed set establishes the baseline (NOT a PR) so the feed isn't noisy with
/// "you logged something for the first time."
public enum PersonalRecords {

    /// Epley is only reliable in the low-to-moderate rep range; past this, a high-rep pump
    /// set produces an inflated e1RM that fires false PRs. Sets above this are ignored for
    /// PR detection (and don't establish a baseline).
    public static let maxRepsForReliableE1RM = 12

    /// Most-recent-first PR moments across the full history, capped at `limit`.
    public static func recentPRs(in workouts: [LoggedWorkout], limit: Int = 8) -> [PRMoment] {
        let chronological = workouts.sorted { $0.date < $1.date }
        var prs: [PRMoment] = []
        var bestByExercise: [String: Double] = [:]

        for w in chronological {
            for ex in w.orderedExercises where !ex.isCardio {
                for set in ex.orderedSets where set.completed && !set.isWarmup {
                    // Skip high-rep sets — Epley over-estimates there and would mint fake PRs.
                    guard set.weight > 0, set.reps > 0, set.reps <= maxRepsForReliableE1RM else { continue }
                    let e = epley(weight: set.weight, reps: set.reps)
                    let prev = bestByExercise[ex.name] ?? 0
                    if prev > 0, e > prev {
                        prs.append(PRMoment(
                            exerciseName: ex.name,
                            weight: set.weight, reps: set.reps,
                            estimatedOneRM: e,
                            date: w.date,
                            weekNumber: w.weekNumber, blockNumber: w.blockNumber,
                            isCompound: ex.isCompound
                        ))
                    }
                    if e > prev { bestByExercise[ex.name] = e }
                }
            }
        }
        return Array(prs.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Epley estimated 1RM — same formula already used for `Analytics.TopSetPoint`.
    public static func epley(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }
}
