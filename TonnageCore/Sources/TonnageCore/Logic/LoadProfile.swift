import Foundation

/// What a movement is loaded with. Inferred from the exercise name, so it also works
/// for custom exercises; anything unrecognized is `.other` and progresses like before.
public enum Equipment: String, Sendable, Equatable {
    case barbell, dumbbell, machine, bodyweight, other
}

/// How load moves for one exercise: the jump size, the rounding step and the lightest
/// loadable weight. Keeps the engine's advice in plates and dumbbells that exist —
/// a 15 lb lateral raise goes to 17.5 rather than 20, and a barbell never drops
/// below the empty bar.
public struct LoadProfile: Sendable, Equatable {
    public let equipment: Equipment
    public let isCompound: Bool

    public init(equipment: Equipment, isCompound: Bool) {
        self.equipment = equipment
        self.isCompound = isCompound
    }

    /// Flat 5 lb jumps, no floor — the engine's behaviour before it knew about equipment.
    public static let standard = LoadProfile(equipment: .other, isCompound: true)

    public static func forExercise(named name: String, isCompound: Bool) -> LoadProfile {
        LoadProfile(equipment: ExerciseLibrary.equipment(for: name), isCompound: isCompound)
    }

    /// Weight of an empty Olympic bar.
    public static let emptyBar: Double = 45

    /// The lightest weight that can actually be loaded (the empty bar for barbells).
    public var floor: Double { equipment == .barbell ? Self.emptyBar : 0 }

    /// One progression step from `weight`. Dumbbells move to the next dumbbell
    /// (2.5 lb steps up to 25 lb, then 5 lb); isolation lifts move 2.5 lb; everything
    /// else 5 lb.
    public func increment(from weight: Double) -> Double {
        switch equipment {
        case .dumbbell: return weight < 25 ? 2.5 : 5
        default:        return isCompound ? 5 : 2.5
        }
    }

    /// `weight` plus one step, landing on a loadable value.
    public func nextWeight(after weight: Double) -> Double {
        let step = increment(from: weight)
        return clampToFloor(CoachEngine.roundToStep(weight + step, step: step))
    }

    /// `weight` rounded to a loadable value for this equipment, never below the floor.
    public func rounded(_ weight: Double) -> Double {
        clampToFloor(CoachEngine.roundToStep(weight, step: increment(from: weight)))
    }

    private func clampToFloor(_ weight: Double) -> Double {
        weight > 0 ? max(floor, weight) : weight
    }
}

public extension ExerciseLibrary {

    /// Name-based equipment guess. Conservative: only clear signals map to a type.
    /// Dumbbell and machine words win over barbell lift names ("DB Bench Press",
    /// "Smith Machine Squat"), so a barbell floor only applies to real barbell lifts.
    static func equipment(for name: String) -> Equipment {
        let n = " " + normalize(name)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ") + " "
        func has(_ words: String...) -> Bool { words.contains { n.contains(" \($0) ") || n.contains(" \($0)s ") } }

        if has("db", "dumbbell", "dumbell", "goblet", "kettlebell", "kb") { return .dumbbell }
        if has("machine", "cable", "smith", "pulldown", "pushdown", "leg press", "leg curl",
               "leg extension", "pec deck", "hack squat", "seated calf raise") { return .machine }
        if has("push up", "pushup", "pull up", "pullup", "chin up", "chinup", "dip", "plank",
               "hanging", "bodyweight", "inverted row", "sit up", "burpee", "pistol") { return .bodyweight }
        if has("barbell", "bb", "back squat", "front squat", "deadlift", "romanian deadlift", "rdl",
               "bench press", "overhead press", "ohp", "military press", "pendlay row", "hip thrust",
               "good morning", "power clean", "barbell row", "floor press") { return .barbell }
        return .other
    }

    /// Holds measured in seconds (planks, dead hangs, wall sits). They log time, not
    /// weight × reps, and the engine never tells them to add load.
    static func isTimedHold(_ name: String) -> Bool {
        let n = " " + normalize(name).replacingOccurrences(of: "-", with: " ") + " "
        let markers = [" plank", " hold", " dead hang", " wall sit", " l sit", " hollow body"]
        return markers.contains { n.contains($0) }
    }

    /// Key for an exercise's history (PRs, last-week references). Folds spelling variants
    /// of the same movement together: "Bench Press", "bench press" and "BB Bench Press"
    /// share one history.
    static func historyKey(for name: String) -> String {
        canonicalDisplayName(for: name).lowercased()
    }
}
