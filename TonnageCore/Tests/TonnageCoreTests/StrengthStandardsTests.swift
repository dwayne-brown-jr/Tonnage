import Testing
@testable import TonnageCore

@Suite("Strength standards")
struct StrengthStandardsTests {

    @Test("1.5× bodyweight bench rates advanced for men")
    func benchAdvanced() {
        let r = StrengthStandards.rating(lift: .bench, e1RM: 270, bodyweightLb: 180, sex: .male)
        #expect(r?.level == .advanced)
        #expect(abs((r?.bodyweightMultiple ?? 0) - 1.5) < 0.001)
        #expect(r?.nextLevelE1RM == 360)   // 2.0× for elite
    }

    @Test("Below the first threshold rates untrained, with progress toward beginner")
    func untrained() {
        let r = StrengthStandards.rating(lift: .squat, e1RM: 70, bodyweightLb: 200, sex: .male)
        #expect(r?.level == .untrained)
        #expect((r?.progressToNext ?? 0) > 0 && (r?.progressToNext ?? 1) < 1)
        #expect(r?.nextLevelE1RM == 150)   // 0.75× of 200
    }

    @Test("Elite caps progress at 1 with no next level")
    func elite() {
        let r = StrengthStandards.rating(lift: .deadlift, e1RM: 700, bodyweightLb: 200, sex: .male)
        #expect(r?.level == .elite)
        #expect(r?.progressToNext == 1)
        #expect(r?.nextLevelE1RM == nil)
    }

    @Test("Female thresholds scale, so the same multiple rates higher")
    func femaleScaling() {
        let male = StrengthStandards.rating(lift: .bench, e1RM: 200, bodyweightLb: 150, sex: .male)
        let female = StrengthStandards.rating(lift: .bench, e1RM: 200, bodyweightLb: 150, sex: .female)
        #expect(male?.level == .intermediate)        // 1.33× male = intermediate
        #expect(female?.level == .advanced)          // clears 1.5 × 0.7 = 1.05×… advanced band
        // Unspecified uses the male table (conservative).
        let unspecified = StrengthStandards.rating(lift: .bench, e1RM: 200, bodyweightLb: 150, sex: .unspecified)
        #expect(unspecified?.level == male?.level)
    }

    @Test("Missing bodyweight or e1RM yields no rating")
    func missingInputs() {
        #expect(StrengthStandards.rating(lift: .bench, e1RM: 0, bodyweightLb: 180, sex: .male) == nil)
        #expect(StrengthStandards.rating(lift: .bench, e1RM: 200, bodyweightLb: 0, sex: .male) == nil)
    }

    @Test("Best e1RM scan follows PR eligibility rules")
    @MainActor
    func bestE1RMScan() {
        let w = LoggedWorkout(blockNumber: 1, weekNumber: 1, dayType: .lift, sessionName: "Upper A")
        let bench = LoggedExercise(name: "Barbell Bench Press", isCompound: true, isCardio: false,
                                   sortOrder: 0, prescribedSets: 3, repRange: "5-7", rpeTarget: "8",
                                   prescriptionNotes: "")
        bench.sets = [
            LoggedSet(weight: 135, reps: 10, completed: true, isWarmup: true, sortOrder: 0),  // warm-up: excluded
            LoggedSet(weight: 225, reps: 5, completed: true, sortOrder: 1),                   // e1RM 262.5
            LoggedSet(weight: 185, reps: 20, completed: true, sortOrder: 2),                  // >12 reps: excluded
            LoggedSet(weight: 245, reps: 2, completed: false, sortOrder: 3),                  // incomplete: excluded
        ]
        w.exercises = [bench]
        let best = StrengthStandards.bestE1RMs(in: [w])
        #expect(abs((best[.bench] ?? 0) - 262.5) < 0.001)
        #expect(best[.squat] == nil)
    }
}
