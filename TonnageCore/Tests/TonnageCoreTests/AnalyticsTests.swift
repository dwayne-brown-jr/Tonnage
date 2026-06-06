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

    // MARK: Sets per muscle

    /// Builds an exercise with `done` completed sets + `pending` incomplete sets.
    private func exercise(_ name: String, isCardio: Bool = false, done: Int, pending: Int = 0, order: Int) -> LoggedExercise {
        let ex = LoggedExercise(name: name, isCardio: isCardio, sortOrder: order)
        var sets: [LoggedSet] = (0..<done).map { LoggedSet(weight: 100, reps: 8, completed: true, sortOrder: $0) }
        sets += (0..<pending).map { LoggedSet(weight: 100, reps: 8, completed: false, sortOrder: done + $0) }
        ex.sets = sets
        return ex
    }

    @Test("Sets per muscle counts hard sets, maps by name, excludes cardio/incomplete, buckets unknowns")
    func setsPerMuscle() {
        let w1 = LoggedWorkout(weekNumber: 1, dayType: .lift, sessionName: "Full Body")
        w1.exercises = [
            exercise("Barbell Bench Press", done: 3, pending: 1, order: 0),  // chest 3 (pending ignored)
            exercise("Barbell Back Squat", done: 2, order: 1),               // quads 2
            exercise("Mystery Move", done: 2, order: 2),                     // Other 2 (unknown name)
            exercise("Bike intervals", isCardio: true, done: 5, order: 3)    // excluded (cardio)
        ]
        let rest = LoggedWorkout(weekNumber: 1, dayType: .fullRest, sessionName: "Rest Day")

        let result = Analytics.setsPerMuscle([w1, rest])
        // Ordered by muscle enum (chest before quads), Other last; cardio absent.
        #expect(result.map(\.label) == ["Chest", "Quads", "Other"])
        #expect(result.map(\.sets) == [3, 2, 2])
        #expect(!result.contains { $0.label == "Cardio" })
    }

    @Test("Warm-up sets are excluded from volume, hard-set counts, top set, and per-muscle")
    func warmupsExcluded() {
        let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
        ex.sets = [
            LoggedSet(weight: 95, reps: 5, completed: true, isWarmup: true, sortOrder: 0),    // warm-up (heaviest by weight? no)
            LoggedSet(weight: 225, reps: 5, completed: true, isWarmup: true, sortOrder: 1),   // heavy warm-up — must NOT be top set
            LoggedSet(weight: 185, reps: 5, completed: true, sortOrder: 2),                    // working
            LoggedSet(weight: 185, reps: 5, completed: true, sortOrder: 3)                     // working
        ]
        let w = LoggedWorkout(weekNumber: 1, dayType: .lift, sessionName: "Upper")
        w.exercises = [ex]

        #expect(ex.completedSetCount == 2)                                   // only working sets
        #expect(ex.topSet?.weight == 185)                                    // not the 225 warm-up
        #expect(w.totalVolume == 185 * 5 * 2)                                // warm-ups contribute 0
        #expect(Analytics.setsPerMuscle([w]).first?.sets == 2)               // chest = 2 hard sets
        #expect(PersonalRecords.recentPRs(in: [w]).isEmpty)                  // warm-ups don't establish/beat PRs
    }

    @Test("Latest logged week ignores empty + rest workouts")
    func latestLoggedWeek() {
        let w1 = LoggedWorkout(weekNumber: 1, dayType: .lift, sessionName: "A")
        w1.exercises = [exercise("Barbell Bench Press", done: 2, order: 0)]
        let w3empty = LoggedWorkout(weekNumber: 3, dayType: .lift, sessionName: "A")   // no sets
        let w4rest = LoggedWorkout(weekNumber: 4, dayType: .fullRest, sessionName: "Rest Day")

        #expect(Analytics.latestLoggedWeek([w1, w3empty, w4rest]) == 1)
        #expect(Analytics.latestLoggedWeek([w3empty, w4rest]) == nil)
    }
}
