import Testing
@testable import TonnageCore

@Suite("Coach profile intake")
struct CoachProfileIntakeTests {

    @Test("coachingClause folds in the new intake when set")
    func clauseIncludesIntake() {
        let p = CoachProfile(
            name: "Test",
            startingPoint: .skinnyFat,
            priorityFocuses: [.arms, .shoulders],
            daysPerWeek: 4,
            environment: .homeDumbbells
        )
        let c = p.coachingClause
        #expect(c.contains("skinny-fat"))
        #expect(c.contains("Arms"))
        #expect(c.contains("Shoulders"))
        #expect(c.contains("4 training days"))
        #expect(c.contains("dumbbells"))
    }

    @Test("coachingClause omits starting point when unsure, still names equipment")
    func clauseHandlesUnsure() {
        let p = CoachProfile(name: "Test")   // defaults: unsure, no focuses, fullGym
        let c = p.coachingClause
        #expect(!c.contains("Starting point:"))
        #expect(c.contains("gym"))
    }

    @Test("Every starting point has a definition and a nutrition direction")
    func startingPointsAreComplete() {
        for sp in StartingPoint.allCases {
            #expect(!sp.label.isEmpty)
            #expect(!sp.definition.isEmpty)
            #expect(!sp.coachPhrase.isEmpty)
            #expect(!sp.nutritionDirection.isEmpty)
        }
    }

    @Test("Starting points map to the expected nutrition direction (mirrors Fuel's Goal)")
    func nutritionMapping() {
        #expect(StartingPoint.skinny.nutritionDirection.contains("bulk"))
        #expect(StartingPoint.skinnyFat.nutritionDirection.contains("recomp"))
        #expect(StartingPoint.overweight.nutritionDirection.contains("cut"))
        #expect(StartingPoint.muscularSoft.nutritionDirection.contains("cut"))
        #expect(StartingPoint.inShape.nutritionDirection.contains("maintain"))
    }
}
