import Foundation
import SwiftData
import TonnageCore

/// Display-only guidance bundle for one exercise (not persisted).
struct ExerciseGuidance: Equatable {
    let call: CoachsCall
    let last: LastTopSet?
}

/// Owns the SwiftData side of the TRAIN screen: resolving / creating the
/// `LoggedWorkout` for a (week, session), pre-filling sets from the Coach's Call,
/// caching per-exercise guidance, and pruning empty auto-created workouts so
/// browsing weeks doesn't litter history.
@MainActor
@Observable
final class TrainStore {
    private(set) var workout: LoggedWorkout?
    private(set) var guidance: [String: ExerciseGuidance] = [:]

    /// When true (low readiness from HealthKit), the Coach's Call + set cues hold loads
    /// instead of adding. Set by TrainView from the day's readiness read.
    var readinessHoldsProgression = false

    private var context: ModelContext?

    func configure(_ context: ModelContext) {
        if self.context == nil { self.context = context }
    }

    // MARK: Loading

    /// Find-or-create the lift workout for (block, week, session) and ensure it's populated.
    func loadLift(block: Int, week: Int, session: SessionTemplate) {
        guard let context else { return }
        pruneIfEmpty(workout)

        let w = findOrCreate(block: block, week: week, session: session, dayType: .lift)

        // First visit to this (block, week, session): snapshot the template into logged exercises.
        if (w.exercises ?? []).isEmpty {
            w.exercises = session.orderedExercises.enumerated().map { index, t in
                makeLoggedExercise(template: t, index: index, block: block, week: week, sessionName: session.name)
            }
        }
        try? context.save()
        rebuildGuidance(for: w, block: block, week: week)
        workout = w
    }

    /// Sentinel session name for standalone rest-day logs — a rest day is a calendar day,
    /// not one of the program's sessions.
    static let restSlotName = "Rest Day"

    /// For active/full-rest days: surface today's rest entry (if any). Never auto-creates.
    func loadRest(block: Int, week: Int) {
        guard context != nil else { return }
        pruneIfEmpty(workout)
        guidance = [:]
        workout = todaysRest(block: block, week: week)
    }

    /// Persist a standalone rest day for today — decoupled from any session, so logging a
    /// rest never touches your Upper/Lower workouts. One entry per calendar day.
    func logRestDay(block: Int, week: Int, dayType: DayType) {
        guard let context else { return }
        let w = todaysRest(block: block, week: week)
            ?? {
                let new = LoggedWorkout(blockNumber: block, weekNumber: week, dayType: dayType,
                                        sessionName: Self.restSlotName)
                context.insert(new)
                return new
            }()
        w.dayType = dayType
        try? context.save()
        workout = w
        Haptics.success()
    }

    /// Today's standalone rest entry for this block/week, if one exists.
    private func todaysRest(block: Int, week: Int) -> LoggedWorkout? {
        guard let context else { return nil }
        let name = Self.restSlotName
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week && $0.sessionName == name }
        )
        let cal = Calendar.current
        return (try? context.fetch(descriptor))?.first { cal.isDateInToday($0.date) }
    }

    // MARK: Set editing

    func addSet(to exercise: LoggedExercise) {
        guard let context else { return }
        let next = ((exercise.sets ?? []).map(\.sortOrder).max() ?? -1) + 1
        let last = exercise.orderedSets.last
        let set = LoggedSet(weight: last?.weight ?? 0, reps: last?.reps ?? 0, rpe: nil,
                            durationSeconds: last?.durationSeconds,
                            distanceMiles: last?.distanceMiles,
                            flights: last?.flights,
                            completed: false, sortOrder: next)
        context.insert(set)
        exercise.sets = (exercise.sets ?? []) + [set]
        try? context.save()
        Haptics.impact(.light)
    }

    func deleteSet(_ set: LoggedSet, from exercise: LoggedExercise) {
        guard let context else { return }
        exercise.sets?.removeAll { $0 === set }
        context.delete(set)
        try? context.save()
    }

    func save() { try? context?.save() }

    // MARK: Per-week edits (mutate this week's workout only; base template untouched)

    func addCustomExercise(name: String, isCompound: Bool, isCardio: Bool,
                           sets: Int, repRange: String, rpeTarget: String, notes: String, block: Int, week: Int) {
        guard let context, let w = workout else { return }
        let order = ((w.exercises ?? []).map(\.sortOrder).max() ?? -1) + 1
        let ex = LoggedExercise(name: name, isCompound: isCompound, isCardio: isCardio, sortOrder: order,
                                prescribedSets: sets, repRange: repRange, rpeTarget: rpeTarget, prescriptionNotes: notes)
        ex.sets = makeSets(name: name, isCardio: isCardio, sets: sets, repRange: repRange, block: block, week: week, sessionName: w.sessionName)
        context.insert(ex)
        w.exercises = (w.exercises ?? []) + [ex]
        w.isCustomized = true
        save()
        rebuildGuidance(for: w, block: block, week: week)
        Haptics.success()
    }

    /// Used for both "edit prescription" (resetSets = false) and "swap" (resetSets = true).
    func editExercise(_ ex: LoggedExercise, name: String, isCompound: Bool, isCardio: Bool,
                      sets: Int, repRange: String, rpeTarget: String, notes: String,
                      block: Int, week: Int, resetSets: Bool) {
        guard let context, let w = workout else { return }
        if ex.name != name { ex.exerciseTemplate = nil }   // swapped to a different movement
        ex.name = name; ex.isCompound = isCompound; ex.isCardio = isCardio
        ex.prescribedSets = sets; ex.repRange = repRange; ex.rpeTarget = rpeTarget; ex.prescriptionNotes = notes
        if resetSets {
            for s in (ex.sets ?? []) { context.delete(s) }
            ex.sets = makeSets(name: name, isCardio: isCardio, sets: sets, repRange: repRange, block: block, week: week, sessionName: w.sessionName)
        }
        w.isCustomized = true
        save()
        rebuildGuidance(for: w, block: block, week: week)
        Haptics.impact(.rigid)
    }

    func removeExercise(_ ex: LoggedExercise) {
        guard let context, let w = workout else { return }
        w.exercises?.removeAll { $0 === ex }
        context.delete(ex)
        w.isCustomized = true
        save()
        Haptics.impact(.rigid)
    }

    // MARK: Pruning

    func pruneIfEmpty(_ candidate: LoggedWorkout?) {
        guard let candidate, let context else { return }
        if candidate.dayType == .lift && !candidate.hasContent {
            context.delete(candidate)
            try? context.save()
        }
        if workout === candidate { workout = nil }
    }

    // MARK: Private helpers

    private func findOrCreate(block: Int, week: Int, session: SessionTemplate, dayType: DayType) -> LoggedWorkout {
        if let existing = existingWorkout(block: block, week: week, sessionName: session.name) {
            existing.dayType = dayType
            existing.sessionTemplate = session
            return existing
        }
        let new = LoggedWorkout(blockNumber: block, weekNumber: week, dayType: dayType,
                                sessionName: session.name, sessionTemplate: session)
        context?.insert(new)
        return new
    }

    private func existingWorkout(block: Int, week: Int, sessionName: String) -> LoggedWorkout? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == week && $0.sessionName == sessionName }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func makeLoggedExercise(template t: ExerciseTemplate, index: Int, block: Int, week: Int, sessionName: String) -> LoggedExercise {
        let exercise = LoggedExercise(name: t.name, isCompound: t.isCompound, isCardio: t.isCardio, sortOrder: index,
                                      prescribedSets: t.prescribedSets, repRange: t.repRange,
                                      rpeTarget: t.rpeTarget, prescriptionNotes: t.notes, exerciseTemplate: t)
        exercise.sets = makeSets(name: t.name, isCardio: t.isCardio, sets: t.prescribedSets,
                                 repRange: t.repRange, block: block, week: week, sessionName: sessionName)
        return exercise
    }

    /// Builds pre-filled sets: cardio gets one timed set; strength gets `sets` sets
    /// pre-loaded from the Coach's Call.
    private func makeSets(name: String, isCardio: Bool, sets: Int, repRange: String,
                          block: Int, week: Int, sessionName: String) -> [LoggedSet] {
        if isCardio {
            let metrics = ExerciseLibrary.metrics(for: name, isCardio: true)
            let seconds = metrics.contains(.time) ? CoachEngine.lowRep(of: repRange) * 60 : nil
            return [LoggedSet(durationSeconds: seconds, completed: false, sortOrder: 0)]
        }
        let call = guidance(name: name, repRange: repRange, isCardio: false, block: block, week: week, sessionName: sessionName).call
        return (0..<max(1, sets)).map { i in
            LoggedSet(weight: call.suggestedWeight ?? 0, reps: call.suggestedReps ?? 0,
                      rpe: nil, completed: false, sortOrder: i)
        }
    }

    private func rebuildGuidance(for w: LoggedWorkout, block: Int, week: Int) {
        var g: [String: ExerciseGuidance] = [:]
        for ex in (w.exercises ?? []) {
            g[ex.name] = guidance(name: ex.name, repRange: ex.repRange,
                                  isCardio: ex.isCardio, block: block, week: week, sessionName: w.sessionName)
        }
        guidance = g
    }

    private func guidance(name: String, repRange: String, isCardio: Bool, block: Int, week: Int, sessionName: String) -> ExerciseGuidance {
        let last = lastTopSet(named: name, block: block, beforeWeek: week, sessionName: sessionName)
        let call = CoachEngine.call(week: week, last: last, repRange: repRange, isCardio: isCardio,
                                    holdProgression: readinessHoldsProgression)
        return ExerciseGuidance(call: call, last: last)
    }

    /// Within a block, compares to last week's session. On a new block's Week 1, carries
    /// the heaviest top set from the previous block forward (so strength isn't lost).
    private func lastTopSet(named name: String, block: Int, beforeWeek week: Int, sessionName: String) -> LastTopSet? {
        guard let context else { return nil }

        if week > 1 {
            let prevWeek = week - 1
            let descriptor = FetchDescriptor<LoggedWorkout>(
                predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == prevWeek && $0.sessionName == sessionName }
            )
            guard let previous = (try? context.fetch(descriptor))?.first,
                  let exercise = previous.exercises?.first(where: { $0.name == name }),
                  let top = exercise.topSet else { return nil }
            return LastTopSet(weight: top.weight, reps: top.reps, rpe: top.rpe)
        }

        // Week 1 of a later block → best top set from the previous block.
        guard block > 1 else { return nil }
        let prevBlock = block - 1
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == prevBlock && $0.sessionName == sessionName }
        )
        let prior = (try? context.fetch(descriptor)) ?? []
        let tops = prior.compactMap { $0.exercises?.first(where: { $0.name == name })?.topSet }
        guard let best = tops.max(by: { ($0.weight, Double($0.reps)) < ($1.weight, Double($1.reps)) }) else { return nil }
        return LastTopSet(weight: best.weight, reps: best.reps, rpe: best.rpe)
    }
}
