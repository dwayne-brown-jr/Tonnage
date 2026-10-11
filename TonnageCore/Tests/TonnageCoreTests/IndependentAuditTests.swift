import Testing
import Foundation
@testable import TonnageCore

// Independent audit, October 2026.
//
// Two suites:
//  • "Audit: verified correct" — known-answer checks on the core math. These should pass today.
//  • "Audit: bugs to fix"      — each test describes the CORRECT behavior for an edge case the
//                                 current code gets wrong. They fail until the bug is fixed, then
//                                 stay as regression tests.
//
// Run: swift test --package-path TonnageCore

// MARK: - Helpers

private func logSet(_ weight: Double, _ reps: Int, rpe: Double? = nil, done: Bool = true,
                 warmup: Bool = false, order: Int) -> LoggedSet {
    LoggedSet(weight: weight, reps: reps, rpe: rpe, completed: done, isWarmup: warmup, sortOrder: order)
}

private func exercise(_ name: String, compound: Bool = true, sets: [LoggedSet], order: Int = 0) -> LoggedExercise {
    let ex = LoggedExercise(name: name, isCompound: compound, sortOrder: order)
    ex.sets = sets
    return ex
}

private func liftDay(week: Int, _ exercises: [LoggedExercise]) -> LoggedWorkout {
    let w = LoggedWorkout(date: Date(timeIntervalSince1970: 1_700_000_000), weekNumber: week,
                          dayType: .lift, sessionName: "Audit")
    w.exercises = exercises
    return w
}

private let blockPlanJSON = """
{
  "blockNumber": 2,
  "theme": "Strength peak",
  "summary": "Keeps main lifts, peaks bench in W4.",
  "sessions": [
    {
      "name": "Upper A",
      "subtitle": "Push focus",
      "exercises": [
        {
          "name": "Barbell Bench Press",
          "prescribedSets": 4,
          "repRange": "3-5",
          "rpeTarget": "8",
          "notes": "",
          "isCompound": true,
          "isCardio": false,
          "rationale": "Top set climbed in Block 1.",
          "change": {"type":"kept"}
        }
      ]
    }
  ]
}
"""

// MARK: - Verified correct

@Suite("Audit: verified correct")
struct AuditVerifiedCorrectTests {

    @Test("Tonnage = weight × reps over completed working sets; warm-ups and unfinished sets excluded")
    func tonnageExcludesWarmupsAndUnfinished() {
        let bench = exercise("Barbell Bench Press", sets: [
            logSet(95, 5, warmup: true, order: 0),   // warm-up: excluded
            logSet(135, 5, order: 1),
            logSet(135, 5, order: 2),
            logSet(135, 5, order: 3),
            logSet(155, 5, done: false, order: 4)    // not completed: excluded
        ])
        let w = liftDay(week: 1, [bench])
        #expect(w.totalVolume == 2025)            // 3 × 135 × 5
        #expect(w.completedSetCount == 3)
    }

    @Test("Tonnage sums across exercises")
    func tonnageAcrossExercises() {
        let bench = exercise("Barbell Bench Press", sets: (0..<3).map { logSet(185, 5, order: $0) })
        let row = exercise("Barbell Row", sets: (0..<3).map { logSet(135, 8, order: $0) }, order: 1)
        #expect(liftDay(week: 1, [bench, row]).totalVolume == 6015)   // 2775 + 3240
    }

    @Test("Weekly volume zero-fills weeks with no training")
    func weeklyVolumeZeroFills() {
        let w = liftDay(week: 2, [exercise("Back Squat", sets: [logSet(225, 3, order: 0)])])
        #expect(Analytics.weeklyVolume([w]).map(\.volume) == [0, 675, 0, 0, 0])
    }

    @Test("Epley estimated 1RM")
    func epley() {
        #expect(PersonalRecords.epley(weight: 225, reps: 5) == 262.5)
        #expect(abs(PersonalRecords.epley(weight: 100, reps: 10) - 133.333) < 0.01)
    }

    @Test("Top set = heaviest completed working set, ties broken by reps")
    func topSetPicksHeaviest() {
        let ex = exercise("Overhead Press", sets: [
            logSet(135, 8, order: 0), logSet(155, 3, order: 1), logSet(155, 5, order: 2),
            logSet(185, 1, warmup: true, order: 3)   // a heavier warm-up must not count
        ])
        #expect(ex.topSet?.weight == 155)
        #expect(ex.topSet?.reps == 5)
    }

    @Test("RPE boundaries: ≤7 add, ≤8.5 add, above 8.5 hold and chase a rep")
    func rpeBoundaries() {
        func call(_ rpe: Double) -> CoachsCall {
            CoachEngine.call(week: 3, last: LastTopSet(weight: 200, reps: 5, rpe: rpe), repRange: "5-7", isCardio: false)
        }
        #expect(call(7.0).suggestedWeight == 205 && call(7.0).emphasis == .progress)
        #expect(call(8.5).suggestedWeight == 205 && call(8.5).emphasis == .progress)
        #expect(call(9.0).suggestedWeight == 200 && call(9.0).suggestedReps == 6 && call(9.0).emphasis == .hold)
    }

    @Test("Week 5 deload = 60% rounded to 5 lb")
    func deloadSixtyPercent() {
        let call = CoachEngine.call(week: 5, last: LastTopSet(weight: 225, reps: 5, rpe: 8), repRange: "5-7", isCardio: false)
        #expect(call.suggestedWeight == 135)
        #expect(call.emphasis == .deload)
    }

    @Test("Layoff tiers switch at 14, 21, 42 and 84 days")
    func layoffTiers() {
        let m = LayoffEngine.loadMultiplier(daysSinceLastLift:)
        #expect(m(13) == 1.0 && m(14) == 0.9 && m(20) == 0.9)
        #expect(m(21) == 0.8 && m(41) == 0.8)
        #expect(m(42) == 0.7 && m(83) == 0.7)
        #expect(m(84) == 0.6 && m(400) == 0.6)
    }

    @Test("After 30 days off, a 225 top set comes back at 180 (80%)")
    func layoffScalesLoad() {
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 225, reps: 5, rpe: 8), repRange: "5-7",
                                    isCardio: false, layoff: Layoff(days: 30, loadMultiplier: 0.8))
        #expect(call.suggestedWeight == 180)
        #expect(call.emphasis == .deload)
    }

    @Test("Layoff plus a forced deload never suggests more than 60%")
    func layoffWithDeloadCapsAtSixty() {
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 225, reps: 5, rpe: 8), repRange: "5-7",
                                    isCardio: false, forceDeload: true, layoff: Layoff(days: 20, loadMultiplier: 0.9))
        #expect(call.suggestedWeight == 135)
    }

    @Test("Plate math for common loads")
    func plateMathCommonLoads() {
        let l315 = PlateMath.loadout(target: 315, bar: 45)
        #expect(l315.perSide == [.init(plate: 45, perSide: 3)] && l315.isExact)
        let l185 = PlateMath.loadout(target: 185, bar: 45)
        #expect(l185.perSide == [.init(plate: 45, perSide: 1), .init(plate: 25, perSide: 1)] && l185.isExact)
    }

    @Test("Warm-up ramp for a 225 working set")
    func warmupFor225() {
        #expect(WarmupRamp.steps(workingWeight: 225) == [.init(weight: 90, reps: 8), .init(weight: 135, reps: 5), .init(weight: 180, reps: 3)])
    }

    @Test("Next-set cue: easy compound +10, moderately easy +5, low readiness never adds")
    func nextSetCues() {
        #expect(CoachEngine.nextSetCue(loggedRPE: 5, targetRPE: 8, isCompound: true).weightDeltaLb == 10)
        #expect(CoachEngine.nextSetCue(loggedRPE: 6, targetRPE: 8, isCompound: true).weightDeltaLb == 5)
        #expect(CoachEngine.nextSetCue(loggedRPE: 5, targetRPE: 8, isCompound: true, holdProgression: true).weightDeltaLb == 0)
    }
}

// MARK: - Bugs to fix (fail until fixed)

@Suite("Audit: bugs to fix")
struct AuditBugsToFixTests {

    @Test("Plate math can't call a weight below the empty bar 'exact'")
    func plateMathBelowBar() {
        // A 65 lb bench deloads to 40 lb. On a 45 lb bar that's impossible, but today the
        // calculator reports achievable 45 with remainder 0, i.e. "exact".
        let l = PlateMath.loadout(target: 40, bar: 45)
        #expect(!l.isExact)
    }

    @Test("Bodyweight exercises aren't told to add 5 lb")
    func bodyweightNoAddedLoad() {
        // Push-ups / pull-ups / dips are logged at 0 lb. An easy week currently returns
        // "add 5 lb" with a suggested weight of 5.
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 0, reps: 12, rpe: 7), repRange: "8-12", isCardio: false)
        #expect(call.suggestedWeight == nil || call.suggestedWeight == 0)
    }

    @Test("A hard set at the top of the rep range doesn't push reps past the range")
    func repsStayInRange() {
        // 225 × 7 at RPE 9 on a 5–7 range: today the call says "chase +1 rep" → 8 reps,
        // and keeps climbing every hard week, so the prescription drifts out of its range.
        let call = CoachEngine.call(week: 4, last: LastTopSet(weight: 225, reps: 7, rpe: 9), repRange: "5-7", isCardio: false)
        #expect((call.suggestedReps ?? 0) <= 7)
    }

    @Test("An impossible RPE target (above 10) is clamped before cueing load")
    func rpeTargetClamped() {
        // An AI-written block plan can carry rpeTarget "12". Logged RPE 8 then reads as
        // 4 RPE easier than planned and cues +10 lb, set after set.
        let target = CoachEngine.targetRPE(forSetIndex: 0, in: "12")
        let cue = CoachEngine.nextSetCue(loggedRPE: 8, targetRPE: target, isCompound: true)
        #expect(cue.weightDeltaLb <= 5)
    }

    @Test("Swap suggestions survive the model wrapping JSON in a code fence")
    func swapParserHandlesCodeFence() {
        let response = "Here are some swaps:\n<swaps>\n```json\n[\"Dumbbell Bench Press\", \"Push-up\"]\n```\n</swaps>"
        #expect(CoachSwapSuggester.parse(response) == ["Dumbbell Bench Press", "Push-up"])
    }

    @Test("Block plan survives the model wrapping JSON in a code fence")
    func blockPlanParserHandlesCodeFence() {
        let response = "Here's the plan.\n<block_plan>\n```json\n\(blockPlanJSON)\n```\n</block_plan>"
        #expect(CoachBlockPlanner.parse(response: response)?.blockNumber == 2)
    }
}
