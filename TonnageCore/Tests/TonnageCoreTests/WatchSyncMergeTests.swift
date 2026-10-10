import Testing
import Foundation
import SwiftData
@testable import TonnageCore

// Audit items 2, 10 and 12: a watch sync merges into the phone's workout instead of
// replacing it, keeps the workout's date, and the watch gets the phone's real program.

@MainActor
private func makeContext() -> ModelContext {
    let config = ModelConfiguration(schema: TonnageStore.schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TonnageStore.schema, configurations: config)
    return ModelContext(container)
}

private let day = Date(timeIntervalSince1970: 1_760_000_000)

@MainActor
private func phoneWorkout(_ sets: [(Double, Int, Bool)], in context: ModelContext,
                          date: Date = day) -> LoggedWorkout {
    let w = LoggedWorkout(date: date, blockNumber: 1, weekNumber: 2, dayType: .lift, sessionName: "Upper A")
    let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
    ex.sets = sets.enumerated().map { i, s in LoggedSet(weight: s.0, reps: s.1, completed: s.2, sortOrder: i) }
    w.exercises = [ex]
    context.insert(w)
    try! context.save()
    return w
}

private func watchPayload(_ sets: [WorkoutPayload.Set], date: Date = day.addingTimeInterval(7200),
                          exercise: String = "Barbell Bench Press") -> WorkoutPayload {
    WorkoutPayload(blockNumber: 1, weekNumber: 2, sessionName: "Upper A", dayType: .lift, date: date,
                   exercises: [.init(name: exercise, isCompound: true, isCardio: false, prescribedSets: 3,
                                     repRange: "5-7", rpeTarget: "8", prescriptionNotes: "", sets: sets)])
}

@MainActor
private func onlyWorkout(_ context: ModelContext) throws -> LoggedWorkout {
    let all = try context.fetch(FetchDescriptor<LoggedWorkout>())
    #expect(all.count == 1)
    return try #require(all.first)
}

@Suite("Watch sync merge")
@MainActor
struct WatchSyncMergeTests {

    @Test("A payload with nothing completed changes nothing")
    func emptyPayloadIgnored() throws {
        let ctx = makeContext()
        phoneWorkout([(185, 5, true), (185, 5, true), (185, 5, true)], in: ctx)
        let changed = applyWorkoutPayload(watchPayload([.init(weight: 0, reps: 5, rpe: nil, completed: false)]), to: ctx)
        #expect(!changed)
        #expect(try onlyWorkout(ctx).completedSetCount == 3)
    }

    @Test("Phone sets survive a watch session that never saw them (the airplane-mode case)")
    func phoneSetsSurvive() throws {
        let ctx = makeContext()
        phoneWorkout([(185, 5, true), (185, 5, true), (185, 5, true)], in: ctx)
        let payload = watchPayload([
            .init(weight: 185, reps: 5, rpe: 8, completed: true, id: "w1", editedOnWatch: true),
            .init(weight: 195, reps: 4, rpe: 9, completed: true, id: "w2", editedOnWatch: true),
            .init(weight: 0, reps: 5, rpe: nil, completed: false, id: "w3", editedOnWatch: false),
        ])
        applyWorkoutPayload(payload, to: ctx)
        let w = try onlyWorkout(ctx)
        let sets = try #require(w.exercises?.first).orderedSets
        // Three phone sets kept; the identical 185×5 isn't doubled; the different 195×4 is added.
        #expect(sets.filter(\.completed).count == 4)
        #expect(sets.contains { $0.weight == 195 && $0.reps == 4 })
        #expect(w.date == day)   // the phone's date, not the sync time
    }

    @Test("Watch sets fill the phone's unlogged sets")
    func fillsIncompleteSets() throws {
        let ctx = makeContext()
        phoneWorkout([(185, 5, true), (185, 5, false), (185, 5, false)], in: ctx)
        applyWorkoutPayload(watchPayload([
            .init(weight: 185, reps: 5, rpe: 8, completed: true, id: "w1", editedOnWatch: true),
            .init(weight: 190, reps: 5, rpe: 9, completed: true, id: "w2", editedOnWatch: true),
        ]), to: ctx)
        let sets = try #require(try onlyWorkout(ctx).exercises?.first).orderedSets
        #expect(sets.count == 3)
        #expect(sets.map(\.completed) == [true, true, false])
        #expect(sets[1].weight == 190 && sets[1].rpe == 9)
    }

    @Test("Re-applying the same payload is idempotent")
    func idempotent() throws {
        let ctx = makeContext()
        phoneWorkout([(185, 5, true)], in: ctx)
        let payload = watchPayload([.init(weight: 200, reps: 3, rpe: 9, completed: true, id: "w1", editedOnWatch: true)])
        applyWorkoutPayload(payload, to: ctx)
        let again = applyWorkoutPayload(payload, to: ctx)
        #expect(!again)
        #expect(try #require(try onlyWorkout(ctx).exercises?.first).orderedSets.count == 2)
    }

    @Test("A stale watch mirror doesn't undo a phone edit; a watch edit does win")
    func syncIDConflicts() throws {
        let ctx = makeContext()
        let w = phoneWorkout([(185, 5, true), (185, 5, true)], in: ctx)
        let mirror = WorkoutPayload(from: w)                       // assigns sync IDs
        let first = try #require(w.exercises?.first).orderedSets[0]
        first.reps = 6                                             // phone corrects set 1 afterwards
        try ctx.save()

        var stale = mirror                                         // watch still has 185×5, unedited
        applyWorkoutPayload(stale, to: ctx)
        #expect(first.reps == 6)

        stale.exercises[0].sets[1].reps = 7                        // watch edits set 2
        stale.exercises[0].sets[1].editedOnWatch = true
        applyWorkoutPayload(stale, to: ctx)
        let sets = try #require(w.exercises?.first).orderedSets
        #expect(sets.count == 2)
        #expect(sets[0].reps == 6 && sets[1].reps == 7)
    }

    @Test("A set deleted on the phone isn't resurrected by the watch's mirror of it")
    func deletionsStick() throws {
        let ctx = makeContext()
        let w = phoneWorkout([(185, 5, true), (185, 5, true)], in: ctx)
        var mirror = WorkoutPayload(from: w)
        // What the watch sends back for sets it only mirrored.
        for i in mirror.exercises[0].sets.indices { mirror.exercises[0].sets[i].editedOnWatch = false }
        let ex = try #require(w.exercises?.first)
        let doomed = ex.orderedSets[1]
        ex.sets?.removeAll { $0 === doomed }
        ctx.delete(doomed)
        try ctx.save()
        applyWorkoutPayload(mirror, to: ctx)
        #expect(ex.orderedSets.count == 1)
    }

    @Test("Exercises only the watch logged are added; phone-only exercises stay")
    func exerciseUnion() throws {
        let ctx = makeContext()
        phoneWorkout([(185, 5, true)], in: ctx)
        applyWorkoutPayload(watchPayload([.init(weight: 30, reps: 12, rpe: 8, completed: true, editedOnWatch: true)],
                                         exercise: "DB Lateral Raise"), to: ctx)
        let names = try onlyWorkout(ctx).orderedExercises.map(\.name)
        #expect(names == ["Barbell Bench Press", "DB Lateral Raise"])
    }

    @Test("A new session from the watch keeps the watch's start date")
    func newWorkoutKeepsDate() throws {
        let ctx = makeContext()
        let start = day.addingTimeInterval(-3600)
        applyWorkoutPayload(watchPayload([.init(weight: 185, reps: 5, rpe: 8, completed: true, editedOnWatch: true)],
                                         date: start), to: ctx)
        #expect(try onlyWorkout(ctx).date == start)
    }

    @Test("Rest days match by date, so a week keeps more than one")
    func restDaysByDate() throws {
        let ctx = makeContext()
        func rest(_ date: Date) -> WorkoutPayload {
            WorkoutPayload(blockNumber: 1, weekNumber: 2, sessionName: "", dayType: .activeRest, date: date, exercises: [])
        }
        applyWorkoutPayload(rest(day), to: ctx)
        applyWorkoutPayload(rest(day.addingTimeInterval(2 * 86_400)), to: ctx)
        applyWorkoutPayload(rest(day.addingTimeInterval(60)), to: ctx)   // same day again
        #expect(try ctx.fetch(FetchDescriptor<LoggedWorkout>()).count == 2)
    }
}

@Suite("Program sync to the watch")
@MainActor
struct ProgramPayloadTests {

    @Test("The watch's seeded program is replaced by the phone's, and re-applying is a no-op")
    func mirrorsProgram() throws {
        let ctx = makeContext()
        seedIfNeeded(ctx)
        let phone = ProgramPayload(name: "Block 02", sessions: [
            .init(name: "Push", subtitle: "Chest", exercises: [
                .init(name: "Barbell Bench Press", prescribedSets: 4, repRange: "3-5", rpeTarget: "8", isCompound: true),
                .init(name: "Cable Fly", prescribedSets: 3, repRange: "12-15", rpeTarget: "9", supersetWithNext: true),
            ]),
            .init(name: "Pull", subtitle: "Back", exercises: [
                .init(name: "Barbell Row", prescribedSets: 4, repRange: "6-8", rpeTarget: "8", isCompound: true),
            ]),
        ])
        #expect(applyProgramPayload(phone, to: ctx))
        let program = try #require(try ctx.fetch(FetchDescriptor<Program>()).first)
        #expect(program.orderedSessions.map(\.name) == ["Push", "Pull"])
        #expect(ProgramPayload(from: program) == phone)
        #expect(!applyProgramPayload(phone, to: ctx))
        let decoded = try #require(ProgramPayload.decoded(from: phone.encoded()))
        #expect(decoded == phone)
    }
}
