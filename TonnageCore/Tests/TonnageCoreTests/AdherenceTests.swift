import Testing
import Foundation
@testable import TonnageCore

@Suite("Block adherence")
struct AdherenceTests {

    @Test("Counts completed slots, plans = sessions/week × weeks")
    func basicAdherence() {
        let logs: [LoggedWorkout] = [
            lift(week: 1, session: "Upper A", date: day(0), didWork: true),
            lift(week: 1, session: "Lower A", date: day(1), didWork: true),
            lift(week: 2, session: "Upper A", date: day(7), didWork: true),
            lift(week: 2, session: "Lower A", date: day(8), didWork: false),   // empty workout — not counted
        ]
        let a = AdherenceEngine.computeBlock(workouts: logs, blockNumber: 1, sessionsPerWeek: 4)
        #expect(a.sessionsCompleted == 3)
        #expect(a.sessionsPlanned == 20)
        #expect(a.trainingDays == 3)
        #expect(a.completionPct == 3.0 / 20.0)
    }

    @Test("Rest-day logs are neutral — not counted as sessions or training days")
    func restDaysAreNeutral() {
        let logs = [
            rest(week: 1, session: "Rest Day", date: day(0), type: .activeRest),
            rest(week: 1, session: "Rest Day", date: day(1), type: .fullRest),
            lift(week: 1, session: "Upper A", date: day(2), didWork: true),   // only this counts
        ]
        let a = AdherenceEngine.computeBlock(workouts: logs, blockNumber: 1, sessionsPerWeek: 4)
        #expect(a.sessionsCompleted == 1)
        #expect(a.trainingDays == 1)
    }

    @Test("Filters out workouts from other blocks")
    func filtersByBlock() {
        let logs = [
            lift(week: 1, session: "Upper A", date: day(0), didWork: true, block: 1),
            lift(week: 1, session: "Upper A", date: day(0), didWork: true, block: 2),
        ]
        let a = AdherenceEngine.computeBlock(workouts: logs, blockNumber: 1, sessionsPerWeek: 4)
        #expect(a.sessionsCompleted == 1)
        #expect(a.trainingDays == 1)
    }

    @Test("Empty inputs degrade to zeros, completionPct is safe")
    func emptyInputs() {
        let a = AdherenceEngine.computeBlock(workouts: [], blockNumber: 1, sessionsPerWeek: 4)
        #expect(a.sessionsCompleted == 0)
        #expect(a.sessionsPlanned == 20)
        #expect(a.trainingDays == 0)
        #expect(a.completionPct == 0)

        let unplanned = AdherenceEngine.computeBlock(workouts: [], blockNumber: 1, sessionsPerWeek: 0)
        #expect(unplanned.completionPct == 0)   // no divide-by-zero
    }

    @Test("Multiple lifts on the same day = one training day")
    func dedupesTrainingDays() {
        let logs = [
            lift(week: 1, session: "Upper A", date: day(0), didWork: true),
            lift(week: 1, session: "Lower A", date: day(0), didWork: true),   // same day
        ]
        let a = AdherenceEngine.computeBlock(workouts: logs, blockNumber: 1, sessionsPerWeek: 4)
        #expect(a.sessionsCompleted == 2)
        #expect(a.trainingDays == 1)
    }

    // MARK: helpers

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    private func lift(week: Int, session: String, date: Date, didWork: Bool, block: Int = 1) -> LoggedWorkout {
        let w = LoggedWorkout(date: date, blockNumber: block, weekNumber: week, dayType: .lift, sessionName: session)
        if didWork {
            let ex = LoggedExercise(name: "Lift", sortOrder: 0)
            ex.sets = [LoggedSet(weight: 100, reps: 5, rpe: nil, completed: true, sortOrder: 0)]
            w.exercises = [ex]
        }
        return w
    }

    private func rest(week: Int, session: String, date: Date, type: DayType, block: Int = 1) -> LoggedWorkout {
        LoggedWorkout(date: date, blockNumber: block, weekNumber: week, dayType: type, sessionName: session)
    }
}
