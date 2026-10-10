import Foundation

/// Fine-grained muscles for the body map — finer than `MuscleGroup` (which drives swaps and
/// the weekly-volume bars) so the map can show e.g. a press lighting front delts, not just "shoulders".
public enum Muscle: String, CaseIterable, Sendable, Identifiable, Codable {
    case upperChest, chest
    case frontDelts, sideDelts, rearDelts
    case traps, upperBack, lats, lowerBack
    case biceps, triceps, forearms
    case abs, obliques, hipFlexors
    case glutes, quads, adductors, hamstrings, calves

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .upperChest: "Upper Chest"
        case .chest:      "Chest"
        case .frontDelts: "Front Delts"
        case .sideDelts:  "Side Delts"
        case .rearDelts:  "Rear Delts"
        case .traps:      "Traps"
        case .upperBack:  "Mid-Back"
        case .lats:       "Lats"
        case .lowerBack:  "Lower Back"
        case .biceps:     "Biceps"
        case .triceps:    "Triceps"
        case .forearms:   "Forearms"
        case .abs:        "Abs"
        case .obliques:   "Obliques"
        case .hipFlexors: "Hip Flexors"
        case .glutes:     "Glutes"
        case .quads:      "Quads"
        case .adductors:  "Adductors"
        case .hamstrings: "Hamstrings"
        case .calves:     "Calves"
        }
    }

    /// The coarse group this muscle rolls up into.
    public var group: MuscleGroup {
        switch self {
        case .upperChest, .chest:                    .chest
        case .frontDelts, .sideDelts, .rearDelts:    .shoulders
        case .traps, .upperBack, .lats, .lowerBack:  .back
        case .biceps, .forearms:                     .biceps
        case .triceps:                               .triceps
        case .abs, .obliques, .hipFlexors:           .core
        case .glutes:                                .glutes
        case .quads, .adductors:                     .quads
        case .hamstrings:                            .hamstrings
        case .calves:                                .calves
        }
    }
}

/// What a movement works: prime movers vs. muscles that assist or stabilize.
public struct MuscleTargets: Sendable, Equatable, Hashable {
    public let primary: [Muscle]
    public let secondary: [Muscle]

    public init(primary: [Muscle], secondary: [Muscle] = []) {
        self.primary = primary
        self.secondary = secondary
    }

    public func emphasis(of muscle: Muscle) -> Emphasis {
        if primary.contains(muscle) { return .primary }
        if secondary.contains(muscle) { return .secondary }
        return .none
    }

    public enum Emphasis: Sendable { case primary, secondary, none }
}

public extension ExerciseLibrary {

    /// Muscles a movement works (nil for unknown / custom names).
    static func muscleTargets(for name: String) -> MuscleTargets? {
        muscleCatalog[normalize(name)]
    }

    /// Keyed by the same normalized names as the directions catalog — a test keeps the two in sync.
    internal static let muscleCatalog: [String: MuscleTargets] = [
        // Chest
        "barbell bench press":        .init(primary: [.chest], secondary: [.frontDelts, .triceps]),
        "db bench press":             .init(primary: [.chest], secondary: [.frontDelts, .triceps]),
        "machine chest press":        .init(primary: [.chest], secondary: [.frontDelts, .triceps]),
        "incline db press":           .init(primary: [.upperChest, .frontDelts], secondary: [.triceps]),
        "incline barbell press":      .init(primary: [.upperChest, .frontDelts], secondary: [.triceps]),
        "cable fly":                  .init(primary: [.chest, .upperChest], secondary: [.frontDelts]),
        "pec deck fly":               .init(primary: [.chest], secondary: [.frontDelts]),
        "push-up":                    .init(primary: [.chest], secondary: [.frontDelts, .triceps, .abs]),
        "bodyweight dip":             .init(primary: [.chest, .triceps], secondary: [.frontDelts]),

        // Back
        "barbell row":                .init(primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps, .lowerBack]),
        "chest-supported row":        .init(primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps]),
        "seated cable row":           .init(primary: [.upperBack, .lats], secondary: [.biceps, .rearDelts]),
        "t-bar row":                  .init(primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps]),
        "inverted row":               .init(primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps]),
        "single-arm db row":          .init(primary: [.lats, .upperBack], secondary: [.biceps, .rearDelts]),
        "cable lat pulldown":         .init(primary: [.lats], secondary: [.biceps, .upperBack]),
        "weighted pull-up / lat pulldown": .init(primary: [.lats], secondary: [.biceps, .upperBack]),
        "pull-up":                    .init(primary: [.lats], secondary: [.upperBack, .biceps, .forearms]),
        "chin-up":                    .init(primary: [.lats, .biceps], secondary: [.upperBack]),
        "straight-arm pulldown":      .init(primary: [.lats], secondary: [.triceps]),

        // Shoulders
        "overhead press":             .init(primary: [.frontDelts, .sideDelts], secondary: [.triceps, .traps, .upperChest, .abs]),
        "seated shoulder press":      .init(primary: [.frontDelts, .sideDelts], secondary: [.triceps, .traps]),
        "arnold press":               .init(primary: [.frontDelts, .sideDelts], secondary: [.triceps]),
        "pike push-up":               .init(primary: [.frontDelts], secondary: [.triceps, .upperChest, .sideDelts]),
        "db lateral raise":           .init(primary: [.sideDelts], secondary: [.traps]),
        "cable lateral raise":        .init(primary: [.sideDelts], secondary: [.traps]),
        "cable face pull":            .init(primary: [.rearDelts, .upperBack], secondary: [.traps, .sideDelts]),
        "rear-delt fly":              .init(primary: [.rearDelts], secondary: [.upperBack]),

        // Arms
        "db incline curl":            .init(primary: [.biceps], secondary: [.forearms]),
        "ez-bar or db curl":          .init(primary: [.biceps], secondary: [.forearms]),
        "barbell or ez-bar curl":     .init(primary: [.biceps], secondary: [.forearms]),
        "hammer curl":                .init(primary: [.biceps, .forearms]),
        "preacher curl":              .init(primary: [.biceps]),
        "cable triceps pushdown":     .init(primary: [.triceps]),
        "overhead triceps extension": .init(primary: [.triceps]),
        "skull crusher":              .init(primary: [.triceps]),
        "close-grip bench press":     .init(primary: [.triceps, .chest], secondary: [.frontDelts]),
        "triceps dips":               .init(primary: [.triceps], secondary: [.chest, .frontDelts]),

        // Quads
        "barbell back squat":         .init(primary: [.quads, .glutes], secondary: [.adductors, .hamstrings, .lowerBack, .abs]),
        "front squat":                .init(primary: [.quads], secondary: [.glutes, .abs, .upperBack]),
        "front squat / goblet squat": .init(primary: [.quads], secondary: [.glutes, .abs, .upperBack]),
        "goblet squat":               .init(primary: [.quads, .glutes], secondary: [.abs, .adductors]),
        "hack squat":                 .init(primary: [.quads], secondary: [.glutes]),
        "leg press":                  .init(primary: [.quads, .glutes], secondary: [.hamstrings, .adductors]),
        "bulgarian split squat":      .init(primary: [.quads, .glutes], secondary: [.adductors, .hamstrings]),
        "walking db lunges":          .init(primary: [.quads, .glutes], secondary: [.adductors, .hamstrings, .calves]),
        "bodyweight squat":           .init(primary: [.quads, .glutes], secondary: [.adductors]),
        "leg extension":              .init(primary: [.quads]),

        // Posterior chain
        "romanian deadlift":          .init(primary: [.hamstrings, .glutes], secondary: [.lowerBack, .forearms]),
        "stiff-leg deadlift":         .init(primary: [.hamstrings], secondary: [.glutes, .lowerBack]),
        "deadlift":                   .init(primary: [.hamstrings, .glutes, .lowerBack], secondary: [.traps, .lats, .forearms, .quads]),
        "leg curl":                   .init(primary: [.hamstrings], secondary: [.calves]),
        "seated leg curl":            .init(primary: [.hamstrings]),
        "barbell hip thrust":         .init(primary: [.glutes], secondary: [.hamstrings]),
        "cable pull-through":         .init(primary: [.glutes, .hamstrings], secondary: [.lowerBack]),
        "glute kickback":             .init(primary: [.glutes], secondary: [.hamstrings]),

        // Calves
        "standing calf raise":        .init(primary: [.calves]),
        "seated calf raise":          .init(primary: [.calves]),
        "single-leg calf raise":      .init(primary: [.calves]),

        // Core
        "hanging knee raise":         .init(primary: [.abs, .hipFlexors], secondary: [.obliques, .forearms]),
        "hanging leg raise":          .init(primary: [.abs, .hipFlexors], secondary: [.obliques, .forearms]),
        "cable crunch":               .init(primary: [.abs], secondary: [.obliques]),
        "cable wood chop / pallof":   .init(primary: [.obliques, .abs]),
        "plank":                      .init(primary: [.abs], secondary: [.obliques, .frontDelts]),

        // Cardio
        "stair master":               .init(primary: [.quads, .glutes], secondary: [.calves, .hamstrings]),
        "bike intervals":             .init(primary: [.quads], secondary: [.glutes, .hamstrings, .calves]),
        "rowing machine":             .init(primary: [.lats, .quads], secondary: [.upperBack, .hamstrings, .glutes, .biceps]),
    ]
}

public extension Analytics {

    /// Body heat map intensities (0…1) that mirror the Sets per Muscle bars: every muscle
    /// takes its group's hard-set count, relative to the busiest group so the emphasis
    /// stands out. The scale never drops below the minimum effective volume, so a light
    /// week doesn't read as maxed out. "Other" (unrecognized movements) has no body region.
    static func muscleHeat(_ volumes: [MuscleVolume]) -> [Muscle: Double] {
        var sets: [MuscleGroup: Int] = [:]
        for v in volumes { if let g = v.group { sets[g, default: 0] += v.sets } }
        let top = Double(max(sets.values.max() ?? 0, weeklySetsMEV))
        var heat: [Muscle: Double] = [:]
        for m in Muscle.allCases {
            if let n = sets[m.group], n > 0 { heat[m] = Double(n) / top }
        }
        return heat
    }
}
