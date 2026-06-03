import Foundation

/// What the athlete is training for — shapes how the coach frames advice.
public enum TrainingGoal: String, CaseIterable, Sendable, Identifiable, Hashable {
    case recomp, strength, size, general
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .recomp:   "Recomp"
        case .strength: "Strength"
        case .size:     "Size"
        case .general:  "General"
        }
    }

    /// Phrase dropped into the coach's system prompt.
    public var coachPhrase: String {
        switch self {
        case .recomp:   "body recomp (muscle gain + fat loss) on a small calorie deficit, high protein"
        case .strength: "getting stronger as the priority, eating at maintenance or a slight surplus"
        case .size:     "adding muscle size, eating in a moderate surplus with high protein"
        case .general:  "general strength and fitness — feeling good and staying consistent"
        }
    }
}

/// Training experience — shapes how aggressive vs. cautious the coach is.
public enum ExperienceLevel: String, CaseIterable, Sendable, Identifiable, Hashable {
    case newcomer, returning, experienced
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .newcomer:    "New to lifting"
        case .returning:   "Getting back into it"
        case .experienced: "Experienced"
        }
    }

    public var coachPhrase: String {
        switch self {
        case .newcomer:    "newer to lifting, so prioritize technique and conservative jumps"
        case .returning:   "returning after a break, so ramp in and don't let them ego-lift early"
        case .experienced: "an experienced lifter who can handle steady, confident progression"
        }
    }
}

/// Biological sex — relevant context for programming, recovery, and nutrition.
/// Optional; the athlete can decline to share it.
public enum BiologicalSex: String, CaseIterable, Sendable, Identifiable, Hashable {
    case unspecified, male, female
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .unspecified: "Prefer not to say"
        case .male:        "Male"
        case .female:      "Female"
        }
    }

    /// Word used in the coach prompt; empty when unspecified.
    public var coachWord: String {
        switch self {
        case .unspecified: ""
        case .male:        "male"
        case .female:      "female"
        }
    }
}

/// The athlete's current physique — captured at intake so the coach can set the right
/// path from day one. Each case implies a training emphasis AND a nutrition direction
/// (which Tonnage Fuel's Goal mirrors: bulk / recomp / cut / maintain).
public enum StartingPoint: String, CaseIterable, Sendable, Identifiable, Hashable {
    case skinny, skinnyFat, overweight, muscularSoft, inShape, unsure
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .skinny:       "Skinny"
        case .skinnyFat:    "Skinny-fat"
        case .overweight:   "Overweight"
        case .muscularSoft: "Muscular but soft"
        case .inShape:      "Lean & in shape"
        case .unsure:       "Not sure"
        }
    }

    /// Plain-language definition shown under the option in onboarding.
    public var definition: String {
        switch self {
        case .skinny:       "Low body fat and low muscle — naturally thin. Small arms/chest, maybe faint abs."
        case .skinnyFat:    "Not big, but soft around the middle — little muscle and no real definition despite a low-ish weight."
        case .overweight:   "Carrying noticeable excess fat across the body; muscle is mostly hidden."
        case .muscularSoft: "Real muscle underneath, but enough fat to hide it — the 'bulked' / offseason look."
        case .inShape:      "Visible muscle and definition, athletic and fairly lean already."
        case .unsure:       "Not sure — the coach will infer from your stats and measurements."
        }
    }

    /// Phrase dropped into the coach/planner prompt.
    public var coachPhrase: String {
        switch self {
        case .skinny:       "skinny (low muscle, low fat) — build size with a lean surplus and patient progression"
        case .skinnyFat:    "skinny-fat (low muscle, soft midsection) — a classic recomp: build muscle while slowly losing fat"
        case .overweight:   "overweight — prioritize fat loss while lifting to preserve and build muscle"
        case .muscularSoft: "muscular but soft — has muscle to reveal; cut while keeping training volume high to retain it"
        case .inShape:      "lean and in shape — maintain or slowly improve, refine weak points, hold body fat in a tight band"
        case .unsure:       "starting point unclear — infer from their height/weight/measurements"
        }
    }

    /// Recommended nutrition direction — mirrors Tonnage Fuel's Goal.
    public var nutritionDirection: String {
        switch self {
        case .skinny:       "lean bulk (slight surplus)"
        case .skinnyFat:    "recomp (around maintenance, high protein)"
        case .overweight:   "cut (moderate deficit)"
        case .muscularSoft: "cut (reveal the muscle)"
        case .inShape:      "maintain or slow lean gain"
        case .unsure:       "to be determined"
        }
    }
}

/// Where the athlete trains — drives exercise selection.
public enum TrainingEnvironment: String, CaseIterable, Sendable, Identifiable, Hashable {
    case fullGym, homeDumbbells, minimal
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fullGym:       "Full gym"
        case .homeDumbbells: "Home (dumbbells)"
        case .minimal:       "Minimal / bodyweight"
        }
    }
    public var coachPhrase: String {
        switch self {
        case .fullGym:       "a fully-equipped gym (barbells, machines, cables)"
        case .homeDumbbells: "a home setup with adjustable dumbbells and a bench"
        case .minimal:       "minimal equipment — mostly bodyweight and bands"
        }
    }
}

/// Body areas the athlete wants to bring up — drives volume emphasis.
public enum BodyFocus: String, CaseIterable, Sendable, Identifiable, Hashable {
    case chest, back, shoulders, arms, legs, glutes, core
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .chest: "Chest"; case .back: "Back"; case .shoulders: "Shoulders"
        case .arms: "Arms"; case .legs: "Legs"; case .glutes: "Glutes"; case .core: "Core"
        }
    }
}

/// The athlete's profile that personalizes the coach. Stored per-device (so each
/// person who installs Tonnage gets their own coach), separate from logged data.
public struct CoachProfile: Sendable, Equatable {
    public var name: String
    public var ageYears: Int          // 0 = unset
    public var sex: BiologicalSex
    public var heightInches: Int      // 0 = unset
    public var bodyweightLb: Int      // 0 = unset (HealthKit is preferred when available)
    public var goal: TrainingGoal
    public var experience: ExperienceLevel
    public var limitations: String    // injuries / things to train around
    public var startingPoint: StartingPoint
    public var priorityFocuses: [BodyFocus]   // muscles to bring up
    public var daysPerWeek: Int               // 0 = unset
    public var environment: TrainingEnvironment

    public init(name: String = "", ageYears: Int = 0, sex: BiologicalSex = .unspecified,
                heightInches: Int = 0, bodyweightLb: Int = 0,
                goal: TrainingGoal = .recomp, experience: ExperienceLevel = .returning,
                limitations: String = "",
                startingPoint: StartingPoint = .unsure, priorityFocuses: [BodyFocus] = [],
                daysPerWeek: Int = 0, environment: TrainingEnvironment = .fullGym) {
        self.name = name
        self.ageYears = ageYears
        self.sex = sex
        self.heightInches = heightInches
        self.bodyweightLb = bodyweightLb
        self.goal = goal
        self.experience = experience
        self.limitations = limitations
        self.startingPoint = startingPoint
        self.priorityFocuses = priorityFocuses
        self.daysPerWeek = daysPerWeek
        self.environment = environment
    }

    /// One-line summary of the new intake for the coach/planner prompts. Empty parts are
    /// dropped, so it scales from "nothing set" to a full picture.
    public var coachingClause: String {
        var parts: [String] = []
        if startingPoint != .unsure { parts.append("Starting point: \(startingPoint.coachPhrase)") }
        if !priorityFocuses.isEmpty { parts.append("Wants to bring up: \(priorityFocuses.map(\.label).joined(separator: ", "))") }
        if daysPerWeek > 0 { parts.append("Has \(daysPerWeek) training days/week") }
        parts.append("Trains in \(environment.coachPhrase)")
        return parts.joined(separator: ". ") + "."
    }

    /// Whether enough is set to personalize (a name is the minimum).
    public var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// e.g. `5'11"`; empty when unset.
    public var heightString: String {
        guard heightInches > 0 else { return "" }
        return "\(heightInches / 12)'\(heightInches % 12)\""
    }

    /// e.g. `32 y/o, male, 5'11", 180 lb` — only the parts that are set.
    public var statsClause: String {
        var parts: [String] = []
        if ageYears > 0 { parts.append("\(ageYears) y/o") }
        if !sex.coachWord.isEmpty { parts.append(sex.coachWord) }
        if heightInches > 0 { parts.append(heightString) }
        if bodyweightLb > 0 { parts.append("\(bodyweightLb) lb") }
        return parts.joined(separator: ", ")
    }
}
