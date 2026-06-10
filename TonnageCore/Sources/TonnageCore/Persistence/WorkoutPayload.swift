import Foundation
import SwiftData

/// Codable snapshot of a logged session, sent watch → phone over WatchConnectivity.
/// Decoupled from the `@Model` types so it can cross the process boundary.
public struct WorkoutPayload: Codable, Sendable, Equatable {

    public struct Set: Codable, Sendable, Equatable {
        public var weight: Double
        public var reps: Int
        public var rpe: Double?
        public var completed: Bool
        // Optional for backward-compatible decoding of older payloads/backups —
        // without these the watch round-trip / a backup restore erased warm-up
        // flags, cardio metrics, and per-set notes (wholesale replace, fields lost).
        public var isWarmup: Bool?         // nil → false
        public var isDropSet: Bool?        // nil → false
        public var isAMRAP: Bool?          // nil → false
        public var note: String?
        public var durationSeconds: Int?
        public var distanceMiles: Double?
        public var flights: Int?

        public init(weight: Double, reps: Int, rpe: Double?, completed: Bool,
                    isWarmup: Bool? = nil, isDropSet: Bool? = nil, isAMRAP: Bool? = nil, note: String? = nil,
                    durationSeconds: Int? = nil, distanceMiles: Double? = nil, flights: Int? = nil) {
            self.weight = weight; self.reps = reps; self.rpe = rpe; self.completed = completed
            self.isWarmup = isWarmup; self.isDropSet = isDropSet; self.isAMRAP = isAMRAP; self.note = note
            self.durationSeconds = durationSeconds; self.distanceMiles = distanceMiles; self.flights = flights
        }
    }

    public struct Exercise: Codable, Sendable, Equatable {
        public var name: String
        public var isCompound: Bool
        public var isCardio: Bool
        public var prescribedSets: Int
        public var repRange: String
        public var rpeTarget: String
        public var prescriptionNotes: String
        public var sets: [Set]
        /// Superset pairing with the next exercise — optional for backward-compatible
        /// decoding (nil → false).
        public var supersetWithNext: Bool?

        public init(name: String, isCompound: Bool, isCardio: Bool, prescribedSets: Int,
                    repRange: String, rpeTarget: String, prescriptionNotes: String, sets: [Set],
                    supersetWithNext: Bool? = nil) {
            self.name = name; self.isCompound = isCompound; self.isCardio = isCardio
            self.prescribedSets = prescribedSets; self.repRange = repRange
            self.rpeTarget = rpeTarget; self.prescriptionNotes = prescriptionNotes; self.sets = sets
            self.supersetWithNext = supersetWithNext
        }
    }

    public var blockNumber: Int?   // optional for backward-compatible decoding (nil → block 1)
    public var weekNumber: Int
    public var sessionName: String
    public var dayType: DayType
    public var date: Date
    public var exercises: [Exercise]
    /// Session notes — optional for backward-compatible decoding (nil → "").
    public var notes: String?

    public init(blockNumber: Int? = nil, weekNumber: Int, sessionName: String, dayType: DayType, date: Date,
                exercises: [Exercise], notes: String? = nil) {
        self.blockNumber = blockNumber; self.weekNumber = weekNumber; self.sessionName = sessionName
        self.dayType = dayType; self.date = date; self.exercises = exercises; self.notes = notes
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(from data: Data) -> WorkoutPayload? { try? JSONDecoder().decode(Self.self, from: data) }

    /// Every set across the workout is completed (used to badge a finished session).
    public var isFullyLogged: Bool {
        !exercises.isEmpty && exercises.allSatisfy { !$0.sets.isEmpty && $0.sets.allSatisfy(\.completed) }
    }
    /// At least one set is completed (session is in progress).
    public var anyCompleted: Bool { exercises.contains { $0.sets.contains(where: { $0.completed }) } }
}

public extension WorkoutPayload {
    /// Snapshot a persisted `LoggedWorkout` into a sendable payload (phone → watch).
    @MainActor
    init(from w: LoggedWorkout) {
        self.init(
            blockNumber: w.blockNumber, weekNumber: w.weekNumber, sessionName: w.sessionName,
            dayType: w.dayType, date: w.date,
            exercises: w.orderedExercises.map { e in
                Exercise(
                    name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                    prescribedSets: e.prescribedSets, repRange: e.repRange,
                    rpeTarget: e.rpeTarget, prescriptionNotes: e.prescriptionNotes,
                    sets: e.orderedSets.map {
                        Set(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, completed: $0.completed,
                            isWarmup: $0.isWarmup ? true : nil,
                            isDropSet: $0.isDropSet ? true : nil,
                            isAMRAP: $0.isAMRAP ? true : nil,
                            note: $0.note,
                            durationSeconds: $0.durationSeconds, distanceMiles: $0.distanceMiles, flights: $0.flights)
                    },
                    supersetWithNext: e.supersetWithNext ? true : nil
                )
            },
            notes: w.notes.isEmpty ? nil : w.notes
        )
    }
}

/// Applies a synced payload to a phone `ModelContext` — replaces any existing
/// workout for the same (week, session) so the watch's record wins.
@MainActor
public func applyWorkoutPayload(_ payload: WorkoutPayload, to context: ModelContext) {
    let block = payload.blockNumber ?? 1
    let week = payload.weekNumber
    let name = payload.sessionName
    let descriptor = FetchDescriptor<LoggedWorkout>(
        predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week && $0.sessionName == name }
    )
    if let existing = try? context.fetch(descriptor) {
        for w in existing { context.delete(w) }
    }

    let workout = LoggedWorkout(date: payload.date, blockNumber: block, weekNumber: week, dayType: payload.dayType,
                                sessionName: name, isCustomized: false)
    workout.notes = payload.notes ?? ""
    workout.exercises = payload.exercises.enumerated().map { idx, e in
        let exercise = LoggedExercise(name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                                      sortOrder: idx, prescribedSets: e.prescribedSets, repRange: e.repRange,
                                      rpeTarget: e.rpeTarget, prescriptionNotes: e.prescriptionNotes)
        exercise.supersetWithNext = e.supersetWithNext ?? false
        exercise.sets = e.sets.enumerated().map { i, s in
            let set = LoggedSet(weight: s.weight, reps: s.reps, rpe: s.rpe,
                                durationSeconds: s.durationSeconds, distanceMiles: s.distanceMiles,
                                flights: s.flights, completed: s.completed,
                                isWarmup: s.isWarmup ?? false, sortOrder: i)
            set.isDropSet = s.isDropSet ?? false
            set.isAMRAP = s.isAMRAP ?? false
            set.note = s.note
            return set
        }
        return exercise
    }
    context.insert(workout)
    do {
        try context.save()
    } catch {
        // Don't leave the delete half-applied (the old record gone, the new one unsaved).
        context.rollback()
    }
}
