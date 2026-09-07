import Foundation
import SwiftData

/// An actual training session performed on a date.
@Model
public final class LoggedWorkout {
    public var date: Date = Date.now
    /// Which mesocycle this belongs to (Block 01 = 1). Lets training continue past Week 5.
    public var blockNumber: Int = 1
    public var weekNumber: Int = 1
    public var dayType: DayType = DayType.lift
    public var notes: String = ""

    /// True once the user edits/swaps/removes/adds an exercise for this week. Keeps
    /// the workout from being pruned even before any set is logged, so per-week
    /// customizations persist (and still revert next week — that's a fresh workout).
    public var isCustomized: Bool = false

    /// Snapshot of the session name at log time — survives template edits/renames.
    public var sessionName: String = ""

    /// Link back to the template this was based on. Nullify (not cascade): deleting
    /// a workout must never delete the program template, and vice versa.
    public var sessionTemplate: SessionTemplate?

    // Optional for CloudKit mirroring (which requires all relationships to be
    // optional). New instances still get `[]` via the initializer; reads go through
    // `orderedExercises` / `?? []`.
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.workout)
    public var exercises: [LoggedExercise]?

    public init(
        date: Date = .now,
        blockNumber: Int = 1,
        weekNumber: Int,
        dayType: DayType,
        sessionName: String,
        notes: String = "",
        isCustomized: Bool = false,
        sessionTemplate: SessionTemplate? = nil,
        exercises: [LoggedExercise] = []
    ) {
        self.date = date
        self.blockNumber = blockNumber
        self.weekNumber = weekNumber
        self.dayType = dayType
        self.sessionName = sessionName
        self.notes = notes
        self.isCustomized = isCustomized
        self.sessionTemplate = sessionTemplate
        self.exercises = exercises
    }

    public var orderedExercises: [LoggedExercise] {
        (exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Live session stats

    private var allSets: [LoggedSet] { (exercises ?? []).flatMap { $0.sets ?? [] } }
    /// Completed WORKING sets — warm-ups are excluded everywhere this feeds (volume,
    /// reps, adherence, "did you train"), so they never inflate the hard-set math.
    private var completedSets: [LoggedSet] { allSets.filter { $0.completed && !$0.isWarmup } }

    /// Number of completed (checked) sets.
    public var completedSetCount: Int { completedSets.count }
    /// Total reps across completed sets.
    public var totalReps: Int { completedSets.reduce(0) { $0 + $1.reps } }
    /// Total tonnage (Σ weight × reps) across completed sets.
    public var totalVolume: Double { completedSets.reduce(0) { $0 + $1.volume } }

    /// True once at least one set is logged, notes were written, or the user
    /// customized the session — used to decide whether to keep an auto-created workout.
    public var hasContent: Bool { completedSetCount > 0 || !notes.isEmpty || isCustomized }
}

/// One exercise inside a logged workout. Holds a name snapshot so ad-hoc/custom
/// exercises work even without a template link.
@Model
public final class LoggedExercise {
    public var name: String = ""
    public var isCompound: Bool = false
    public var isCardio: Bool = false
    public var sortOrder: Int = 0

    // Prescription snapshot — copied from the template at creation so per-week edits
    // (and custom/swapped exercises) live here without touching the base template.
    public var prescribedSets: Int = 3
    public var repRange: String = ""
    public var rpeTarget: String = ""
    public var prescriptionNotes: String = ""
    /// Paired with the NEXT exercise (by sortOrder) as a superset: alternate sets,
    /// rest only after the chain's last movement. Chains (A→B→C) come from
    /// consecutive flags. Defaults false so existing records migrate untouched.
    public var supersetWithNext: Bool = false

    /// Optional link to the template this came from (nullify on delete).
    public var exerciseTemplate: ExerciseTemplate?

    public var workout: LoggedWorkout?

    // Optional for CloudKit mirroring (see LoggedWorkout.exercises).
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    public var sets: [LoggedSet]?

    public init(
        name: String,
        isCompound: Bool = false,
        isCardio: Bool = false,
        sortOrder: Int,
        prescribedSets: Int = 3,
        repRange: String = "",
        rpeTarget: String = "",
        prescriptionNotes: String = "",
        exerciseTemplate: ExerciseTemplate? = nil,
        sets: [LoggedSet] = []
    ) {
        self.name = name
        self.isCompound = isCompound
        self.isCardio = isCardio
        self.sortOrder = sortOrder
        self.prescribedSets = prescribedSets
        self.repRange = repRange
        self.rpeTarget = rpeTarget
        self.prescriptionNotes = prescriptionNotes
        self.exerciseTemplate = exerciseTemplate
        self.sets = sets
    }

    public var orderedSets: [LoggedSet] {
        (sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Heaviest completed WORKING set, by weight then reps — used for top-set history
    /// (warm-ups excluded so a ramp set never counts as your top set).
    public var topSet: LoggedSet? {
        (sets ?? []).filter { $0.completed && !$0.isWarmup }.max {
            ($0.weight, Double($0.reps)) < ($1.weight, Double($1.reps))
        }
    }

    /// Completed working sets (warm-ups excluded).
    public var completedSetCount: Int { (sets ?? []).filter { $0.completed && !$0.isWarmup }.count }
    public var isFullyLogged: Bool {
        let s = sets ?? []
        return !s.isEmpty && s.allSatisfy(\.completed)
    }
}

/// A single set: weight × reps at an optional RPE.
@Model
public final class LoggedSet {
    // Strength metrics.
    public var weight: Double = 0
    public var reps: Int = 0
    public var rpe: Double?

    // Cardio metrics (nil for strength sets). Which are used depends on the
    // exercise — see `ExerciseLibrary.metrics(for:isCardio:)`.
    public var durationSeconds: Int?
    public var distanceMiles: Double?
    public var flights: Int?

    public var completed: Bool = false
    /// A warm-up (ramp) set — performed but NOT counted as working volume, toward PRs,
    /// top sets, or adherence. Logged like any set; just excluded from the hard-set math.
    public var isWarmup: Bool = false
    /// A back-off performed immediately after the set above at reduced load, no rest
    /// between. Counts as working volume; labeled "D" instead of a set number.
    public var isDropSet: Bool = false
    /// "As many reps as possible" — the reps field records what was achieved.
    public var isAMRAP: Bool = false
    /// Optional per-set note ("felt heavy", "grip gave out") — optional so existing
    /// records and CloudKit mirroring migrate cleanly.
    public var note: String?
    public var timestamp: Date = Date.now
    public var sortOrder: Int = 0

    public var exercise: LoggedExercise?

    public init(
        weight: Double = 0,
        reps: Int = 0,
        rpe: Double? = nil,
        durationSeconds: Int? = nil,
        distanceMiles: Double? = nil,
        flights: Int? = nil,
        completed: Bool = false,
        isWarmup: Bool = false,
        timestamp: Date = .now,
        sortOrder: Int
    ) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.durationSeconds = durationSeconds
        self.distanceMiles = distanceMiles
        self.flights = flights
        self.completed = completed
        self.isWarmup = isWarmup
        self.timestamp = timestamp
        self.sortOrder = sortOrder
    }

    /// Volume contribution (weight × reps) for completed WORKING strength sets.
    public var volume: Double { (completed && !isWarmup) ? weight * Double(reps) : 0 }
}
