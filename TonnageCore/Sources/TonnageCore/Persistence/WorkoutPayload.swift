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
        public init(weight: Double, reps: Int, rpe: Double?, completed: Bool) {
            self.weight = weight; self.reps = reps; self.rpe = rpe; self.completed = completed
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
        public init(name: String, isCompound: Bool, isCardio: Bool, prescribedSets: Int,
                    repRange: String, rpeTarget: String, prescriptionNotes: String, sets: [Set]) {
            self.name = name; self.isCompound = isCompound; self.isCardio = isCardio
            self.prescribedSets = prescribedSets; self.repRange = repRange
            self.rpeTarget = rpeTarget; self.prescriptionNotes = prescriptionNotes; self.sets = sets
        }
    }

    public var blockNumber: Int?   // optional for backward-compatible decoding (nil → block 1)
    public var weekNumber: Int
    public var sessionName: String
    public var dayType: DayType
    public var date: Date
    public var exercises: [Exercise]

    public init(blockNumber: Int? = nil, weekNumber: Int, sessionName: String, dayType: DayType, date: Date, exercises: [Exercise]) {
        self.blockNumber = blockNumber; self.weekNumber = weekNumber; self.sessionName = sessionName
        self.dayType = dayType; self.date = date; self.exercises = exercises
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
                    sets: e.orderedSets.map { Set(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, completed: $0.completed) }
                )
            }
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
    workout.exercises = payload.exercises.enumerated().map { idx, e in
        let exercise = LoggedExercise(name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                                      sortOrder: idx, prescribedSets: e.prescribedSets, repRange: e.repRange,
                                      rpeTarget: e.rpeTarget, prescriptionNotes: e.prescriptionNotes)
        exercise.sets = e.sets.enumerated().map { i, s in
            LoggedSet(weight: s.weight, reps: s.reps, rpe: s.rpe, completed: s.completed, sortOrder: i)
        }
        return exercise
    }
    context.insert(workout)
    try? context.save()
}
