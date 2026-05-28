import Testing
@testable import TonnageCore

@Suite("Live session stats")
struct StatsTests {

    /// Builds a workout: bench 3 sets (2 completed), curl 1 completed set.
    private func makeWorkout() -> LoggedWorkout {
        let bench = LoggedExercise(name: "Bench", isCompound: true, sortOrder: 0)
        bench.sets = [
            LoggedSet(weight: 135, reps: 6, rpe: 7, completed: true, sortOrder: 0),
            LoggedSet(weight: 135, reps: 5, rpe: 8, completed: true, sortOrder: 1),
            LoggedSet(weight: 135, reps: 0, rpe: nil, completed: false, sortOrder: 2) // not done
        ]
        let curl = LoggedExercise(name: "Curl", sortOrder: 1)
        curl.sets = [LoggedSet(weight: 30, reps: 12, rpe: 9, completed: true, sortOrder: 0)]

        let workout = LoggedWorkout(weekNumber: 2, dayType: .lift, sessionName: "Upper A")
        workout.exercises = [bench, curl]
        return workout
    }

    @Test("Only completed sets count toward stats")
    func completedOnly() {
        let w = makeWorkout()
        #expect(w.completedSetCount == 3)
        #expect(w.totalReps == 6 + 5 + 12)
        // Volume: 135*6 + 135*5 + 30*12 = 810 + 675 + 360 = 1845
        #expect(w.totalVolume == 1845)
    }

    @Test("Top set is heaviest completed by weight then reps")
    func topSet() {
        let bench = LoggedExercise(name: "Bench", sortOrder: 0)
        bench.sets = [
            LoggedSet(weight: 135, reps: 8, completed: true, sortOrder: 0),
            LoggedSet(weight: 155, reps: 5, completed: true, sortOrder: 1),
            LoggedSet(weight: 155, reps: 6, completed: false, sortOrder: 2) // heavier reps but not done
        ]
        #expect(bench.topSet?.weight == 155)
        #expect(bench.topSet?.reps == 5)
    }

    @Test("hasContent gates empty-workout pruning")
    func hasContent() {
        let empty = LoggedWorkout(weekNumber: 1, dayType: .lift, sessionName: "Upper A")
        let ex = LoggedExercise(name: "Bench", sortOrder: 0)
        ex.sets = [LoggedSet(weight: 135, reps: 0, completed: false, sortOrder: 0)]
        empty.exercises = [ex]
        #expect(empty.hasContent == false)

        ex.sets?[0].completed = true
        #expect(empty.hasContent == true)
    }
}

@Suite("Block 01 seed")
struct SeedTests {
    @Test("Seed builds the four-session block with the right exercise counts")
    func seededSessions() {
        let sessions = SeedProgram.makeSessions()
        #expect(sessions.map(\.name) == ["Upper A", "Lower A", "Upper B", "Lower B"])
        #expect(sessions.map { ($0.exercises ?? []).count } == [7, 6, 7, 6])
        // Compounds are tagged.
        let benchPress = sessions[0].orderedExercises.first
        #expect(benchPress?.name == "Barbell Bench Press")
        #expect(benchPress?.isCompound == true)
    }
}
