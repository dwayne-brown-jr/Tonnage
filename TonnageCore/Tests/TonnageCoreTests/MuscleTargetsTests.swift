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

    @Test("Heat mirrors the per-group bar counts, scaled to the busiest group")
    func muscleHeat() {
        let volumes = [
            Analytics.MuscleVolume(group: .back, sets: 12),
            Analytics.MuscleVolume(group: .glutes, sets: 3),
            Analytics.MuscleVolume(group: nil, sets: 5)          // "Other" — no body region
        ]
        let heat = Analytics.muscleHeat(volumes)
        #expect(heat[.lats] == 1)
        #expect(heat[.upperBack] == 1)                          // every back muscle shares the bar
        #expect(heat[.lowerBack] == 1)
        #expect(heat[.glutes] == 0.25)
        #expect(heat[.chest] == nil)
        #expect(heat.values.allSatisfy { $0 <= 1 })
    }

    @Test("A light week is scaled against the minimum effective volume, not maxed out")
    func lightWeekNotMaxed() {
        let heat = Analytics.muscleHeat([Analytics.MuscleVolume(group: .chest, sets: 2)])
        #expect(heat[.chest] == 2.0 / Double(Analytics.weeklySetsMEV))
    }
}
