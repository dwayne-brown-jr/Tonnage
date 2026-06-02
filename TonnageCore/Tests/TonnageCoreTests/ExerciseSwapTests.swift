import Testing
@testable import TonnageCore

@Suite("Exercise swap suggestions")
struct ExerciseSwapTests {

    @Test("Maps a movement to its muscle group")
    func groupLookup() {
        #expect(ExerciseLibrary.muscleGroup(for: "Barbell Back Squat") == .quads)
        #expect(ExerciseLibrary.muscleGroup(for: "Barbell Bench Press") == .chest)
        #expect(ExerciseLibrary.muscleGroup(for: "Chest-Supported Row") == .back)
        #expect(ExerciseLibrary.muscleGroup(for: "Made-up Lift") == nil)
    }

    @Test("Alternatives share the muscle group, exclude the original, and stay same-muscle")
    func alternatives() {
        let alts = ExerciseLibrary.alternatives(for: "Barbell Back Squat")
        #expect(!alts.isEmpty)
        // The friend's case: swapping back squat should offer no-bar-on-back options.
        #expect(alts.contains("Leg Press"))
        #expect(alts.contains("Front Squat"))
        // Never suggests the same movement back, and everything stays in the quads group.
        #expect(!alts.contains("Barbell Back Squat"))
        #expect(alts.allSatisfy { ExerciseLibrary.muscleGroup(for: $0) == .quads })
    }

    @Test("Unknown movements yield no suggestions (manual entry only)")
    func unknownYieldsNone() {
        #expect(ExerciseLibrary.alternatives(for: "Zercher Carry").isEmpty)
    }

    @Test("Compound flag is set for big lifts, not isolations")
    func compoundFlag() {
        #expect(ExerciseLibrary.isCompound("Barbell Bench Press"))
        #expect(ExerciseLibrary.isCompound("Leg Press"))
        #expect(!ExerciseLibrary.isCompound("DB Lateral Raise"))
        #expect(!ExerciseLibrary.isCompound("Leg Curl"))
    }

    @Test("Every suggestable movement has how-to directions")
    func suggestionsHaveDirections() {
        for (_, names) in ExerciseLibrary.exercisesByGroup {
            for name in names {
                #expect(ExerciseLibrary.directions(for: name) != nil, "no directions for \(name)")
            }
        }
    }
}
