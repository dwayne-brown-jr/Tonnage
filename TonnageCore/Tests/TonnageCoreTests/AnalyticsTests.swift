import Testing
@testable import TonnageCore

@Suite("Analytics")
struct AnalyticsTests {

    /// Bench logged in W1 (135×5 top) and W2 (140×5 top); a curl in W1.
    private func sampleWorkouts() -> [LoggedWorkout] {
        func bench(week: Int, top: Double) -> LoggedWorkout {
            let ex = LoggedExercise(name: "Bench", isCompound: true, sortOrder: 0)
            ex.sets = [
                LoggedSet(weight: top - 10, reps: 5, completed: true, sortOrder: 0),
                LoggedSet(weight: top, reps: 5, completed: true, sortOrder: 1)
            ]
            let w = LoggedWorkout(weekNumber: week, dayType: .lift, sessionName: "Upper A")
            w.exercises = [ex]
            return w
        }
        let w1 = bench(week: 1, top: 135)
        let curl = LoggedExercise(name: "Curl", sortOrder: 1)
        curl.sets = [LoggedSet(weight: 30, reps: 12, completed: true, sortOrder: 0)]
        w1.exercises = (w1.exercises ?? []) + [curl]
        let w2 = bench(week: 2, top: 140)
        return [w2, w1] // intentionally out of order
    }

    @Test("Weekly volume sums completed sets, zero-filling empty weeks")
    func weeklyVolume() {
        let v = Analytics.weeklyVolume(sampleWorkouts())
        #expect(v.count == 5)
        // W1: 125*5 + 135*5 + 30*12 = 625 + 675 + 360 = 1660
        #expect(v[0] == .init(week: 1, volume: 1660))
        // W2: 130*5 + 140*5 = 650 + 700 = 1350
        #expect(v[1] == .init(week: 2, volume: 1350))
        #expect(v[2].volume == 0) // W3 empty
    }

    @Test("Top-set series tracks the heaviest set per week, ascending")
    func topSetSeries() {
        let series = Analytics.topSetSeries(for: "Bench", in: sampleWorkouts())
        #expect(series.map(\.week) == [1, 2])
        #expect(series.map(\.weight) == [135, 140])
    }

    @Test("Logged exercise names are distinct and only include completed work")
    func names() {
        #expect(Analytics.loggedExerciseNames(sampleWorkouts()) == ["Bench", "Curl"])
    }

    @Test("Block summary totals")
    func summary() {
        let w = sampleWorkouts()
        #expect(Analytics.totalSets(w) == 5)        // 2 bench W1 + 1 curl + 2 bench W2
        #expect(Analytics.sessionsLogged(w) == 2)
        #expect(Analytics.totalVolume(w) == 3010)   // 1660 + 1350
    }
}
