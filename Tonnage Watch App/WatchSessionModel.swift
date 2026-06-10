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

    /// Builds from the program template, or — when the phone already logged this
    /// session (`existing`) — from that logged state so the watch mirrors the phone.
    init(session: SessionTemplate, block: Int, week: Int, existing: WorkoutPayload? = nil) {
        blockNumber = block
        weekNumber = week
        sessionName = session.name
        phoneNotes = existing?.notes

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
                                 flights: $0.flights)
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

    var completedSets: Int { exercises.reduce(0) { $0 + $1.completedCount } }
    var totalVolume: Double {
        exercises.flatMap(\.sets).filter(\.completed).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    func addSet(toExerciseAt index: Int) {
        guard exercises.indices.contains(index) else { return }
        let last = exercises[index].sets.last
        exercises[index].sets.append(SetEntry(weight: last?.weight ?? 0, reps: last?.reps ?? 0, completed: false))
    }

    func payload() -> WorkoutPayload {
        WorkoutPayload(
            blockNumber: blockNumber, weekNumber: weekNumber, sessionName: sessionName, dayType: .lift, date: Date(),
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
                              flights: $0.flights)
                    },
                    supersetWithNext: e.supersetWithNext ? true : nil
                )
            },
            notes: phoneNotes
        )
    }
}
