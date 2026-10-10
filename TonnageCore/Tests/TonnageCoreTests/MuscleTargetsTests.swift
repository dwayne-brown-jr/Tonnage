import Testing
@testable import TonnageCore

@Suite("Muscle targets + body map data")
struct MuscleTargetsTests {

    @Test("Every movement with directions also has muscle targets, and vice versa")
    func catalogsInSync() {
        let directions = Set(ExerciseLibrary.catalog.keys)
        let muscles = Set(ExerciseLibrary.muscleCatalog.keys)
        #expect(directions.subtracting(muscles).isEmpty, "missing targets: \(directions.subtracting(muscles).sorted())")
        #expect(muscles.subtracting(directions).isEmpty, "orphan targets: \(muscles.subtracting(directions).sorted())")
    }

    @Test("Every swap-list movement resolves to targets")
    func swapListCovered() {
        for name in ExerciseLibrary.exercisesByGroup.values.joined() {
            #expect(ExerciseLibrary.muscleTargets(for: name) != nil, "\(name)")
        }
    }

    @Test("A lifting movement's primary muscles include its swap group")
    func primaryMatchesGroup() {
        for (group, names) in ExerciseLibrary.exercisesByGroup where group != .cardio {
            for name in names {
                let t = ExerciseLibrary.muscleTargets(for: name)
                #expect(t?.primary.contains { $0.group == group } == true, "\(name) → \(group)")
            }
        }
    }

    @Test("No muscle is listed as both primary and secondary")
    func noOverlap() {
        for (name, t) in ExerciseLibrary.muscleCatalog {
            #expect(Set(t.primary).isDisjoint(with: t.secondary), "\(name)")
            #expect(!t.primary.isEmpty, "\(name)")
        }
    }

    @Test("Lookup ignores case and (…) suffixes")
    func lookupNormalizes() {
        #expect(ExerciseLibrary.muscleTargets(for: "BARBELL BENCH PRESS (top set)")?.primary == [.chest])
        #expect(ExerciseLibrary.muscleTargets(for: "Mystery Move") == nil)
    }

    @Test("Every muscle is drawn on the body map")
    func everyMuscleDrawn() {
        let drawn = Set((BodyGeometry.front + BodyGeometry.back).compactMap(\.muscle))
        #expect(drawn == Set(Muscle.allCases))
    }

    @Test("Muscle load credits primary 1, secondary ½, and skips cardio + unknowns")
    func muscleLoad() {
        let bench = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
        bench.sets = (0..<3).map { LoggedSet(weight: 185, reps: 5, completed: true, sortOrder: $0) }
        let mystery = LoggedExercise(name: "Mystery Move", sortOrder: 1)
        mystery.sets = [LoggedSet(weight: 50, reps: 10, completed: true, sortOrder: 0)]
        let bike = LoggedExercise(name: "Bike intervals", isCardio: true, sortOrder: 2)
        bike.sets = [LoggedSet(weight: 0, reps: 0, completed: true, sortOrder: 0)]
        let w = LoggedWorkout(weekNumber: 1, dayType: .lift, sessionName: "Upper")
        w.exercises = [bench, mystery, bike]

        let load = Analytics.muscleLoad([w])
        #expect(load[.chest] == 3)
        #expect(load[.frontDelts] == 1.5)
        #expect(load[.triceps] == 1.5)
        #expect(load[.quads] == nil)       // bike is cardio
        #expect(load.count == 3)
    }
}
