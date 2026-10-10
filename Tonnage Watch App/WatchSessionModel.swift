import Foundation
import TonnageCore

/// In-memory logging state for a watch session. Snapshots the chosen session
/// template into plain structs (no SwiftData coupling), then produces a
/// `WorkoutPayload` to sync to the phone on finish.
@MainActor
@Observable
final class WatchSessionModel {
    struct SetEntry: Identifiable {
        let id = UUID()
        var weight: Double
        var reps: Int
        var completed: Bool
        // Passthrough fields the watch doesn't edit but must NOT erase on sync —
        // the phone applies a synced payload wholesale, so dropping these here
        // wiped phone-logged RPE, warm-ups, cardio metrics, and notes.
        var rpe: Double? = nil
        var isWarmup: Bool = false
        var isDropSet: Bool = false
        var isAMRAP: Bool = false
        var note: String? = nil
        var durationSeconds: Int? = nil
        var distanceMiles: Double? = nil
        var flights: Int? = nil
        /// Same identity as the phone's `LoggedSet.syncID`, so the phone merges this set
        /// into its own copy instead of adding a duplicate.
        var syncID: String = UUID().uuidString
        /// Logged or changed on the watch — tells the phone these values are newer.
        var editedOnWatch: Bool = false
    }

    struct Exercise: Identifiable {
        let id = UUID()
        var name: String
        var isCompound: Bool
        var isCardio: Bool
        var prescribedSets: Int
        var repRange: String
        var rpeTarget: String
        var notes: String
        var sets: [SetEntry]
        /// Passthrough — superset pairing made on the phone survives the round-trip.
        var supersetWithNext: Bool = false

        var completedCount: Int { sets.filter(\.completed).count }
        var isDone: Bool { !sets.isEmpty && sets.allSatisfy(\.completed) }
    }

    let blockNumber: Int
    let weekNumber: Int
    let sessionName: String
    var exercises: [Exercise]
    /// Session notes logged on the phone — carried through the watch round-trip.
    private let phoneNotes: String?
    /// When the session was first logged (on either device). Sync keeps this date rather
    /// than stamping the workout with the moment Finish was tapped.
    let startedAt: Date

    /// Builds from the program template, or — when the phone already logged this
    /// session (`existing`) — from that logged state so the watch mirrors the phone.
    init(session: SessionTemplate, block: Int, week: Int, existing: WorkoutPayload? = nil) {
        blockNumber = block
        weekNumber = week
        sessionName = session.name
        phoneNotes = existing?.notes
        startedAt = existing?.date ?? Date()

        if let existing {
            exercises = existing.exercises.map { e in
                Exercise(
                    name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                    prescribedSets: e.prescribedSets, repRange: e.repRange,
                    rpeTarget: e.rpeTarget, notes: e.prescriptionNotes,
                    sets: e.sets.map {
                        SetEntry(weight: $0.weight, reps: $0.reps, completed: $0.completed,
                                 rpe: $0.rpe, isWarmup: $0.isWarmup ?? false,
                                 isDropSet: $0.isDropSet ?? false, isAMRAP: $0.isAMRAP ?? false,
                                 note: $0.note,
                                 durationSeconds: $0.durationSeconds, distanceMiles: $0.distanceMiles,
                                 flights: $0.flights, syncID: $0.id ?? UUID().uuidString)
                    },
                    supersetWithNext: e.supersetWithNext ?? false
                )
            }
        } else {
            exercises = session.orderedExercises.map { t in
                let count = t.isCardio ? 1 : max(1, t.prescribedSets)
                let startReps = CoachEngine.lowRep(of: t.repRange)
                return Exercise(
                    name: t.name, isCompound: t.isCompound, isCardio: t.isCardio,
                    prescribedSets: t.prescribedSets, repRange: t.repRange,
                    rpeTarget: t.rpeTarget, notes: t.notes,
                    sets: (0..<count).map { _ in SetEntry(weight: 0, reps: startReps, completed: false) }
                )
            }
        }
    }

    /// Completed working sets — warm-ups don't count toward sets, reps or volume,
    /// matching the phone's numbers.
    private var workingSets: [SetEntry] {
        exercises.flatMap(\.sets).filter { $0.completed && !$0.isWarmup }
    }
    var completedSets: Int { workingSets.count }
    var totalVolume: Double { workingSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var totalReps: Int { workingSets.reduce(0) { $0 + $1.reps } }
    /// Anything at all was logged, warm-ups included — worth syncing.
    var hasCompletedSets: Bool { exercises.contains { $0.sets.contains(where: \.completed) } }

    /// Snapshot for the HealthKit workout's metadata — the same `HealthMetadataKeys` the
    /// phone stamps, so Tonnage Fuel reads one shape whichever device logged the session.
    var liftMeta: LiftSessionMeta {
        let compoundTop = exercises.first(where: { $0.isCompound })?.sets
            .filter { $0.completed && !$0.isWarmup }
            .max { ($0.weight, Double($0.reps)) < ($1.weight, Double($1.reps)) }?.rpe
        let rpe = compoundTop ?? exercises.flatMap(\.sets).compactMap(\.rpe).first
        return LiftSessionMeta(sessionName: sessionName, totalVolumeLb: totalVolume,
                               setCount: completedSets, totalReps: totalReps,
                               block: blockNumber, week: weekNumber,
                               isDeload: weekNumber >= 5, topSetRPE: rpe)
    }

    func addSet(toExerciseAt index: Int) {
        guard exercises.indices.contains(index) else { return }
        let last = exercises[index].sets.last
        exercises[index].sets.append(SetEntry(weight: last?.weight ?? 0, reps: last?.reps ?? 0, completed: false))
    }

    func payload() -> WorkoutPayload {
        WorkoutPayload(
            blockNumber: blockNumber, weekNumber: weekNumber, sessionName: sessionName, dayType: .lift, date: startedAt,
            exercises: exercises.map { e in
                WorkoutPayload.Exercise(
                    name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                    prescribedSets: e.prescribedSets, repRange: e.repRange,
                    rpeTarget: e.rpeTarget, prescriptionNotes: e.notes,
                    sets: e.sets.map {
                        .init(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, completed: $0.completed,
                              isWarmup: $0.isWarmup ? true : nil,
                              isDropSet: $0.isDropSet ? true : nil,
                              isAMRAP: $0.isAMRAP ? true : nil,
                              note: $0.note,
                              durationSeconds: $0.durationSeconds, distanceMiles: $0.distanceMiles,
                              flights: $0.flights, id: $0.syncID, editedOnWatch: $0.editedOnWatch)
                    },
                    supersetWithNext: e.supersetWithNext ? true : nil
                )
            },
            notes: phoneNotes
        )
    }
}
