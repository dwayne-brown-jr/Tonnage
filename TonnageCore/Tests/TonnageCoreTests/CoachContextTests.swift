import Testing
import Foundation
@testable import TonnageCore

@Suite("Coach context")
struct CoachContextTests {

    private func benchWorkout() -> LoggedWorkout {
        let ex = LoggedExercise(name: "Barbell Bench Press", isCompound: true, sortOrder: 0)
        ex.sets = [
            LoggedSet(weight: 135, reps: 6, rpe: 7, completed: true, sortOrder: 0),
            LoggedSet(weight: 145, reps: 5, rpe: 8, completed: true, sortOrder: 1)
        ]
        let w = LoggedWorkout(weekNumber: 2, dayType: .lift, sessionName: "Upper A", notes: "felt strong")
        w.exercises = [ex]
        return w
    }

    @Test("Context includes program week, recovery, and top sets")
    func buildsContext() {
        let recovery = CoachRecovery(bodyweightLb: 179, bodyweightChangeLb: -1.5, restingHR: 54, sleepHours: 7.2)
        let text = CoachContext.build(program: nil, currentWeek: 2,
                                      recentWorkouts: [benchWorkout()], activities: [],
                                      recovery: recovery)
        #expect(text.contains("Week 2"))
        #expect(text.contains("BUILD"))
        #expect(text.contains("bodyweight 179 lb"))
        #expect(text.contains("−1.5 lb"))
        #expect(text.contains("resting HR 54 bpm"))
        #expect(text.contains("Barbell Bench Press 145×5 · 2 left")) // top set, not the lighter one
        #expect(text.contains("felt strong"))
    }

    @Test("Context includes the program plan so the coach knows each session's exercises")
    func includesProgramPlan() {
        let bench = ExerciseTemplate(name: "Barbell Bench Press", prescribedSets: 3, repRange: "5-7",
                                     rpeTarget: "8", isCompound: true, sortOrder: 0)
        let row = ExerciseTemplate(name: "Barbell Row", prescribedSets: 3, repRange: "8-10",
                                   rpeTarget: "8", sortOrder: 0)
        let upperA = SessionTemplate(name: "Upper A", subtitle: "Push focus", sortOrder: 0, exercises: [bench])
        let upperB = SessionTemplate(name: "Upper B", subtitle: "Pull focus", sortOrder: 1, exercises: [row])
        let program = Program(name: "Block 01", sessions: [upperB, upperA])   // unordered on purpose

        let text = CoachContext.build(program: program, currentWeek: 1, recentWorkouts: [],
                                      activities: [], recovery: CoachRecovery())

        #expect(text.contains("Program plan"))
        #expect(text.contains("Upper A — Push focus"))
        #expect(text.contains("Upper B — Pull focus"))
        #expect(text.contains("Barbell Bench Press: 3×5-7, 2 reps left (compound)"))
        #expect(text.contains("Barbell Row: 3×8-10"))
        #expect(!text.contains("RPE"))   // reps-left language only
    }

    @Test("Flags a session trained today so the coach won't tell them to redo it")
    func alreadyTrainedToday() {
        let todayText = CoachContext.build(program: nil, currentWeek: 2,
                                           recentWorkouts: [benchWorkout()], activities: [],
                                           recovery: CoachRecovery())
        #expect(todayText.contains("ALREADY TRAINED TODAY"))
        #expect(todayText.contains("Upper A"))

        // A workout from a prior day must not trigger it.
        let past = benchWorkout()
        past.date = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let pastText = CoachContext.build(program: nil, currentWeek: 2,
                                          recentWorkouts: [past], activities: [],
                                          recovery: CoachRecovery())
        #expect(!pastText.contains("ALREADY TRAINED TODAY"))
    }

    @Test("Empty recovery is stated explicitly")
    func emptyRecovery() {
        let text = CoachContext.build(program: nil, currentWeek: 1, recentWorkouts: [],
                                      activities: [], recovery: CoachRecovery())
        #expect(text.contains("no HealthKit data shared"))
        #expect(text.contains("No workouts logged yet"))
    }

    @Test("System prompt carries the core philosophy + personalizes to the profile")
    func systemPrompt() {
        let prompt = CoachContext.systemPrompt(for: CoachProfile(name: "Sam", goal: .strength, experience: .experienced))
        #expect(prompt.contains("RAMP first, push later"))
        #expect(prompt.contains("Numbers over vibes"))
        #expect(prompt.contains("Sam"))                 // personalized name
        #expect(prompt.contains("experienced lifter"))  // experience phrase
        #expect(!prompt.contains("Dwayne"))             // no hardcoded identity
    }
}
