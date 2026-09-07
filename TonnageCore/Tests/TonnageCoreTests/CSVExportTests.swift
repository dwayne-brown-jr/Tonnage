import Testing
import Foundation
@testable import TonnageCore

@Suite("CSV export")
@MainActor
struct CSVExportTests {

    private func makeWorkout() -> LoggedWorkout {
        let w = LoggedWorkout(date: Date(timeIntervalSince1970: 1_700_000_000),
                              blockNumber: 2, weekNumber: 3, dayType: .lift, sessionName: "Upper A")
        w.notes = "slept well, strong"
        let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, isCardio: false,
                                sortOrder: 0, prescribedSets: 2, repRange: "5-7", rpeTarget: "8",
                                prescriptionNotes: "")
        let warm = LoggedSet(weight: 135, reps: 8, completed: true, isWarmup: true, sortOrder: 0)
        let top = LoggedSet(weight: 225, reps: 5, rpe: 8, completed: true, sortOrder: 1)
        top.note = "paused last rep, \"grindy\""
        ex.sets = [warm, top]
        w.exercises = [ex]
        return w
    }

    @Test("One row per set with header, warm-ups flagged, working sets numbered")
    func rowsAndNumbering() {
        let csv = CSVExport.workoutsCSV([makeWorkout()])
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)   // header + 2 sets
        #expect(lines[0] == CSVExport.header)
        #expect(lines[1].contains(",W,true,false,false,135,8,"))     // warm-up row
        #expect(lines[2].contains(",1,false,false,false,225,5,2,"))  // working set 1, reps-left 2 (RPE 8)
        #expect(lines[2].contains("Barbell Bench Press"))
        #expect(lines[2].contains("Chest"))
    }

    @Test("Fields with commas and quotes are RFC-4180 escaped")
    func escaping() {
        #expect(CSVExport.escape("plain") == "plain")
        #expect(CSVExport.escape("a, b") == "\"a, b\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        let csv = CSVExport.workoutsCSV([makeWorkout()])
        #expect(csv.contains("\"paused last rep, \"\"grindy\"\"\""))
    }
}
