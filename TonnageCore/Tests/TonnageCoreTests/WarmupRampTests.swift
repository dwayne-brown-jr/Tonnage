import Testing
@testable import TonnageCore

@Suite("Warm-up ramp")
struct WarmupRampTests {

    @Test("Classic 40/60/80 ramp toward a heavy working weight, rounded to 5 lb")
    func classicRamp() {
        let steps = WarmupRamp.steps(workingWeight: 225)
        #expect(steps == [
            .init(weight: 90, reps: 8),
            .init(weight: 135, reps: 5),
            .init(weight: 180, reps: 3),
        ])
    }

    @Test("Ramp weights always ascend and never reach the working weight")
    func ascendsBelowWorking() {
        for working in stride(from: 20.0, through: 500.0, by: 5) {
            let steps = WarmupRamp.steps(workingWeight: working)
            for (a, b) in zip(steps, steps.dropFirst()) { #expect(a.weight < b.weight) }
            for s in steps { #expect(s.weight < working && s.weight > 0) }
        }
    }

    @Test("Light working weight gets a single 50% primer")
    func lightWeight() {
        #expect(WarmupRamp.steps(workingWeight: 30) == [.init(weight: 15, reps: 8)])
    }

    @Test("Very light working weight needs no ramp")
    func veryLight() {
        #expect(WarmupRamp.steps(workingWeight: 15).isEmpty)
        #expect(WarmupRamp.steps(workingWeight: 0).isEmpty)
    }

    @Test("Rounding collisions are deduped, not duplicated")
    func dedupesRoundedSteps() {
        for working in stride(from: 50.0, through: 120.0, by: 2.5) {
            let steps = WarmupRamp.steps(workingWeight: working)
            let weights = steps.map(\.weight)
            #expect(weights == weights.sorted())
            #expect(Set(weights).count == weights.count)
        }
    }
}
