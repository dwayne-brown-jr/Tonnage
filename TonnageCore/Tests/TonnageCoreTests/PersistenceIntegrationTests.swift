import Testing
import Foundation
import SwiftData
@testable import TonnageCore

// NOTE: These exercise a REAL SwiftData ModelContainer, which crashes under `swift test`
// (the macOS SPM test host has no app bundle/entitlements). They run only when hosted on
// an iOS test target / simulator (where the same in-memory container works, as in the app
// + previews). Gated to iOS so `swift test` on macOS stays green; see UPDATE_PLAN.md for
// adding the iOS unit-test target that runs these.
#if canImport(UIKit)

/// Integration tests: data must survive save→fetch, cascade correctly, and travel intact
/// through backup + watch-sync payloads (continuity).
@MainActor
@Suite("Persistence integration")
struct PersistenceIntegrationTests {

    private func makeCtx() -> ModelContext {
        TonnageStore.makeContainer(inMemory: true).mainContext
    }

    private func liftWorkout(block: Int = 1, week: Int = 1, session: String = "Upper A",
                             sets: [(Double, Int)] = [(135, 5), (140, 5)]) -> LoggedWorkout {
        let w = LoggedWorkout(blockNumber: block, weekNumber: week, dayType: .lift, sessionName: session)
        let ex = LoggedExercise(name: "Bench", isCompound: true, sortOrder: 0)
        ex.sets = sets.enumerated().map { i, s in
            LoggedSet(weight: s.0, reps: s.1, rpe: 8, completed: true, sortOrder: i)
        }
        w.exercises = [ex]
        return w
    }

    @Test("Workout graph survives save → fetch with relationships intact")
    func roundTripFetch() throws {
        let ctx = makeCtx()
        ctx.insert(liftWorkout())
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<LoggedWorkout>())
        #expect(fetched.count == 1)
        let w = try #require(fetched.first)
        #expect(w.sessionName == "Upper A")
        #expect((w.exercises ?? []).count == 1)
        #expect((w.exercises?.first?.sets ?? []).count == 2)
        #expect(w.completedSetCount == 2)
        #expect(w.exercises?.first?.topSet?.weight == 140)
    }

    @Test("Deleting a workout cascades to its exercises and sets")
    func cascadeDelete() throws {
        let ctx = makeCtx()
        let w = liftWorkout()
        ctx.insert(w)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<LoggedSet>()).count == 2)

        ctx.delete(w)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<LoggedWorkout>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<LoggedExercise>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<LoggedSet>()).isEmpty)   // no orphans
    }

    @Test("Backup export → encode → decode → import preserves data")
    func backupRoundTrip() throws {
        let src = makeCtx()
        src.insert(liftWorkout())
        src.insert(Activity(name: "Bike", kind: .bike, durationMinutes: 30, distanceMiles: 8, date: .now))
        try src.save()

        let workouts = try src.fetch(FetchDescriptor<LoggedWorkout>())
        let activities = try src.fetch(FetchDescriptor<Activity>())
        let data = try makeBackup(workouts: workouts, activities: activities).encoded()
        let decoded = try #require(BackupData.decoded(from: data))

        let dst = makeCtx()
        applyBackup(decoded, to: dst)
        let restoredW = try dst.fetch(FetchDescriptor<LoggedWorkout>())
        let restoredA = try dst.fetch(FetchDescriptor<Activity>())
        #expect(restoredW.count == 1)
        #expect(restoredW.first?.completedSetCount == 2)
        #expect(restoredA.count == 1)
        #expect(restoredA.first?.kind == .bike)
    }

    @Test("Re-importing the same backup does NOT duplicate workouts or activities")
    func backupReimportDedupe() throws {
        let src = makeCtx()
        src.insert(liftWorkout())
        src.insert(Activity(name: "Walk", kind: .walk, durationMinutes: 20, date: .now))
        try src.save()
        let data = try makeBackup(
            workouts: try src.fetch(FetchDescriptor<LoggedWorkout>()),
            activities: try src.fetch(FetchDescriptor<Activity>())
        ).encoded()
        let backup = try #require(BackupData.decoded(from: data))

        let dst = makeCtx()
        applyBackup(backup, to: dst)
        applyBackup(backup, to: dst)   // import twice
        #expect(try dst.fetch(FetchDescriptor<LoggedWorkout>()).count == 1)   // upserted by (week, session)
        #expect(try dst.fetch(FetchDescriptor<Activity>()).count == 1)        // de-duped by kind+name+minute
    }

    @Test("Watch payload round-trips through Codable and reconstructs faithfully")
    func workoutPayloadRoundTrip() throws {
        let src = makeCtx()
        let w = liftWorkout(block: 2, week: 3, session: "Lower B", sets: [(225, 5), (230, 3)])
        src.insert(w)
        try src.save()

        let payload = WorkoutPayload(from: w)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WorkoutPayload.self, from: data)

        let dst = makeCtx()
        applyWorkoutPayload(decoded, to: dst)
        let arrived = try #require(try dst.fetch(FetchDescriptor<LoggedWorkout>()).first)
        #expect(arrived.blockNumber == 2)
        #expect(arrived.weekNumber == 3)
        #expect(arrived.sessionName == "Lower B")
        #expect(arrived.completedSetCount == 2)
        #expect(arrived.exercises?.first?.topSet?.weight == 230)
    }

    @Test("Applying a payload twice for the same slot replaces, not duplicates")
    func workoutPayloadUpsert() throws {
        let ctx = makeCtx()
        applyWorkoutPayload(WorkoutPayload(from: liftWorkout(sets: [(100, 5)])), to: ctx)
        applyWorkoutPayload(WorkoutPayload(from: liftWorkout(sets: [(115, 5)])), to: ctx) // same block/week/session
        let all = try ctx.fetch(FetchDescriptor<LoggedWorkout>())
        #expect(all.count == 1)                                  // replaced, not duplicated
        #expect(all.first?.exercises?.first?.topSet?.weight == 115)
    }
}

#endif
