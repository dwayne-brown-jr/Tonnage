import Testing
import Foundation
@testable import TonnageCore

@Suite("Training streak / fatigue")
struct FatigueTests {

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    private func lift(_ date: Date, work: Bool = true) -> LoggedWorkout {
        let w = LoggedWorkout(date: date, blockNumber: 1, weekNumber: 1, dayType: .lift, sessionName: "Upper")
        if work {
            let ex = LoggedExercise(name: "Bench", sortOrder: 0)
            ex.sets = [LoggedSet(weight: 100, reps: 5, rpe: nil, completed: true, sortOrder: 0)]
            w.exercises = [ex]
        }
        return w
    }
    private func rest(_ date: Date, _ type: DayType) -> LoggedWorkout {
        LoggedWorkout(date: date, blockNumber: 1, weekNumber: 1, dayType: type, sessionName: "Rest Day")
    }

    @Test("Counts consecutive lift days up to today")
    func counts() {
        let logs = [lift(day(0)), lift(day(-1)), lift(day(-2))]
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 3)
    }

    @Test("A full rest day resets the streak")
    func fullRestResets() {
        let logs = [lift(day(0)), rest(day(-1), .fullRest), lift(day(-2))]
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 1)
    }

    @Test("A gap day (nothing logged) ends the streak")
    func gapEnds() {
        let logs = [lift(day(0)), lift(day(-2))]   // yesterday is a gap
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 1)
    }

    @Test("Active rest carries the streak without counting itself")
    func activeRestCarries() {
        let logs = [lift(day(0)), rest(day(-1), .activeRest), lift(day(-2))]
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 2)
    }

    @Test("Today not yet logged still counts prior days")
    func todayEmpty() {
        let logs = [lift(day(-1)), lift(day(-2))]
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 2)
    }

    @Test("An empty lift (no completed sets) doesn't count")
    func emptyLiftIgnored() {
        let logs = [lift(day(0), work: false), lift(day(-1))]
        #expect(FatigueEngine.trainingStreak(workouts: logs, asOf: today) == 1)
    }

    @Test("Recommends rest at the threshold, not below")
    func threshold() {
        #expect(FatigueEngine.recommendsRest(FatigueEngine.restNudgeThreshold))
        #expect(!FatigueEngine.recommendsRest(FatigueEngine.restNudgeThreshold - 1))
    }
}
