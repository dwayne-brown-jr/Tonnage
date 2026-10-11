import Testing
import Foundation
@testable import TonnageCore

// Regression tests for the October 2026 audit's calculation fixes (items 8, 13–15 and
// the "findings only" list). The audit's own failing tests live in IndependentAuditTests.

@Suite("Load profile")
struct LoadProfileTests {

    @Test("Equipment is inferred from the name, dumbbell and machine words winning over lift names")
    func equipmentInference() {
        #expect(ExerciseLibrary.equipment(for: "Barbell Bench Press") == .barbell)
        #expect(ExerciseLibrary.equipment(for: "Barbell Back Squat") == .barbell)
        #expect(ExerciseLibrary.equipment(for: "Romanian Deadlift") == .barbell)
        #expect(ExerciseLibrary.equipment(for: "DB Lateral Raise") == .dumbbell)
        #expect(ExerciseLibrary.equipment(for: "Incline DB Press") == .dumbbell)
        #expect(ExerciseLibrary.equipment(for: "Dumbbell Bench Press") == .dumbbell)
        #expect(ExerciseLibrary.equipment(for: "Cable Lat Pulldown") == .machine)
        #expect(ExerciseLibrary.equipment(for: "Smith Machine Squat") == .machine)
        #expect(ExerciseLibrary.equipment(for: "Push-up") == .bodyweight)
        #expect(ExerciseLibrary.equipment(for: "Dips") == .bodyweight)
        #expect(ExerciseLibrary.equipment(for: "Seated Shoulder Press") == .other)
    }

    @Test("Jumps: next dumbbell, 2.5 lb for isolation, 5 lb for compounds")
    func increments() {
        let lateral = LoadProfile.forExercise(named: "DB Lateral Raise", isCompound: false)
        #expect(lateral.nextWeight(after: 15) == 17.5)
        #expect(lateral.nextWeight(after: 40) == 45)
        let pushdown = LoadProfile.forExercise(named: "Cable Triceps Pushdown", isCompound: false)
        #expect(pushdown.nextWeight(after: 50) == 52.5)
        let bench = LoadProfile.forExercise(named: "Barbell Bench Press", isCompound: true)
        #expect(bench.nextWeight(after: 225) == 230)
        #expect(LoadProfile.standard.nextWeight(after: 15) == 20)   // legacy behaviour kept
    }

    @Test("An easy week on a small lift adds 2.5, not 5")
    func smallLiftProgression() {
        let call = CoachEngine.call(week: 3, last: LastTopSet(weight: 15, reps: 12, rpe: 7), repRange: "12-15",
                                    isCardio: false, load: .forExercise(named: "DB Lateral Raise", isCompound: false))
        #expect(call.suggestedWeight == 17.5)
        #expect(call.headline.contains("add 2.5 lb"))
    }

    @Test("Barbell deloads and layoffs never go below the empty bar")
    func barbellFloor() {
        let bench = LoadProfile.forExercise(named: "Barbell Bench Press", isCompound: true)
        let deload = CoachEngine.call(week: 5, last: LastTopSet(weight: 65, reps: 8, rpe: 8), repRange: "6-8",
                                      isCardio: false, load: bench)
        #expect(deload.suggestedWeight == 45)
        let early = CoachEngine.call(week: 3, last: LastTopSet(weight: 65, reps: 8, rpe: 8), repRange: "6-8",
                                     isCardio: false, load: bench, forceDeload: true)
        #expect(early.suggestedWeight == 45)
        let layoff = CoachEngine.call(week: 3, last: LastTopSet(weight: 50, reps: 8, rpe: 8), repRange: "6-8",
                                      isCardio: false, load: bench, layoff: Layoff(days: 100, loadMultiplier: 0.6))
        #expect(layoff.suggestedWeight == 45)
    }
}

@Suite("Double progression")
struct DoubleProgressionTests {

    private func call(_ w: Double, _ reps: Int, rpe: Double?, range: String = "5-7", week: Int = 3) -> CoachsCall {
        CoachEngine.call(week: week, last: LastTopSet(weight: w, reps: reps, rpe: rpe), repRange: range, isCardio: false)
    }

    @Test("Rep range top is parsed from common formats")
    func highRepParsing() {
        #expect(CoachEngine.highRep(of: "5-7") == 7)
        #expect(CoachEngine.highRep(of: "8–12") == 12)
        #expect(CoachEngine.highRep(of: "3 to 5") == 5)
        #expect(CoachEngine.highRep(of: "15") == 15)
        #expect(CoachEngine.highRep(of: "10/leg") == 10)
        #expect(CoachEngine.highRep(of: "easy") == nil)
    }

    @Test("Hitting the top of the range adds load and resets to the bottom, whatever the RPE")
    func topOfRangeAddsLoad() {
        for rpe in [6.0, 8.0, 9.0, 10.0] {
            let c = call(225, 7, rpe: rpe)
            #expect(c.suggestedWeight == 230)
            #expect(c.suggestedReps == 5)
        }
        let noRPE = call(225, 7, rpe: nil)
        #expect(noRPE.suggestedWeight == 230 && noRPE.suggestedReps == 5)
    }

    @Test("A hard set below the top chases a rep, capped at the top")
    func hardSetChasesRep() {
        let c = call(225, 6, rpe: 9.5)
        #expect(c.suggestedWeight == 225 && c.suggestedReps == 7)
    }

    @Test("Reps that already drifted past the range come back inside it")
    func driftedRepsReturn() {
        let c = call(225, 9, rpe: 9)
        #expect(c.suggestedReps == 5)
        let ramp = call(225, 9, rpe: 8, week: 1)
        #expect(ramp.suggestedReps == 7)
    }
}

@Suite("Bodyweight progression")
struct BodyweightProgressionTests {

    @Test("Easy bodyweight sets add a rep, not load")
    func addsRep() {
        let c = CoachEngine.call(week: 3, last: LastTopSet(weight: 0, reps: 10, rpe: 7), repRange: "8-12", isCardio: false)
        #expect(c.suggestedWeight == 0)
        #expect(c.suggestedReps == 11)
    }

    @Test("At the top of the range the call suggests load or a harder variation")
    func topOfRange() {
        let c = CoachEngine.call(week: 3, last: LastTopSet(weight: 0, reps: 12, rpe: 9), repRange: "8-12", isCardio: false)
        #expect(c.suggestedWeight == 0)
        #expect(c.suggestedReps == 12)
        #expect(c.headline.contains("harder variation"))
    }

    @Test("A bodyweight deload trims reps")
    func deloadTrimsReps() {
        let c = CoachEngine.call(week: 5, last: LastTopSet(weight: 0, reps: 10, rpe: 8), repRange: "8-12", isCardio: false)
        #expect(c.suggestedWeight == 0)
        #expect(c.suggestedReps == 6)
    }

    @Test("The set-to-set cue on a bodyweight set talks reps, never pounds")
    func cueTalksReps() {
        let cue = CoachEngine.nextSetCue(loggedRPE: 6, targetRPE: 8, isCompound: true, isBodyweight: true)
        #expect(cue.weightDeltaLb == 0)
        #expect(cue.direction == .up)
        #expect(cue.label.contains("rep"))
    }
}

@Suite("RPE targets and cues")
struct RPETargetTests {

    @Test("Parsed RPE targets are clamped to 5–10")
    func clamp() {
        #expect(CoachEngine.rpeTargets("12") == [10])
        #expect(CoachEngine.rpeTargets("3→8→80") == [5, 8, 10])
        #expect(CoachEngine.repsLeftTarget(from: "12") == "0")
    }

    @Test("The set-to-set cue scales with the lift's step")
    func cueIncrement() {
        let small = CoachEngine.nextSetCue(loggedRPE: 6, targetRPE: 8, isCompound: false, increment: 2.5)
        #expect(small.weightDeltaLb == 2.5 && small.label == "Add 2.5 lb")
        let big = CoachEngine.nextSetCue(loggedRPE: 5, targetRPE: 8, isCompound: true, increment: 5)
        #expect(big.weightDeltaLb == 10)
    }
}

@Suite("Plate math and warm-up floors")
struct BarFloorTests {

    @Test("A target below the bar is flagged; the bar itself is exact")
    func belowBar() {
        let below = PlateMath.loadout(target: 40, bar: 45)
        #expect(below.isBelowBar && !below.isExact)
        let bar = PlateMath.loadout(target: 45, bar: 45)
        #expect(!bar.isBelowBar && bar.isExact)
    }

    @Test("Barbell warm-ups start at the empty bar")
    func barbellRamp() {
        #expect(WarmupRamp.steps(workingWeight: 95, barFloor: 45)
                == [.init(weight: 45, reps: 10), .init(weight: 55, reps: 5), .init(weight: 75, reps: 3)])
        #expect(WarmupRamp.steps(workingWeight: 65, barFloor: 45)
                == [.init(weight: 45, reps: 10), .init(weight: 50, reps: 3)])
        #expect(WarmupRamp.steps(workingWeight: 45, barFloor: 45).isEmpty)
        #expect(WarmupRamp.steps(workingWeight: 225, barFloor: 45) == WarmupRamp.steps(workingWeight: 225))
    }
}

@Suite("Timed holds")
struct TimedHoldTests {

    @Test("Planks and hangs log time")
    func metrics() {
        #expect(ExerciseLibrary.isTimedHold("Plank"))
        #expect(ExerciseLibrary.isTimedHold("Side Plank"))
        #expect(ExerciseLibrary.isTimedHold("Dead Hang"))
        #expect(ExerciseLibrary.isTimedHold("Wall Sit"))
        #expect(!ExerciseLibrary.isTimedHold("Hanging Knee Raise"))
        #expect(!ExerciseLibrary.isTimedHold("Barbell Bench Press"))
        #expect(ExerciseLibrary.metrics(for: "Plank", isCardio: false) == [.time])
    }

    @Test("The call never tells a hold to add load")
    func noLoadCall() {
        let c = CoachEngine.call(week: 3, last: LastTopSet(weight: 0, reps: 0, rpe: 7), repRange: "30-45s",
                                 isCardio: false, isTimed: true)
        #expect(c.suggestedWeight == nil && c.suggestedReps == nil)
    }
}

@Suite("PR history keys")
struct PRHistoryKeyTests {

    @Test("Spelling variants share one PR history")
    func canonicalKeys() {
        func workout(_ name: String, _ weight: Double, day: Double) -> LoggedWorkout {
            let w = LoggedWorkout(date: Date(timeIntervalSince1970: 1_700_000_000 + day * 86_400),
                                  weekNumber: 1, dayType: .lift, sessionName: "Upper")
            let ex = LoggedExercise(name: name, isCompound: true, sortOrder: 0)
            ex.sets = [LoggedSet(weight: weight, reps: 5, completed: true, sortOrder: 0)]
            w.exercises = [ex]
            return w
        }
        let prs = PersonalRecords.recentPRs(in: [workout("Bench Press", 185, day: 0),
                                                 workout("bench press", 195, day: 7)])
        #expect(prs.count == 1)
        #expect(prs.first?.weight == 195)
        #expect(ExerciseLibrary.historyKey(for: "Bench Press") == ExerciseLibrary.historyKey(for: " bench press "))
    }
}

@Suite("AI reply parsing")
struct AIResponseParsingTests {

    @Test("Trailing commas, prose mentioning the tag, and non-string items")
    func swapsLenient() {
        let reply = "I'll put them in <swaps> tags.\n<swaps>[\"Leg Press\", 42, \"Hack Squat\",]</swaps>"
        #expect(CoachSwapSuggester.parse(reply) == ["Leg Press", "Hack Squat"])
    }

    @Test("A reply cut off mid-array keeps the complete items")
    func swapsTruncated() {
        #expect(CoachSwapSuggester.parse("<swaps>[\"Leg Press\", \"Hack Squat\", \"Front Sq") == ["Leg Press", "Hack Squat"])
    }

    @Test("One malformed exercise is dropped instead of sinking the plan")
    func blockPlanLossy() {
        let reply = """
        <block_plan>{"blockNumber": "3", "theme": "T", "summary": "S", "sessions": [
          {"name": "Upper A", "subtitle": "Push", "exercises": [
            {"name": "Barbell Bench Press", "prescribedSets": 4, "repRange": "5-7", "rpeTarget": 8,
             "isCompound": true, "rationale": "r", "change": {"type": "kept"}},
            {"prescribedSets": 3},
            {"name": "Cable Fly", "prescribedSets": "3", "repRange": "12-15", "rpeTarget": "9",
             "rationale": "r", "change": {"type": "mystery"}},
          ]}
        ]}</block_plan>
        """
        let plan = CoachBlockPlanner.parse(response: reply)
        #expect(plan?.blockNumber == 3)
        #expect(plan?.sessions.first?.exercises.map(\.name) == ["Barbell Bench Press", "Cable Fly"])
        #expect(plan?.sessions.first?.exercises.first?.rpeTarget == "8")
        #expect(plan?.sessions.first?.exercises.last?.change == .new)
    }

    @Test("Body scan survives a fence and a bad estimate")
    func bodyScanLenient() {
        let reply = "<measurements>\n```json\n{\"estimates\": [{\"type\": \"waist\", \"value\": 33}, {\"type\": \"chest\", \"value\": \"big\"}], \"confidence\": \"low\"}\n```\n</measurements>"
        let result = BodyScanEstimator.parse(response: reply)
        #expect(result?.estimates.map(\.type) == [.waist])
    }
}
