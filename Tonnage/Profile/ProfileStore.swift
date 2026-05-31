import Foundation
import TonnageCore

/// Reads the athlete profile from `UserDefaults` (written by the profile form via
/// `@AppStorage`). Per-device, so every install gets its own coach. Kept tiny and
/// stateless — the source of truth is the defaults keys below.
enum ProfileStore {
    enum Key {
        static let name = "profile.name"
        static let age = "profile.ageYears"
        static let sex = "profile.sex"
        static let height = "profile.heightInches"
        static let weight = "profile.bodyweightLb"
        static let goal = "profile.goal"
        static let experience = "profile.experience"
        static let limitations = "profile.limitations"
        static let split = "profile.split"
    }

    /// The athlete's chosen training split (drives the seeded program + coach framing).
    /// Defaults to Upper/Lower for anyone who hasn't picked.
    static var split: SplitPreset {
        SplitPreset(rawValue: UserDefaults.standard.string(forKey: Key.split) ?? "") ?? .upperLower
    }

    static var current: CoachProfile {
        let d = UserDefaults.standard
        return CoachProfile(
            name: d.string(forKey: Key.name) ?? "",
            ageYears: d.integer(forKey: Key.age),
            sex: BiologicalSex(rawValue: d.string(forKey: Key.sex) ?? "") ?? .unspecified,
            heightInches: d.integer(forKey: Key.height),
            bodyweightLb: d.integer(forKey: Key.weight),
            goal: TrainingGoal(rawValue: d.string(forKey: Key.goal) ?? "") ?? .recomp,
            experience: ExperienceLevel(rawValue: d.string(forKey: Key.experience) ?? "") ?? .returning,
            limitations: d.string(forKey: Key.limitations) ?? ""
        )
    }

    static var isComplete: Bool { current.isComplete }
}
