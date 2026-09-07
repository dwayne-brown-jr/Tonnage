import XCTest
import Foundation
import SwiftData
import TonnageCore

/// Integration tests against a REAL SwiftData container — the layer the pure-logic unit
/// tests can't touch. Native XCTest (the bundle's format), hosted by the Tonnage app so the
/// container initializes as it does in the running app. Uses only public TonnageCore API.
@MainActor
final class PersistenceIntegrationTests: XCTestCase {

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

    func testWorkoutGraphSurvivesSaveAndFetch() throws {
        let ctx = makeCtx()
        ctx.insert(liftWorkout())
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<LoggedWorkout>())
        XCTAssertEqual(fetched.count, 1)
        let w = try XCTUnwrap(fetched.first)
        XCTAssertEqual(w.sessionName, "Upper A")
        XCTAssertEqual((w.exercises ?? []).count, 1)
        XCTAssertEqual((w.exercises?.first?.sets ?? []).count, 2)
        XCTAssertEqual(w.completedSetCount, 2)
        XCTAssertEqual(w.exercises?.first?.topSet?.weight, 140)
    }

    func testDeletingWorkoutCascades() throws {
        let ctx = makeCtx()
        let w = liftWorkout()
        ctx.insert(w)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LoggedSet>()).count, 2)

        ctx.delete(w)
        try ctx.save()
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<LoggedWorkout>()).isEmpty)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<LoggedExercise>()).isEmpty)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<LoggedSet>()).isEmpty)   // no orphans
    }

    func testBackupRoundTrip() throws {
        let src = makeCtx()
        src.insert(liftWorkout())
        src.insert(Activity(name: "Bike", kind: .bike, durationMinutes: 30, distanceMiles: 8, date: .now))
        try src.save()

        let data = try makeBackup(workouts: try src.fetch(FetchDescriptor<LoggedWorkout>()),
                                  activities: try src.fetch(FetchDescriptor<Activity>())).encoded()
        let decoded = try XCTUnwrap(BackupData.decoded(from: data))

        let dst = makeCtx()
        applyBackup(decoded, to: dst)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<LoggedWorkout>()).count, 1)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<LoggedWorkout>()).first?.completedSetCount, 2)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<Activity>()).first?.kind, .bike)
    }

    func testBackupReimportDoesNotDuplicate() throws {
        let src = makeCtx()
        src.insert(liftWorkout())
        src.insert(Activity(name: "Walk", kind: .walk, durationMinutes: 20, date: .now))
        try src.save()
        let data = try makeBackup(workouts: try src.fetch(FetchDescriptor<LoggedWorkout>()),
                                  activities: try src.fetch(FetchDescriptor<Activity>())).encoded()
        let backup = try XCTUnwrap(BackupData.decoded(from: data))

        let dst = makeCtx()
        applyBackup(backup, to: dst)
        applyBackup(backup, to: dst)   // import twice
        XCTAssertEqual(try dst.fetch(FetchDescriptor<LoggedWorkout>()).count, 1)   // upserted by (week, session)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<Activity>()).count, 1)        // de-duped
    }

    func testWatchPayloadRoundTrip() throws {
        let src = makeCtx()
        let w = liftWorkout(block: 2, week: 3, session: "Lower B", sets: [(225, 5), (230, 3)])
        src.insert(w)
        try src.save()

        let payload = WorkoutPayload(from: w)
        let decoded = try JSONDecoder().decode(WorkoutPayload.self, from: try JSONEncoder().encode(payload))

        let dst = makeCtx()
        applyWorkoutPayload(decoded, to: dst)
        let arrived = try XCTUnwrap(try dst.fetch(FetchDescriptor<LoggedWorkout>()).first)
        XCTAssertEqual(arrived.blockNumber, 2)
        XCTAssertEqual(arrived.weekNumber, 3)
        XCTAssertEqual(arrived.sessionName, "Lower B")
        XCTAssertEqual(arrived.completedSetCount, 2)
        XCTAssertEqual(arrived.exercises?.first?.topSet?.weight, 230)
    }

    func testWatchPayloadUpsertReplaces() throws {
        let ctx = makeCtx()
        applyWorkoutPayload(WorkoutPayload(from: liftWorkout(sets: [(100, 5)])), to: ctx)
        applyWorkoutPayload(WorkoutPayload(from: liftWorkout(sets: [(115, 5)])), to: ctx) // same slot
        let all = try ctx.fetch(FetchDescriptor<LoggedWorkout>())
        XCTAssertEqual(all.count, 1)                                  // replaced, not duplicated
        XCTAssertEqual(all.first?.exercises?.first?.topSet?.weight, 115)
    }
}
