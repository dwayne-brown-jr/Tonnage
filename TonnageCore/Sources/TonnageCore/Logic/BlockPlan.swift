import Foundation

/// A proposed mesocycle — the Coach drafts one of these at block transitions, the
/// user previews + commits, and the program's templates get rewritten to match.
public struct BlockPlan: Codable, Sendable, Equatable {
    public let blockNumber: Int
    public let theme: String         // One-line label, e.g. "Pull focus + push accessory rotation"
    public let summary: String       // 1–2 sentences explaining the intent of the block.
    public let sessions: [SessionPlan]

    public init(blockNumber: Int, theme: String, summary: String, sessions: [SessionPlan]) {
        self.blockNumber = blockNumber
        self.theme = theme
        self.summary = summary
        self.sessions = sessions
    }
}

public struct SessionPlan: Codable, Sendable, Equatable, Identifiable {
    public let name: String          // "Upper A"
    public let subtitle: String      // "Push focus"
    public let exercises: [ExercisePlan]
    public var id: String { name }

    public init(name: String, subtitle: String, exercises: [ExercisePlan]) {
        self.name = name
        self.subtitle = subtitle
        self.exercises = exercises
    }
}

public struct ExercisePlan: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let prescribedSets: Int
    public let repRange: String      // "5-7", "8-10", "10 min" for cardio
    public let rpeTarget: String     // "8", "7→8→8", "easy" for cardio
    public let notes: String
    public let isCompound: Bool
    public let isCardio: Bool
    /// Why this exercise belongs in this session — surfaced to the user under the row.
    public let rationale: String
    /// Whether the planner kept the existing exercise, swapped it for another, or added
    /// a new one. Drives the "kept / swap / new" badge in the preview UI.
    public let change: PlanChange
    public var id: String { name }

    public init(name: String, prescribedSets: Int, repRange: String, rpeTarget: String,
                notes: String = "", isCompound: Bool = false, isCardio: Bool = false,
                rationale: String, change: PlanChange) {
        self.name = name
        self.prescribedSets = prescribedSets
        self.repRange = repRange
        self.rpeTarget = rpeTarget
        self.notes = notes
        self.isCompound = isCompound
        self.isCardio = isCardio
        self.rationale = rationale
        self.change = change
    }
}

/// The type of move the planner made on a given exercise — tagged on every
/// `ExercisePlan` so the preview can show "kept / swap / new" badges.
public enum PlanChange: Codable, Sendable, Equatable {
    case kept                       // same exercise as last block, intentionally preserved
    case swapped(from: String)      // replaced the named exercise
    case new                        // added (no prior counterpart)

    // MARK: Codable — tagged JSON: { "type": "kept" } / { "type": "swapped", "from": "..." } / { "type": "new" }

    private enum CodingKeys: String, CodingKey { case type, from }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "kept":    self = .kept
        case "new":     self = .new
        case "swapped": self = .swapped(from: try c.decode(String.self, forKey: .from))
        default:        throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                               debugDescription: "Unknown PlanChange type '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .kept:                try c.encode("kept", forKey: .type)
        case .new:                 try c.encode("new", forKey: .type)
        case .swapped(let from):   try c.encode("swapped", forKey: .type)
                                   try c.encode(from, forKey: .from)
        }
    }
}
