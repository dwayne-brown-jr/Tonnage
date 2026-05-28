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

    public init(name: String = "", ageYears: Int = 0, sex: BiologicalSex = .unspecified,
                heightInches: Int = 0, bodyweightLb: Int = 0,
                goal: TrainingGoal = .recomp, experience: ExperienceLevel = .returning,
                limitations: String = "") {
        self.name = name
        self.ageYears = ageYears
        self.sex = sex
        self.heightInches = heightInches
        self.bodyweightLb = bodyweightLb
        self.goal = goal
        self.experience = experience
        self.limitations = limitations
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
