import Testing
@testable import TonnageCore

@Suite("Coach's Call progression")
struct CoachEngineTests {

    @Test("Week 1 is always a ramp, never prescribes added load")
    func week1Ramp() {
        let call = CoachEngine.call(week: 1, last: LastTopSet(weight: 185, reps: 6, rpe: 8), repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .ramp)
        // Ramp keeps last week's working weight, doesn't add.
        #expect(call.suggestedWeight == 185)
    }

    @Test("Week 1 with no history seeds reps from the low end of the range")
    func week1NoHistory() {
        let call = CoachEngine.call(week: 1, last: nil, repRange: "8-10", isCardio: false)
        #expect(call.emphasis == .ramp)
        #expect(call.suggestedWeight == nil)
        #expect(call.suggestedReps == 8)
    }

    @Test("RPE ≤7 last week → add 5 lb")
    func easyAddsLoad() {
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 135, reps: 6, rpe: 7), repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .progress)
        #expect(call.suggestedWeight == 140)
        #expect(call.suggestedReps == 6)
    }

    @Test("RPE 8–8.5 → add 5 lb, hold reps")
    func onTargetAddsLoad() {
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 200, reps: 5, rpe: 8), repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .progress)
        #expect(call.suggestedWeight == 205)
    }

    @Test("RPE 9+ → hold weight, chase +1 rep")
    func toughHoldsAndAddsRep() {
        let call = CoachEngine.call(week: 4, last: LastTopSet(weight: 225, reps: 5, rpe: 9), repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .hold)
        #expect(call.suggestedWeight == 225)
        #expect(call.suggestedReps == 6)
    }

    @Test("Week 5 deloads to ~60%, rounded to 5 lb")
    func week5Deload() {
        let call = CoachEngine.call(week: 5, last: LastTopSet(weight: 200, reps: 6, rpe: 8), repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .deload)
        #expect(call.suggestedWeight == 120) // 200 * 0.6
    }

    @Test("Cardio gets a neutral, no-numbers call")
    func cardioNeutral() {
        let call = CoachEngine.call(week: 3, last: nil, repRange: "10 min", isCardio: true)
        #expect(call.emphasis == .neutral)
        #expect(call.suggestedWeight == nil)
    }

    @Test("Missing data on a progression week is honest about it")
    func noLogLastWeek() {
        let call = CoachEngine.call(week: 3, last: nil, repRange: "10-12", isCardio: false)
        #expect(call.emphasis == .neutral)
        #expect(call.suggestedReps == 10)
    }

    @Test("Rep-range parsing handles ranges, per-leg, and durations", arguments: [
        ("5-7", 5), ("8-10", 8), ("10/leg", 10), ("10/side", 10), ("15", 15), ("10 min", 10), ("", 0)
    ])
    func lowRepParsing(input: String, expected: Int) {
        #expect(CoachEngine.lowRep(of: input) == expected)
    }

    // MARK: Set-to-set cue

    @Test("Per-set RPE targets parse the ramp and clamp to the last value")
    func rpeTargetParsing() {
        #expect(CoachEngine.rpeTargets("7→8→8") == [7, 8, 8])
        #expect(CoachEngine.rpeTargets("8") == [8])
        #expect(CoachEngine.rpeTargets("easy").isEmpty)
        #expect(CoachEngine.targetRPE(forSetIndex: 0, in: "7→8→8") == 7)
        #expect(CoachEngine.targetRPE(forSetIndex: 5, in: "7→8→8") == 8) // clamped to last
        #expect(CoachEngine.targetRPE(forSetIndex: 2, in: "easy") == nil)
    }

    @Test("Set came in well under target → add load (10 lb only for compounds)")
    func cueAddsWhenEasy() {
        let compound = CoachEngine.nextSetCue(loggedRPE: 5.5, targetRPE: 8, isCompound: true)
        #expect(compound.direction == .up)
        #expect(compound.weightDeltaLb == 10)

        let isolation = CoachEngine.nextSetCue(loggedRPE: 5.5, targetRPE: 8, isCompound: false)
        #expect(isolation.direction == .up)
        #expect(isolation.weightDeltaLb == 5) // capped — no 10 lb jump on isolations

        let slightlyEasy = CoachEngine.nextSetCue(loggedRPE: 7, targetRPE: 8, isCompound: true)
        #expect(slightlyEasy.weightDeltaLb == 5)
    }

    @Test("On-target effort holds the weight")
    func cueHoldsOnTarget() {
        let cue = CoachEngine.nextSetCue(loggedRPE: 8, targetRPE: 8, isCompound: true)
        #expect(cue.direction == .hold)
        #expect(cue.weightDeltaLb == 0)
    }

    @Test("Reps-left labels: 10→0 (all out), 8→2, 6→4+ (easy)")
    func repsLeftLabels() {
        #expect(CoachEngine.repsLeftLabel(fromRPE: 10) == "0")
        #expect(CoachEngine.repsLeftLabel(fromRPE: 9) == "1")
        #expect(CoachEngine.repsLeftLabel(fromRPE: 8) == "2")
        #expect(CoachEngine.repsLeftLabel(fromRPE: 7) == "3")
        #expect(CoachEngine.repsLeftLabel(fromRPE: 6) == "4+")
        #expect(CoachEngine.repsLeftLabel(fromRPE: 5) == "4+") // clamped easy end
    }

    @Test("Reps-left target converts the RPE ramp; non-numeric passes through")
    func repsLeftTargets() {
        #expect(CoachEngine.repsLeftTarget(from: "7→8→8") == "3→2→2")
        #expect(CoachEngine.repsLeftTarget(from: "8") == "2")
        #expect(CoachEngine.repsLeftTarget(from: "easy") == "easy")
    }

    @Test("Max-effort set suggests backing off; tough-but-not-max holds")
    func cueBacksOffWhenMaxed() {
        let maxed = CoachEngine.nextSetCue(loggedRPE: 9.5, targetRPE: 8, isCompound: true)
        #expect(maxed.direction == .down)
        #expect(maxed.weightDeltaLb == -5)

        let tough = CoachEngine.nextSetCue(loggedRPE: 9, targetRPE: 8, isCompound: true)
        #expect(tough.direction == .hold)
        #expect(tough.weightDeltaLb == 0)
    }
}

@Suite("Early deload override")
struct EarlyDeloadTests {
    @Test("forceDeload routes any mid-block week to deload coaching")
    func forcedMidBlock() {
        let last = LastTopSet(weight: 225, reps: 5, rpe: 8)
        let call = CoachEngine.call(week: 3, last: last, repRange: "5-7", isCardio: false, forceDeload: true)
        #expect(call.emphasis == .deload)
        #expect(call.suggestedWeight == 135)   // 60% of 225, rounded to 5
    }

    @Test("forceDeload beats a hold from low readiness")
    func beatsReadinessHold() {
        let last = LastTopSet(weight: 200, reps: 6, rpe: 7)
        let call = CoachEngine.call(week: 2, last: last, repRange: "5-7", isCardio: false,
                                    holdProgression: true, forceDeload: true)
        #expect(call.emphasis == .deload)
    }

    @Test("No override → weeks behave exactly as before")
    func defaultUnchanged() {
        let last = LastTopSet(weight: 225, reps: 5, rpe: 7)
        let call = CoachEngine.call(week: 3, last: last, repRange: "5-7", isCardio: false)
        #expect(call.emphasis == .progress)
    }

    @Test("Cardio ignores the override")
    func cardioUnaffected() {
        let call = CoachEngine.call(week: 3, last: nil, repRange: "15 min", isCardio: true, forceDeload: true)
        #expect(call.emphasis == .neutral)
    }
}
