import Testing
import Foundation
import SwiftData
@testable import TonnageCore

// Audit item 11: restores merge (never overwrite newer logs), keep every rest day in a
// week, and carry the program plus the current block and week.

@MainActor
private func makeContext() -> ModelContext {
    let config = ModelConfiguration(schema: TonnageStore.schema, isStoredInMemoryOnly: true)
    return ModelContext(try! ModelContainer(for: TonnageStore.schema, configurations: config))
}

private let monday = Date(timeIntervalSince1970: 1_760_000_000)

@Suite("Backup restore")
@MainActor
struct BackupRestoreTests {

    private func rest(_ date: Date) -> WorkoutPayload {
        WorkoutPayload(blockNumber: 1, weekNumber: 1, sessionName: "", dayType: .activeRest, date: date, exercises: [])
    }

    @Test("Every rest day in a week survives a restore")
    func restDaysByDate() throws {
        let ctx = makeContext()
        let backup = BackupData(workouts: [rest(monday), rest(monday.addingTimeInterval(2 * 86_400)),
                                           rest(monday.addingTimeInterval(4 * 86_400))], activities: [])
        applyBackup(backup, to: ctx)
        #expect(try ctx.fetch(FetchDescriptor<LoggedWorkout>()).count == 3)
        let again = applyBackup(backup, to: ctx)   // re-import is a no-op
        #expect(again.workoutsChanged == 0)
        #expect(try ctx.fetch(FetchDescriptor<LoggedWorkout>()).count == 3)
    }

    @Test("A restore never overwrites sets logged after the backup")
    func newerLogsSurvive() throws {
        let ctx = makeContext()
        let w = LoggedWorkout(date: monday, blockNumber: 1, weekNumber: 2, dayType: .lift, sessionName: "Upper A")
        let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
        ex.sets = [LoggedSet(weight: 185, reps: 5, completed: true, sortOrder: 0)]
        w.exercises = [ex]
        ctx.insert(w)
        try ctx.save()
        let backup = makeBackup(workouts: [w], activities: [])
        ex.sets?.append(LoggedSet(weight: 195, reps: 3, completed: true, sortOrder: 1))   // logged later
        try ctx.save()

        applyBackup(backup, to: ctx)
        #expect(ex.orderedSets.count == 2)
        #expect(ex.topSet?.weight == 195)
    }

    @Test("v2 carries the program and position; v1 files still read")
    func programAndPosition() throws {
        let src = makeContext()
        seedIfNeeded(src)
        let program = try #require(try src.fetch(FetchDescriptor<Program>()).first)
        let backup = makeBackup(workouts: [], activities: [], program: program, currentBlock: 3, currentWeek: 4)
        let decoded = try #require(BackupData.decoded(from: backup.encoded()))
        #expect(decoded.version == 2 && decoded.currentBlock == 3 && decoded.currentWeek == 4)
        #expect(decoded.contentsSummary.contains("Block 3, Week 4"))

        let dst = makeContext()
        seedIfNeeded(dst)
        let dstProgram = try #require(try dst.fetch(FetchDescriptor<Program>()).first)
        dstProgram.orderedSessions.first?.name = "Renamed"
        try dst.save()
        let result = applyBackup(decoded, to: dst)
        #expect(result.programRestored)
        #expect(ProgramPayload(from: dstProgram) == decoded.program)

        let v1 = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","workouts":[],"activities":[]}"#
        let old = try #require(BackupData.decoded(from: Data(v1.utf8)))
        #expect(old.program == nil && old.currentBlock == nil)
    }

    @Test("Backups from a newer app version are refused")
    func newerVersionRejected() {
        let v9 = #"{"version":9,"exportedAt":"2026-01-01T00:00:00Z","workouts":[],"activities":[]}"#
        #expect(BackupData.decoded(from: Data(v9.utf8)) == nil)
    }
}
