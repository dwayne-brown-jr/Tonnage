import Testing
import Foundation
@testable import TonnageCore

@Suite("Personal records")
struct PersonalRecordsTests {

    @Test("First completed set is the baseline, later improvements are PRs")
    func baselineThenPRs() {
        let baseline = workout(name: "Bench", date: day(0), sets: [(135, 5)])     // baseline
        let plateau  = workout(name: "Bench", date: day(1), sets: [(135, 5)])     // tie — not a PR
        let firstPR  = workout(name: "Bench", date: day(2), sets: [(140, 5)])     // PR (heavier)
        let secondPR = workout(name: "Bench", date: day(3), sets: [(135, 8)])     // PR (more reps)

        let prs = PersonalRecords.recentPRs(in: [baseline, plateau, firstPR, secondPR])

        #expect(prs.count == 2)
        // Most recent first
        #expect(prs[0].weight == 135 && prs[0].reps == 8)
        #expect(prs[1].weight == 140 && prs[1].reps == 5)
    }

    @Test("Cardio exercises never generate PRs")
    func cardioExcluded() {
        let w1 = workout(name: "Walk", date: day(0), sets: [(0, 30)], cardio: true)
        let w2 = workout(name: "Walk", date: day(1), sets: [(0, 45)], cardio: true)
        #expect(PersonalRecords.recentPRs(in: [w1, w2]).isEmpty)
    }

    @Test("Incomplete sets don't establish a baseline OR a PR")
    func incompleteIgnored() {
        let scratched = workout(name: "Bench", date: day(0), sets: [(180, 8)], completedFlag: false)
        #expect(PersonalRecords.recentPRs(in: [scratched]).isEmpty)
    }

    @Test("PR limit caps the most recent N moments")
    func respectsLimit() {
        // baseline + 5 ascending PRs
        let workouts = (0...5).map { i in
            workout(name: "Squat", date: day(i), sets: [(100.0 + 10.0 * Double(i), 5)])
        }
        let prs = PersonalRecords.recentPRs(in: workouts, limit: 3)
        #expect(prs.count == 3)
        #expect(prs[0].date == day(5))   // newest
        #expect(prs[2].date == day(3))
    }

    @Test("Separate exercises track their own baseline")
    func perExerciseBaselines() {
        let benchBase = workout(name: "Bench", date: day(0), sets: [(135, 5)])
        let squatBase = workout(name: "Squat", date: day(0), sets: [(225, 5)])
        let benchPR   = workout(name: "Bench", date: day(1), sets: [(140, 5)])  // PR
        let squatPR   = workout(name: "Squat", date: day(2), sets: [(230, 5)])  // PR

        let prs = PersonalRecords.recentPRs(in: [benchBase, squatBase, benchPR, squatPR])
        #expect(prs.count == 2)
        #expect(prs.contains(where: { $0.exerciseName == "Bench" }))
        #expect(prs.contains(where: { $0.exerciseName == "Squat" }))
    }

    // MARK: helpers

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    private func workout(name: String, date: Date, sets: [(Double, Int)],
                         cardio: Bool = false, completedFlag: Bool = true) -> LoggedWorkout {
        let ex = LoggedExercise(name: name, isCardio: cardio, sortOrder: 0)
        ex.sets = sets.enumerated().map { i, s in
            LoggedSet(weight: s.0, reps: s.1, rpe: nil, completed: completedFlag, sortOrder: i)
        }
        let w = LoggedWorkout(date: date, weekNumber: 1, dayType: .lift, sessionName: "Test")
        w.exercises = [ex]
        return w
    }
}
