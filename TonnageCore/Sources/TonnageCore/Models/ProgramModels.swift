import Foundation
import SwiftData

/// Top-level program container (a mesocycle / "block"). Owns its session templates.
/// Week progression metadata lives in `WeekPhase` (the block is always 5 weeks).
@Model
public final class Program {
    public var name: String = ""
    public var createdAt: Date = Date.now

    // Optional for CloudKit mirroring (all relationships must be optional).
    @Relationship(deleteRule: .cascade, inverse: \SessionTemplate.program)
    public var sessions: [SessionTemplate]?

    public init(name: String, createdAt: Date = .now, sessions: [SessionTemplate] = []) {
        self.name = name
        self.createdAt = createdAt
        self.sessions = sessions
    }

    /// Sessions in their authored order.
    public var orderedSessions: [SessionTemplate] {
        (sessions ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// One day of the split, e.g. "Upper A / Push focus". Owns its exercises.
@Model
public final class SessionTemplate {
    public var name: String = ""
    public var subtitle: String = ""
    public var sortOrder: Int = 0

    public var program: Program?

    // Optional for CloudKit mirroring (all relationships must be optional).
    @Relationship(deleteRule: .cascade, inverse: \ExerciseTemplate.session)
    public var exercises: [ExerciseTemplate]?

    /// Inverse for `LoggedWorkout.sessionTemplate` — CloudKit requires every
    /// relationship to have an inverse. Nullify: deleting this template detaches the
    /// snapshot link on logged workouts but never deletes the logs.
    @Relationship(deleteRule: .nullify, inverse: \LoggedWorkout.sessionTemplate)
    public var loggedWorkouts: [LoggedWorkout]?

    public init(
        name: String,
        subtitle: String,
        sortOrder: Int,
        exercises: [ExerciseTemplate] = []
    ) {
        self.name = name
        self.subtitle = subtitle
        self.sortOrder = sortOrder
        self.exercises = exercises
    }

    public var orderedExercises: [ExerciseTemplate] {
        (exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// A prescribed exercise within a session template.
@Model
public final class ExerciseTemplate {
    public var name: String = ""
    public var prescribedSets: Int = 3
    /// Rep range as authored, e.g. "5-7", "10/leg", "10 min".
    public var repRange: String = ""
    /// RPE target as authored, e.g. "8" or "7→8→8".
    public var rpeTarget: String = ""
    public var notes: String = ""
    public var isCompound: Bool = false
    public var isCardio: Bool = false
    public var sortOrder: Int = 0
    /// Superset pairing with the next exercise — mirrors `LoggedExercise.supersetWithNext`
    /// so a pairing made during a session persists into future weeks.
    public var supersetWithNext: Bool = false

    public var session: SessionTemplate?

    /// Inverse for `LoggedExercise.exerciseTemplate` — CloudKit requires every
    /// relationship to have an inverse. Nullify keeps logged exercises intact when a
    /// template is deleted.
    @Relationship(deleteRule: .nullify, inverse: \LoggedExercise.exerciseTemplate)
    public var loggedExercises: [LoggedExercise]?

    public init(
        name: String,
        prescribedSets: Int,
        repRange: String,
        rpeTarget: String,
        notes: String = "",
        isCompound: Bool = false,
        isCardio: Bool = false,
        sortOrder: Int
    ) {
        self.name = name
        self.prescribedSets = prescribedSets
        self.repRange = repRange
        self.rpeTarget = rpeTarget
        self.notes = notes
        self.isCompound = isCompound
        self.isCardio = isCardio
        self.sortOrder = sortOrder
    }
}
