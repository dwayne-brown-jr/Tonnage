import Testing
import Foundation
@testable import TonnageCore

// Smaller audit items: a session that crosses midnight keeps its start date and gets its
// real length in Health; the watch complication shows real week totals.

@Suite("Session timing")
struct SessionTimingTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func workout(start: Date, setTimes: [Date]) -> LoggedWorkout {
        let w = LoggedWorkout(date: start, weekNumber: 2, dayType: .lift, sessionName: "Upper A")
        let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
        ex.sets = setTimes.enumerated().map { i, t in
            LoggedSet(weight: 185, reps: 5, completed: true, timestamp: t, sortOrder: i)
        }
        w.exercises = [ex]
        return w
    }

    @Test("A session past midnight keeps its start and its real length")
    func crossesMidnight() {
        let w = workout(start: at(9, 23, 20), setTimes: [at(9, 23, 25), at(10, 0, 10), at(10, 0, 35)])
        let interval = w.sessionInterval(now: at(10, 9, 0), calendar: calendar)
        #expect(interval.start == at(9, 23, 20))
        #expect(interval.duration == 76 * 60)   // 23:20 → 00:35, plus a minute for the last set
    }

    @Test("A backdated session filled in later falls back to 45 minutes")
    func backdated() {
        let w = workout(start: at(5, 18, 0), setTimes: [at(10, 8, 0), at(10, 8, 5)])
        let interval = w.sessionInterval(now: at(10, 8, 10), calendar: calendar)
        #expect(interval.start == at(5, 18, 0) && interval.duration == 45 * 60)
    }

    @Test("Today's session with no set times ends now")
    func todayFallback() {
        let w = workout(start: at(10, 7, 0), setTimes: [])
        #expect(w.sessionInterval(now: at(10, 7, 50), calendar: calendar).duration == 50 * 60)
    }
}

@Suite("Watch complication totals")
struct WatchComplicationTotalsTests {

    @Test("Totals count this week's completed working sets only")
    func totals() {
        func payload(week: Int, _ sets: [WorkoutPayload.Set], cardio: Bool = false) -> WorkoutPayload {
            WorkoutPayload(blockNumber: 1, weekNumber: week, sessionName: "S\(week)", dayType: .lift, date: .now,
                           exercises: [.init(name: "Lift", isCompound: true, isCardio: cardio, prescribedSets: 3,
                                             repRange: "5", rpeTarget: "8", prescriptionNotes: "", sets: sets)])
        }
        let workouts = [
            payload(week: 2, [.init(weight: 95, reps: 5, rpe: nil, completed: true, isWarmup: true),
                              .init(weight: 185, reps: 5, rpe: 8, completed: true),
                              .init(weight: 185, reps: 5, rpe: nil, completed: false)]),
            payload(week: 2, [.init(weight: 0, reps: 0, rpe: nil, completed: true, durationSeconds: 600)], cardio: true),
            payload(week: 3, [.init(weight: 200, reps: 3, rpe: 9, completed: true)]),
        ]
        let t = WidgetSnapshot.weekTotals(workouts, week: 2)
        #expect(t.sets == 1 && t.reps == 5 && t.volume == 925)
    }
}
