import Foundation

/// Contextualizes a lifter's best e1RM against widely used bodyweight-multiple
/// strength standards for the big four. Thresholds follow the common
/// strength-level convention (e.g. a 1.5× bodyweight bench ≈ advanced for men);
/// female thresholds are scaled per the same tables.
public enum StrengthStandards {

    public enum Lift: String, CaseIterable, Sendable, Identifiable {
        case squat, bench, deadlift, overheadPress
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .squat:         "Squat"
            case .bench:         "Bench Press"
            case .deadlift:      "Deadlift"
            case .overheadPress: "Overhead Press"
            }
        }

        /// Library display names whose history feeds this standard.
        public var exerciseNames: [String] {
            switch self {
            case .squat:         ["Barbell Back Squat"]
            case .bench:         ["Barbell Bench Press"]
            case .deadlift:      ["Deadlift"]
            case .overheadPress: ["Overhead Press", "Seated Shoulder Press"]
            }
        }

        /// Bodyweight multiples for [beginner, novice, intermediate, advanced, elite] — male.
        var maleThresholds: [Double] {
            switch self {
            case .squat:         [0.75, 1.0, 1.5, 2.0, 2.5]
            case .bench:         [0.5, 0.75, 1.0, 1.5, 2.0]
            case .deadlift:      [1.0, 1.25, 1.75, 2.5, 3.0]
            case .overheadPress: [0.35, 0.5, 0.75, 1.0, 1.4]
            }
        }
    }

    public enum Level: Int, CaseIterable, Sendable, Comparable {
        case untrained, beginner, novice, intermediate, advanced, elite

        public var label: String {
            switch self {
            case .untrained:    "Untrained"
            case .beginner:     "Beginner"
            case .novice:       "Novice"
            case .intermediate: "Intermediate"
            case .advanced:     "Advanced"
            case .elite:        "Elite"
            }
        }
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Rating: Sendable, Equatable {
        public let lift: Lift
        public let estimatedOneRM: Double
        public let bodyweightMultiple: Double
        public let level: Level
        /// 0…1 progress from the current level's threshold to the next (1 at elite).
        public let progressToNext: Double
        /// e1RM needed for the next level (nil at elite).
        public let nextLevelE1RM: Double?
    }

    /// Female thresholds run at the conventional ~70% of male bodyweight multiples.
    static let femaleScale = 0.7

    /// Rate a best e1RM against the standard. Nil when bodyweight or e1RM is missing.
    public static func rating(lift: Lift, e1RM: Double, bodyweightLb: Double,
                              sex: BiologicalSex) -> Rating? {
        guard e1RM > 0, bodyweightLb > 0 else { return nil }
        let scale = (sex == .female) ? femaleScale : 1.0
        let thresholds = lift.maleThresholds.map { $0 * scale * bodyweightLb }
        let multiple = e1RM / bodyweightLb

        var level = Level.untrained
        for (i, threshold) in thresholds.enumerated() where e1RM >= threshold {
            level = Level(rawValue: i + 1) ?? .elite
        }

        let progress: Double
        let nextE1RM: Double?
        if level == .elite {
            progress = 1
            nextE1RM = nil
        } else {
            let lower = level == .untrained ? 0 : thresholds[level.rawValue - 1]
            let upper = thresholds[level.rawValue]
            progress = max(0, min(1, (e1RM - lower) / (upper - lower)))
            nextE1RM = upper
        }
        return Rating(lift: lift, estimatedOneRM: e1RM, bodyweightMultiple: multiple,
                      level: level, progressToNext: progress, nextLevelE1RM: nextE1RM)
    }

    /// Best (lifetime) e1RM per standard lift from logged history — same eligibility
    /// rules as PR detection (completed working sets, reps ≤ 12).
    @MainActor
    public static func bestE1RMs(in workouts: [LoggedWorkout]) -> [Lift: Double] {
        var best: [Lift: Double] = [:]
        for w in workouts {
            for ex in w.orderedExercises where !ex.isCardio {
                guard let lift = Lift.allCases.first(where: { $0.exerciseNames.contains(ex.name) }) else { continue }
                for set in ex.orderedSets where set.completed && !set.isWarmup {
                    guard set.weight > 0, set.reps > 0,
                          set.reps <= PersonalRecords.maxRepsForReliableE1RM else { continue }
                    let e = PersonalRecords.epley(weight: set.weight, reps: set.reps)
                    if e > (best[lift] ?? 0) { best[lift] = e }
                }
            }
        }
        return best
    }
}
