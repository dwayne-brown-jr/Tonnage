import Testing
import Foundation
@testable import TonnageCore

@Suite("PR moments (bugfix)")
struct PersonalRecordsBugTests {

    private func day(_ o: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(o) * 86_400) }

    private func benchWorkout(_ date: Date, sets: [(Double, Int)]) -> LoggedWorkout {
        let w = LoggedWorkout(date: date, blockNumber: 1, weekNumber: 1, dayType: .lift, sessionName: "Upper")
        let ex = LoggedExercise(name: "Bench", sortOrder: 0)
        ex.sets = sets.enumerated().map { i, s in
            LoggedSet(weight: s.0, reps: s.1, rpe: nil, completed: true, sortOrder: i)
        }
        w.exercises = [ex]
        return w
    }

    @Test("Several beating sets in one session fire exactly one PR (no id collision)")
    func singlePRPerSession() {
        let logs = [benchWorkout(day(0), sets: [(135, 5)]),
                    benchWorkout(day(1), sets: [(136, 5), (145, 5)])]
        let prs = PersonalRecords.recentPRs(in: logs)
        #expect(prs.count == 1)
        #expect(prs.first?.weight == 145)
        #expect(Set(prs.map(\.id)).count == prs.count)
    }

    @Test("A high-rep set (>12) neither fires nor seeds a PR")
    func highRepIgnored() {
        let logs = [benchWorkout(day(0), sets: [(100, 12)]),   // baseline
                    benchWorkout(day(1), sets: [(100, 13)]),   // higher Epley but >12 reps → ignored
                    benchWorkout(day(2), sets: [(105, 12)])]   // real PR
        let prs = PersonalRecords.recentPRs(in: logs)
        #expect(prs.count == 1)
        #expect(prs.first?.weight == 105)
    }

    @Test("An identical e1RM is not a PR (strict beat)")
    func tieIsNotPR() {
        let logs = [benchWorkout(day(0), sets: [(200, 5)]),
                    benchWorkout(day(1), sets: [(200, 5)])]
        #expect(PersonalRecords.recentPRs(in: logs).isEmpty)
    }

    @Test("Epley formula")
    func epley() {
        #expect(PersonalRecords.epley(weight: 100, reps: 30) == 200)
        #expect(abs(PersonalRecords.epley(weight: 135, reps: 5) - 157.5) < 0.001)
    }
}
