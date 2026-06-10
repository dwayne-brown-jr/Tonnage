import Testing
@testable import TonnageCore

@Suite("Exercise name canonicalization")
struct ExerciseCanonicalizerTests {

    @Test("Word-order and dumbbell/DB variants resolve to one canonical name")
    func variantsUnify() {
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Dumbbell Incline Press") == "Incline DB Press")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "incline dumbbell press") == "Incline DB Press")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Bench Press Barbell") == "Barbell Bench Press")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "DB Bench Press") == "DB Bench Press")
    }

    @Test("Catalog names pass through exactly, including parenthetical notes")
    func exactAndParens() {
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Romanian Deadlift") == "Romanian Deadlift")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "incline db press (finisher)") == "Incline DB Press")
    }

    @Test("Common shorthand expands (RDL, OHP)")
    func shorthand() {
        #expect(ExerciseLibrary.canonicalDisplayName(for: "RDL") == "Romanian Deadlift")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "OHP") == "Overhead Press")
    }

    @Test("Hyphen, plural, and joined-word forms match")
    func looseForms() {
        #expect(ExerciseLibrary.canonicalDisplayName(for: "pushups") == "Push-up")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Pull Up") == "Pull-up")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "DB Lateral Raises") == "DB Lateral Raise")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Cable Lat Pull Down") == "Cable Lat Pulldown")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "stiff-legged deadlift") == "Stiff-Leg Deadlift")
    }

    @Test("Unknown / custom movements pass through untouched")
    func customUnchanged() {
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Sled Push") == "Sled Push")
        #expect(ExerciseLibrary.canonicalDisplayName(for: "  Zercher Carry  ") == "Zercher Carry")
        // Partial overlap with a known movement is NOT a match — conservative by design.
        #expect(ExerciseLibrary.canonicalDisplayName(for: "Shoulder Press") == "Shoulder Press")
    }

    @Test("Every library display name canonicalizes to itself")
    func libraryIsFixedPoint() {
        for names in ExerciseLibrary.exercisesByGroup.values {
            for name in names {
                #expect(ExerciseLibrary.canonicalDisplayName(for: name) == name)
            }
        }
    }
}
