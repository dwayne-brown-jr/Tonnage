import Testing
@testable import TonnageCore

@Suite("Exercise metric inference")
struct ExerciseLibraryTests {

    @Test("Strength movements log weight / reps / RPE")
    func strengthMetrics() {
        #expect(ExerciseLibrary.metrics(for: "Barbell Bench Press", isCardio: false) == [.weight, .reps, .rpe])
        #expect(ExerciseLibrary.metrics(for: "Barbell Row", isCardio: false) == [.weight, .reps, .rpe])
    }

    @Test("Stair machines log flights + time", arguments: [
        "Stair Master (finisher)", "Stadium Stairs", "Step Mill"
    ])
    func stairs(name: String) {
        #expect(ExerciseLibrary.metrics(for: name, isCardio: true) == [.flights, .time])
    }

    @Test("Bike logs time + distance")
    func bike() {
        #expect(ExerciseLibrary.metrics(for: "Bike intervals (finisher)", isCardio: true) == [.time, .distance])
    }

    @Test("Walks / runs log distance + time", arguments: [
        "Weighted Vest Walk", "Treadmill Run", "Easy Jog"
    ])
    func walks(name: String) {
        #expect(ExerciseLibrary.metrics(for: name, isCardio: true) == [.distance, .time])
    }

    @Test("Unknown cardio falls back to time only")
    func genericCardio() {
        #expect(ExerciseLibrary.metrics(for: "Jump Rope", isCardio: true) == [.time])
    }

    @Test("Every seeded exercise has directions")
    func seedDirectionsCoverage() {
        for session in SeedProgram.makeSessions() {
            for exercise in (session.exercises ?? []) {
                #expect(ExerciseLibrary.directions(for: exercise.name) != nil,
                        "Missing directions for \(exercise.name)")
            }
        }
    }
}
