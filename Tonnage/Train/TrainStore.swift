import Foundation
import SwiftData
import TonnageCore

/// Display-only guidance bundle for one exercise (not persisted).
struct ExerciseGuidance: Equatable {
    let call: CoachsCall
    let last: LastTopSet?
    /// Last comparable session's completed working sets in order, so set row N can show
    /// (and one-tap apply) what you actually did on set N last time.
    let lastSets: [LastTopSet]

    init(call: CoachsCall, last: LastTopSet?, lastSets: [LastTopSet] = []) {
        self.call = call
        self.last = last
        self.lastSets = lastSets
    }
}

/// A just-logged set that beat the lifetime e1RM for its exercise — drives the PR toast.
struct PRCelebration: Equatable {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let estimatedOneRM: Double
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

    /// When true (user started an early deload for this block+week), the Coach's Call
    /// treats this week like W5: ~60% loads, big reserve. Set by TrainView.
    var deloadOverridden = false

    /// Non-nil right after a logged set beats the lifetime e1RM — TrainView shows a toast.
    private(set) var celebration: PRCelebration?
    @ObservationIgnored private var celebratedSetIDs: Set<PersistentIdentifier> = []
    @ObservationIgnored private var celebrationDismissTask: Task<Void, Never>?

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
        context.saveOrReport()
        rebuildGuidance(for: w, block: block, week: week)
        workout = w
    }

    /// Sentinel session name for standalone rest-day logs — a rest day is a calendar day,
    /// not one of the program's sessions.
    static let restSlotName = "Rest Day"

    /// For active/full-rest days: surface the rest entry for `date` (if any). Never auto-creates.
    /// `date` defaults to today; pass a past day to retroactively review/log a missed rest.
    func loadRest(block: Int, week: Int, date: Date = .now) {
        guard context != nil else { return }
        pruneIfEmpty(workout)
        guidance = [:]
        workout = restEntry(block: block, on: date)
    }

    /// Persist a standalone rest day for `date` — decoupled from any session, so logging a
    /// rest never touches your Upper/Lower workouts. One entry per calendar day; `date`
    /// defaults to today but can be backdated (e.g. logging yesterday's rest the next morning).
    func logRestDay(block: Int, week: Int, dayType: DayType, date: Date = .now) {
        guard let context else { return }
        let w = restEntry(block: block, on: date)
            ?? {
                let new = LoggedWorkout(date: date, blockNumber: block, weekNumber: week,
                                        dayType: dayType, sessionName: Self.restSlotName)
                context.insert(new)
                return new
            }()
        w.dayType = dayType
        context.saveOrReport()
        workout = w
        Haptics.success()
    }

    /// The standalone rest entry for this block on a given calendar day, if one exists.
    /// Keyed on (block, calendar-day) — NOT week — so backdating a rest into a day that
    /// fell in a different program-week can't create a second entry for the same real day.
    private func restEntry(block: Int, on date: Date) -> LoggedWorkout? {
        guard let context else { return nil }
        let name = Self.restSlotName
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == block && $0.sessionName == name }
        )
        let cal = Calendar.current
        return (try? context.fetch(descriptor))?.first { cal.isDate($0.date, inSameDayAs: date) }
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
        context.saveOrReport()
        Haptics.impact(.light)
    }

    /// Re-prefill untouched exercises from the (re-derived) Coach's Call — used when
    /// toggling an early deload so the suggested loads actually land in the set rows.
    /// Anything with a completed set is left alone.
    func applySuggestedWeights() {
        guard let w = workout else { return }
        for ex in w.orderedExercises where !ex.isCardio && ex.completedSetCount == 0 {
            guard let call = guidance[ex.name]?.call, let weight = call.suggestedWeight else { continue }
            for s in (ex.sets ?? []) where !s.completed && !s.isWarmup && !s.isDropSet {
                s.weight = weight
                if let reps = call.suggestedReps { s.reps = reps }
            }
        }
        save()
    }

    /// Generate a warm-up ramp toward the exercise's working weight and insert it
    /// before the working sets. No-op if warm-ups already exist or the weight is too
    /// light to need one.
    func addWarmupRamp(to exercise: LoggedExercise) {
        guard let context, !exercise.isCardio,
              !(exercise.sets ?? []).contains(where: { $0.isWarmup }) else { return }
        let workingWeight = (exercise.sets ?? []).filter { !$0.isWarmup }.map(\.weight).max() ?? 0
        let steps = WarmupRamp.steps(workingWeight: workingWeight)
        guard !steps.isEmpty else { return }

        for s in (exercise.sets ?? []) { s.sortOrder += steps.count }   // make room up front
        let warmups = steps.enumerated().map { i, step in
            LoggedSet(weight: step.weight, reps: step.reps, isWarmup: true, sortOrder: i)
        }
        for w in warmups { context.insert(w) }
        exercise.sets = (exercise.sets ?? []) + warmups
        context.saveOrReport()
        Haptics.impact(.light)
    }

    /// Can a ramp be offered for this exercise right now?
    func canAddWarmupRamp(to exercise: LoggedExercise) -> Bool {
        guard !exercise.isCardio,
              !(exercise.sets ?? []).contains(where: { $0.isWarmup }) else { return false }
        let workingWeight = (exercise.sets ?? []).filter { !$0.isWarmup }.map(\.weight).max() ?? 0
        return !WarmupRamp.steps(workingWeight: workingWeight).isEmpty
    }

    /// Insert a drop set right after `set`: classic ~20% back-off (plate-rounded),
    /// same rep target, performed with no rest between.
    func addDropSet(after set: LoggedSet, in exercise: LoggedExercise) {
        guard let context, !exercise.isCardio, !set.isWarmup else { return }
        let ordered = exercise.orderedSets
        guard let i = ordered.firstIndex(where: { $0 === set }) else { return }
        for (k, s) in ordered.enumerated() { s.sortOrder = k }          // normalize
        for s in ordered[(i + 1)...] { s.sortOrder += 1 }               // make room
        let dropWeight = max(0, ((set.weight * 0.8) / 5).rounded() * 5)
        let drop = LoggedSet(weight: dropWeight, reps: set.reps, sortOrder: i + 1)
        drop.isDropSet = true
        context.insert(drop)
        exercise.sets = (exercise.sets ?? []) + [drop]
        context.saveOrReport()
        Haptics.impact(.light)
    }

    func deleteSet(_ set: LoggedSet, from exercise: LoggedExercise) {
        guard let context else { return }
        exercise.sets?.removeAll { $0 === set }
        context.delete(set)
        context.saveOrReport()
    }

    func save() { context?.saveOrReport() }

    // MARK: PR celebration

    /// Did this just-completed set beat the exercise's lifetime e1RM? Mirrors the
    /// `PersonalRecords` rules (working sets only, reps ≤ 12, first-ever set is a
    /// baseline not a PR) so the toast never disagrees with the DATA tab's PR feed.
    func checkForPR(_ set: LoggedSet, exercise: LoggedExercise) {
        guard let context, set.completed, !set.isWarmup, !exercise.isCardio,
              set.weight > 0, set.reps > 0, set.reps <= PersonalRecords.maxRepsForReliableE1RM,
              !celebratedSetIDs.contains(set.persistentModelID) else { return }
        let e1RM = PersonalRecords.epley(weight: set.weight, reps: set.reps)
        let name = exercise.name

        var best = 0.0
        let all = (try? context.fetch(FetchDescriptor<LoggedWorkout>())) ?? []
        for w in all {
            for ex in (w.exercises ?? []) where ex.name == name && !ex.isCardio {
                for s in (ex.sets ?? []) where s.completed && !s.isWarmup && s !== set {
                    guard s.weight > 0, s.reps > 0, s.reps <= PersonalRecords.maxRepsForReliableE1RM else { continue }
                    best = max(best, PersonalRecords.epley(weight: s.weight, reps: s.reps))
                }
            }
        }
        guard best > 0, e1RM > best else { return }

        celebratedSetIDs.insert(set.persistentModelID)   // one celebration per set, even after un/re-complete
        celebration = PRCelebration(exerciseName: name, weight: set.weight, reps: set.reps, estimatedOneRM: e1RM)
        Haptics.impact(.heavy)
        celebrationDismissTask?.cancel()
        celebrationDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.celebration = nil
        }
    }

    func dismissCelebration() {
        celebrationDismissTask?.cancel()
        celebration = nil
    }

    // MARK: Per-week edits (mutate this week's workout only; base template untouched)

    func addCustomExercise(name rawName: String, isCompound: Bool, isCardio: Bool,
                           sets: Int, repRange: String, rpeTarget: String, notes: String, block: Int, week: Int) {
        guard let context, let w = workout else { return }
        // Canonicalize so "Dumbbell Incline Press" and "Incline DB Press" share one history.
        let name = ExerciseLibrary.canonicalDisplayName(for: rawName)
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
    func editExercise(_ ex: LoggedExercise, name rawName: String, isCompound: Bool, isCardio: Bool,
                      sets: Int, repRange: String, rpeTarget: String, notes: String,
                      block: Int, week: Int, resetSets: Bool) {
        guard let context, let w = workout else { return }
        let name = ExerciseLibrary.canonicalDisplayName(for: rawName)
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

    // MARK: Supersets

    /// Link/unlink this exercise with the NEXT one as a superset (alternate sets,
    /// rest after the chain's last movement). Mirrored onto the template so the
    /// pairing persists into future weeks.
    func toggleSuperset(_ ex: LoggedExercise) {
        ex.supersetWithNext.toggle()
        ex.exerciseTemplate?.supersetWithNext = ex.supersetWithNext
        workout?.isCustomized = true
        save()
        Haptics.selection()
    }

    /// Pairing requires a next exercise, and neither side can be cardio.
    func canSupersetWithNext(_ ex: LoggedExercise) -> Bool {
        guard !ex.isCardio, let next = nextExercise(after: ex) else { return false }
        return !next.isCardio
    }

    func nextExercise(after ex: LoggedExercise) -> LoggedExercise? {
        guard let w = workout else { return nil }
        let ordered = w.orderedExercises
        guard let i = ordered.firstIndex(where: { $0 === ex }), i + 1 < ordered.count else { return nil }
        return ordered[i + 1]
    }

    /// True when the PREVIOUS exercise chains into this one (this is A2/A3 of a superset).
    func isSupersetContinuation(_ ex: LoggedExercise) -> Bool {
        guard let w = workout else { return false }
        let ordered = w.orderedExercises
        guard let i = ordered.firstIndex(where: { $0 === ex }), i > 0 else { return false }
        return ordered[i - 1].supersetWithNext
    }

    /// The first movement of the superset chain containing `ex` (itself if unchained).
    func supersetHead(of ex: LoggedExercise) -> LoggedExercise {
        guard let w = workout else { return ex }
        let ordered = w.orderedExercises
        guard var i = ordered.firstIndex(where: { $0 === ex }) else { return ex }
        while i > 0 && ordered[i - 1].supersetWithNext { i -= 1 }
        return ordered[i]
    }

    /// Shift an exercise up (-1) or down (+1) within this session's order.
    func moveExercise(_ ex: LoggedExercise, by offset: Int) {
        guard let w = workout else { return }
        let ordered = w.orderedExercises
        guard let i = ordered.firstIndex(where: { $0 === ex }),
              ordered.indices.contains(i + offset) else { return }
        for (k, e) in ordered.enumerated() { e.sortOrder = k }   // normalize before swapping
        ordered[i].sortOrder = i + offset
        ordered[i + offset].sortOrder = i
        w.isCustomized = true
        save()
        Haptics.selection()
    }

    func canMoveExercise(_ ex: LoggedExercise, by offset: Int) -> Bool {
        guard let w = workout else { return false }
        let ordered = w.orderedExercises
        guard let i = ordered.firstIndex(where: { $0 === ex }) else { return false }
        return ordered.indices.contains(i + offset)
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
            context.saveOrReport()
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
        exercise.supersetWithNext = t.supersetWithNext
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
        let reference = lastReference(named: name, block: block, beforeWeek: week, sessionName: sessionName)
        let call = CoachEngine.call(week: week, last: reference.top, repRange: repRange, isCardio: isCardio,
                                    holdProgression: readinessHoldsProgression,
                                    forceDeload: deloadOverridden)
        return ExerciseGuidance(call: call, last: reference.top, lastSets: reference.sets)
    }

    /// The completed working sets of one logged exercise, in order, as display references.
    /// Drop sets are excluded so set N always lines up with last week's straight set N.
    private func ghostSets(of exercise: LoggedExercise) -> [LastTopSet] {
        exercise.orderedSets
            .filter { $0.completed && !$0.isWarmup && !$0.isDropSet }
            .map { LastTopSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }
    }

    /// Within a block, compares to last week's session. On a new block's Week 1, carries
    /// the heaviest top set from the previous block forward (so strength isn't lost).
    /// `sets` is the same reference session's completed working sets, for per-row ghosts.
    private func lastReference(named name: String, block: Int, beforeWeek week: Int,
                               sessionName: String) -> (top: LastTopSet?, sets: [LastTopSet]) {
        guard let context else { return (nil, []) }

        if week > 1 {
            let prevWeek = week - 1
            let descriptor = FetchDescriptor<LoggedWorkout>(
                predicate: #Predicate { $0.blockNumber == block && $0.weekNumber == prevWeek && $0.sessionName == sessionName }
            )
            guard let previous = (try? context.fetch(descriptor))?.first,
                  let exercise = previous.exercises?.first(where: { $0.name == name }),
                  let top = exercise.topSet else { return (nil, []) }
            return (LastTopSet(weight: top.weight, reps: top.reps, rpe: top.rpe), ghostSets(of: exercise))
        }

        // Week 1 of a later block → best top set from the previous block; ghosts from the
        // most recent prior session that actually logged this exercise.
        guard block > 1 else { return (nil, []) }
        let prevBlock = block - 1
        let descriptor = FetchDescriptor<LoggedWorkout>(
            predicate: #Predicate { $0.blockNumber == prevBlock && $0.sessionName == sessionName }
        )
        let prior = (try? context.fetch(descriptor)) ?? []
        let tops = prior.compactMap { $0.exercises?.first(where: { $0.name == name })?.topSet }
        guard let best = tops.max(by: { ($0.weight, Double($0.reps)) < ($1.weight, Double($1.reps)) }) else { return (nil, []) }
        let latestWithExercise = prior.sorted { $0.date > $1.date }
            .compactMap { $0.exercises?.first(where: { $0.name == name }) }
            .first { !ghostSets(of: $0).isEmpty }
        return (LastTopSet(weight: best.weight, reps: best.reps, rpe: best.rpe),
                latestWithExercise.map(ghostSets(of:)) ?? [])
    }
}
