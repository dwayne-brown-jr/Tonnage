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
        /// `LoggedSet.syncID` — matches this set to the same set on the other device.
        public var id: String?
        /// True when the set was logged or changed on the watch, so the phone knows the
        /// watch's values are newer than its own. False for sets the watch only mirrors.
        public var editedOnWatch: Bool?

        public init(weight: Double, reps: Int, rpe: Double?, completed: Bool,
                    isWarmup: Bool? = nil, isDropSet: Bool? = nil, isAMRAP: Bool? = nil, note: String? = nil,
                    durationSeconds: Int? = nil, distanceMiles: Double? = nil, flights: Int? = nil,
                    id: String? = nil, editedOnWatch: Bool? = nil) {
            self.weight = weight; self.reps = reps; self.rpe = rpe; self.completed = completed
            self.isWarmup = isWarmup; self.isDropSet = isDropSet; self.isAMRAP = isAMRAP; self.note = note
            self.durationSeconds = durationSeconds; self.distanceMiles = distanceMiles; self.flights = flights
            self.id = id; self.editedOnWatch = editedOnWatch
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
    /// Completed working sets (warm-ups excluded).
    public var completedWorkingSets: Int {
        exercises.reduce(0) { $0 + $1.sets.filter { $0.completed && !($0.isWarmup ?? false) }.count }
    }
}

public extension WorkoutPayload {
    /// Snapshot a persisted `LoggedWorkout` into a sendable payload (phone → watch, and
    /// backups). Gives any set without a `syncID` one first, so every exported set can be
    /// recognised when it comes back.
    @MainActor
    init(from w: LoggedWorkout) {
        for e in w.exercises ?? [] {
            for s in e.sets ?? [] where s.syncID == nil { s.syncID = UUID().uuidString }
        }
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
                            durationSeconds: $0.durationSeconds, distanceMiles: $0.distanceMiles, flights: $0.flights,
                            id: $0.syncID)
                    },
                    supersetWithNext: e.supersetWithNext ? true : nil
                )
            },
            notes: w.notes.isEmpty ? nil : w.notes
        )
    }
}

/// Applies a synced payload (from the watch, or a backup) to a phone `ModelContext` by
/// MERGING it into the matching workout — never by deleting and replacing it — so no set
/// that exists on either side is lost.
///
/// - Lift days match on (block, week, session); rest days match on (block, calendar day,
///   day type), so a week can hold several rest days.
/// - Sets match by `syncID` first. A matched set takes the payload's values when the
///   payload completed it and the phone hadn't, or when the watch edited it.
/// - Unmatched sets line up by position (warm-ups with warm-ups, working sets with working
///   sets). An incomplete phone set is filled; a different completed phone set is kept and
///   the payload's set is added after it. Mirrors the watch never edited are skipped, so a
///   set deleted on the phone doesn't come back.
/// - The phone workout keeps its date. Exercises only the payload has are added when they
///   carry a completed set.
///
/// A lift payload with no completed sets changes nothing. Returns whether anything changed.
@MainActor
@discardableResult
public func applyWorkoutPayload(_ payload: WorkoutPayload, to context: ModelContext) -> Bool {
    if payload.dayType == .lift && !payload.anyCompleted { return false }

    let block = payload.blockNumber ?? 1
    let week = payload.weekNumber
    let name = payload.sessionName
    let candidates: [LoggedWorkout]
    if payload.dayType == .lift {
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week && $0.sessionName == name },
            sortBy: [SortDescriptor(\.date)]
        )
        candidates = (try? context.fetch(descriptor)) ?? []
    } else {
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week },
            sortBy: [SortDescriptor(\.date)]
        )
        let cal = Calendar.current
        candidates = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.dayType == payload.dayType && cal.isDate($0.date, inSameDayAs: payload.date)
        }
    }

    let changed: Bool
    if let target = candidates.first {
        changed = WorkoutMerge.merge(payload, into: target, context: context)
    } else {
        context.insert(WorkoutMerge.makeWorkout(from: payload))
        changed = true
    }
    guard changed else { return false }
    do {
        try context.save()
        return true
    } catch {
        // Don't leave a half-applied merge behind.
        context.rollback()
        return false
    }
}

/// The pieces of `applyWorkoutPayload`.
@MainActor
enum WorkoutMerge {

    static func makeWorkout(from payload: WorkoutPayload) -> LoggedWorkout {
        let workout = LoggedWorkout(date: payload.date, blockNumber: payload.blockNumber ?? 1,
                                    weekNumber: payload.weekNumber, dayType: payload.dayType,
                                    sessionName: payload.sessionName, isCustomized: false)
        workout.notes = payload.notes ?? ""
        workout.exercises = payload.exercises.enumerated().map { idx, e in makeExercise(e, sortOrder: idx) }
        return workout
    }

    static func makeExercise(_ e: WorkoutPayload.Exercise, sortOrder: Int) -> LoggedExercise {
        let exercise = LoggedExercise(name: e.name, isCompound: e.isCompound, isCardio: e.isCardio,
                                      sortOrder: sortOrder, prescribedSets: e.prescribedSets, repRange: e.repRange,
                                      rpeTarget: e.rpeTarget, prescriptionNotes: e.prescriptionNotes)
        exercise.supersetWithNext = e.supersetWithNext ?? false
        exercise.sets = e.sets.enumerated().map { i, s in makeSet(s, sortOrder: i) }
        return exercise
    }

    static func makeSet(_ s: WorkoutPayload.Set, sortOrder: Int) -> LoggedSet {
        let set = LoggedSet(sortOrder: sortOrder)
        copy(s, into: set)
        set.isWarmup = s.isWarmup ?? false
        set.syncID = s.id
        return set
    }

    /// Payload values onto a phone set. Optional details only overwrite when present.
    static func copy(_ s: WorkoutPayload.Set, into set: LoggedSet) {
        if s.completed && !set.completed { set.timestamp = .now }   // logged just now, elsewhere
        set.weight = s.weight
        set.reps = s.reps
        if let rpe = s.rpe { set.rpe = rpe }
        set.completed = s.completed
        set.isDropSet = s.isDropSet ?? set.isDropSet
        set.isAMRAP = s.isAMRAP ?? set.isAMRAP
        if let note = s.note { set.note = note }
        if let d = s.durationSeconds { set.durationSeconds = d }
        if let d = s.distanceMiles { set.distanceMiles = d }
        if let f = s.flights { set.flights = f }
    }

    /// Same performance (load, reps, cardio metrics). Effort isn't part of identity: a set
    /// whose RPE was only logged on one side is still the same set.
    static func sameValues(_ s: WorkoutPayload.Set, _ set: LoggedSet) -> Bool {
        s.completed == set.completed && s.weight == set.weight && s.reps == set.reps
            && (s.durationSeconds == nil || s.durationSeconds == set.durationSeconds)
            && (s.distanceMiles == nil || s.distanceMiles == set.distanceMiles)
            && (s.flights == nil || s.flights == set.flights)
    }

    static func merge(_ payload: WorkoutPayload, into workout: LoggedWorkout, context: ModelContext) -> Bool {
        var changed = false
        if workout.notes.isEmpty, let notes = payload.notes, !notes.isEmpty {
            workout.notes = notes
            changed = true
        }

        var used = Set<ObjectIdentifier>()
        var nextOrder = (workout.exercises ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
        for pe in payload.exercises {
            let key = ExerciseLibrary.historyKey(for: pe.name)
            if let ex = workout.orderedExercises.first(where: {
                !used.contains(ObjectIdentifier($0)) && ($0.name == pe.name || ExerciseLibrary.historyKey(for: $0.name) == key)
            }) {
                used.insert(ObjectIdentifier(ex))
                if mergeSets(pe.sets, into: ex, context: context) { changed = true }
            } else if pe.sets.contains(where: \.completed) {
                let ex = makeExercise(pe, sortOrder: nextOrder)
                nextOrder += 1
                context.insert(ex)
                workout.exercises = (workout.exercises ?? []) + [ex]
                used.insert(ObjectIdentifier(ex))
                changed = true
            }
        }
        return changed
    }

    static func mergeSets(_ incoming: [WorkoutPayload.Set], into exercise: LoggedExercise,
                          context: ModelContext) -> Bool {
        var changed = false
        let phoneSets = exercise.orderedSets
        var matched = Set<ObjectIdentifier>()
        var unmatched: [WorkoutPayload.Set] = []

        // 1. Same set on both sides (by syncID).
        for p in incoming {
            guard let id = p.id, let set = phoneSets.first(where: { $0.syncID == id }) else {
                unmatched.append(p)
                continue
            }
            matched.insert(ObjectIdentifier(set))
            let watchWins = p.completed && (!set.completed || p.editedOnWatch == true)
            if watchWins && (!sameValues(p, set) || (p.rpe != nil && p.rpe != set.rpe)) {
                copy(p, into: set)
                changed = true
            } else if set.rpe == nil, let rpe = p.rpe, sameValues(p, set) {
                set.rpe = rpe
                changed = true
            }
        }

        // 2. Everything else, by position within warm-ups and within working sets.
        var nextOrder = (phoneSets.map(\.sortOrder).max() ?? -1) + 1
        var additions: [LoggedSet] = []
        for warmup in [true, false] {
            let phonePart = phoneSets.filter { $0.isWarmup == warmup && !matched.contains(ObjectIdentifier($0)) }
            let payloadPart = unmatched.filter { ($0.isWarmup ?? false) == warmup }
            for (i, p) in payloadPart.enumerated() {
                // An untouched watch set adds nothing; a mirror the watch never edited
                // whose phone set is gone was deleted on the phone — leave it deleted.
                guard p.completed, p.editedOnWatch != false else { continue }
                if i < phonePart.count {
                    let set = phonePart[i]
                    if !set.completed {
                        copy(p, into: set)
                        if let id = p.id { set.syncID = id }
                        changed = true
                        continue
                    }
                    if sameValues(p, set) {
                        if set.syncID == nil, let id = p.id { set.syncID = id; changed = true }
                        if set.rpe == nil, let rpe = p.rpe { set.rpe = rpe; changed = true }
                        continue
                    }
                }
                let set = makeSet(p, sortOrder: nextOrder)
                nextOrder += 1
                context.insert(set)
                additions.append(set)
                changed = true
            }
        }
        if !additions.isEmpty { exercise.sets = (exercise.sets ?? []) + additions }
        return changed
    }
}
