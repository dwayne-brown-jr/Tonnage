import Foundation

/// A curated training split the athlete can choose. Each preset knows how to build its
/// own session templates, so the seed, the onboarding picker, and a later "change split"
/// all share one source of truth. The progression engine and AI planner are split-
/// agnostic — they operate on whatever sessions the chosen preset produces.
public enum SplitPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case fullBody
    case upperLower
    case pushPullLegs

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fullBody:     "Full Body"
        case .upperLower:   "Upper / Lower"
        case .pushPullLegs: "Push / Pull / Legs"
        }
    }

    public var daysPerWeek: Int {
        switch self {
        case .fullBody:     3
        case .upperLower:   4
        case .pushPullLegs: 6
        }
    }

    /// One-line pitch shown in the picker.
    public var blurb: String {
        switch self {
        case .fullBody:     "3 days. Hit everything each session — best for time-crunched weeks or getting back in."
        case .upperLower:   "4 days. Balanced frequency and recovery — the all-rounder."
        case .pushPullLegs: "6 days. High frequency and volume for dedicated lifters with time to train."
        }
    }

    /// Names + focuses, for the AI planner's "keep these sessions" lock.
    public var sessionSpecs: [SessionSpec] {
        makeSessions().map { SessionSpec(name: $0.name, focus: $0.subtitle) }
    }

    public func makeSessions() -> [SessionTemplate] {
        switch self {
        case .fullBody:     return Self.fullBodySessions()
        case .upperLower:   return Self.upperLowerSessions()
        case .pushPullLegs: return Self.pushPullLegsSessions()
        }
    }

    // MARK: Builder

    private static func ex(_ order: Int, _ name: String, sets: Int, reps: String, rpe: String,
                           compound: Bool = false, cardio: Bool = false, notes: String = "") -> ExerciseTemplate {
        ExerciseTemplate(name: name, prescribedSets: sets, repRange: reps, rpeTarget: rpe,
                         notes: notes, isCompound: compound, isCardio: cardio, sortOrder: order)
    }

    private static func session(_ order: Int, _ name: String, _ subtitle: String,
                                _ exercises: [ExerciseTemplate]) -> SessionTemplate {
        SessionTemplate(name: name, subtitle: subtitle, sortOrder: order, exercises: exercises)
    }

    // MARK: Upper / Lower (4 days) — the default

    static func upperLowerSessions() -> [SessionTemplate] {
        [
            session(0, "Upper A", "Push focus", [
                ex(0, "Barbell Bench Press", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Ramp up, last set is your top set"),
                ex(1, "Seated Shoulder Press", sets: 3, reps: "8-10", rpe: "8", compound: true, notes: "Machine or DB"),
                ex(2, "Chest-Supported Row", sets: 3, reps: "10-12", rpe: "8", compound: true, notes: "Squeeze, slow eccentric"),
                ex(3, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8", notes: "Wide grip"),
                ex(4, "Cable Triceps Pushdown", sets: 2, reps: "12-15", rpe: "9"),
                ex(5, "DB Incline Curl", sets: 2, reps: "10-12", rpe: "9"),
                ex(6, "Stair Master (finisher)", sets: 1, reps: "10 min", rpe: "easy", cardio: true, notes: "Optional")
            ]),
            session(1, "Lower A", "Squat focus", [
                ex(0, "Barbell Back Squat", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Romanian Deadlift", sets: 3, reps: "8-10", rpe: "8", compound: true, notes: "Hinge, neutral spine"),
                ex(2, "Walking DB Lunges", sets: 2, reps: "10/leg", rpe: "8"),
                ex(3, "Leg Curl", sets: 2, reps: "12-15", rpe: "9", notes: "Or DB RDL if no machine"),
                ex(4, "Standing Calf Raise", sets: 3, reps: "12-15", rpe: "9", notes: "Full stretch, pause top"),
                ex(5, "Hanging Knee Raise", sets: 3, reps: "12-15", rpe: "8", notes: "Or cable crunch")
            ]),
            session(2, "Upper B", "Pull focus", [
                ex(0, "Barbell Row", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true, notes: "Log top set. Or chest-supported row."),
                ex(1, "Incline DB Press", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8", notes: "Close grip"),
                ex(3, "DB Lateral Raise", sets: 3, reps: "12-15", rpe: "9", notes: "Light, strict, slow"),
                ex(4, "Cable Face Pull", sets: 2, reps: "15", rpe: "8", notes: "Rear delts + upper back"),
                ex(5, "EZ-bar or DB Curl", sets: 2, reps: "10-12", rpe: "9"),
                ex(6, "Bike intervals (finisher)", sets: 1, reps: "10 min", rpe: "moderate", cardio: true, notes: "30s hard / 60s easy")
            ]),
            session(3, "Lower B", "Hinge focus", [
                ex(0, "Romanian Deadlift", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true, notes: "DB or barbell. Log top set."),
                ex(1, "Front Squat / Goblet Squat", sets: 3, reps: "8-10", rpe: "8", compound: true, notes: "Heavy DB OK"),
                ex(2, "Bulgarian Split Squat", sets: 2, reps: "10/leg", rpe: "8"),
                ex(3, "Cable Pull-Through", sets: 3, reps: "12-15", rpe: "8", notes: "Or hip thrust. Glute focus."),
                ex(4, "Seated Calf Raise", sets: 3, reps: "12-15", rpe: "9"),
                ex(5, "Cable Wood Chop / Pallof", sets: 3, reps: "10/side", rpe: "8", notes: "Anti-rotation")
            ])
        ]
    }

    // MARK: Full Body (3 days)

    static func fullBodySessions() -> [SessionTemplate] {
        [
            session(0, "Full Body A", "Squat focus", [
                ex(0, "Barbell Back Squat", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Barbell Bench Press", sets: 3, reps: "6-8", rpe: "8", compound: true),
                ex(2, "Barbell Row", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(3, "Leg Curl", sets: 2, reps: "12-15", rpe: "9"),
                ex(4, "DB Lateral Raise", sets: 3, reps: "12-15", rpe: "9"),
                ex(5, "Standing Calf Raise", sets: 3, reps: "12-15", rpe: "9")
            ]),
            session(1, "Full Body B", "Hinge focus", [
                ex(0, "Romanian Deadlift", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Seated Shoulder Press", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8"),
                ex(3, "Leg Press", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(4, "Cable Triceps Pushdown", sets: 2, reps: "12-15", rpe: "9"),
                ex(5, "Hanging Knee Raise", sets: 3, reps: "12-15", rpe: "8")
            ]),
            session(2, "Full Body C", "Push focus", [
                ex(0, "Incline DB Press", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Front Squat / Goblet Squat", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Chest-Supported Row", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(3, "Bulgarian Split Squat", sets: 2, reps: "10/leg", rpe: "8"),
                ex(4, "EZ-bar or DB Curl", sets: 2, reps: "10-12", rpe: "9"),
                ex(5, "Seated Calf Raise", sets: 3, reps: "12-15", rpe: "9")
            ])
        ]
    }

    // MARK: Push / Pull / Legs (6 days)

    static func pushPullLegsSessions() -> [SessionTemplate] {
        [
            session(0, "Push A", "Chest focus", [
                ex(0, "Barbell Bench Press", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Seated Shoulder Press", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Incline DB Press", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(3, "DB Lateral Raise", sets: 3, reps: "12-15", rpe: "9"),
                ex(4, "Cable Triceps Pushdown", sets: 3, reps: "12-15", rpe: "9")
            ]),
            session(1, "Pull A", "Back width", [
                ex(0, "Barbell Row", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8", compound: true, notes: "Wide grip"),
                ex(2, "Chest-Supported Row", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(3, "Cable Face Pull", sets: 3, reps: "15", rpe: "8", notes: "Rear delts"),
                ex(4, "Barbell or EZ-bar Curl", sets: 3, reps: "10-12", rpe: "9")
            ]),
            session(2, "Legs A", "Squat focus", [
                ex(0, "Barbell Back Squat", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Romanian Deadlift", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Leg Press", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(3, "Leg Curl", sets: 3, reps: "12-15", rpe: "9"),
                ex(4, "Standing Calf Raise", sets: 3, reps: "12-15", rpe: "9")
            ]),
            session(3, "Push B", "Shoulder focus", [
                ex(0, "Overhead Press", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Incline Barbell Press", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Cable Fly", sets: 3, reps: "12-15", rpe: "9"),
                ex(3, "DB Lateral Raise", sets: 3, reps: "12-15", rpe: "9"),
                ex(4, "Overhead Triceps Extension", sets: 3, reps: "10-12", rpe: "9")
            ]),
            session(4, "Pull B", "Back thickness", [
                ex(0, "Weighted Pull-up / Lat Pulldown", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Seated Cable Row", sets: 3, reps: "10-12", rpe: "8", compound: true),
                ex(2, "Single-arm DB Row", sets: 3, reps: "10-12", rpe: "8"),
                ex(3, "Rear-delt Fly", sets: 3, reps: "15", rpe: "8"),
                ex(4, "DB Incline Curl", sets: 3, reps: "10-12", rpe: "9")
            ]),
            session(5, "Legs B", "Hinge focus", [
                ex(0, "Deadlift", sets: 3, reps: "4-6", rpe: "7→8→8", compound: true, notes: "Log top set"),
                ex(1, "Front Squat", sets: 3, reps: "8-10", rpe: "8", compound: true),
                ex(2, "Bulgarian Split Squat", sets: 2, reps: "10/leg", rpe: "8"),
                ex(3, "Leg Extension", sets: 3, reps: "12-15", rpe: "9"),
                ex(4, "Seated Calf Raise", sets: 3, reps: "12-15", rpe: "9")
            ])
        ]
    }
}

/// A session's identity (name + focus) — the minimal shape the AI planner needs to lock
/// the next block to the athlete's chosen split structure.
public struct SessionSpec: Sendable, Equatable {
    public let name: String
    public let focus: String
    public init(name: String, focus: String) {
        self.name = name
        self.focus = focus
    }
}
