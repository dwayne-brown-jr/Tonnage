import Testing
import Foundation
@testable import TonnageCore

@Suite("Block progress (week bars and chip)")
struct BlockProgressTests {

    private func workout(week: Int, block: Int = 3, session: String = "Upper A",
                         _ name: String = "Barbell Bench Press", sets: [(Double, Int)]) -> LoggedWorkout {
        let w = LoggedWorkout(date: .now, blockNumber: block, weekNumber: week, dayType: .lift, sessionName: session)
        let ex = LoggedExercise(name: name, isCompound: true, sortOrder: 0)
        ex.sets = sets.enumerated().map { i, s in LoggedSet(weight: s.0, reps: s.1, completed: true, sortOrder: i) }
        w.exercises = [ex]
        return w
    }

    @Test("Gain is best build-week top set minus week 1, and the deload doesn't count")
    func gain() {
        let ws = [workout(week: 1, sets: [(190, 6)]), workout(week: 2, sets: [(195, 6)]),
                  workout(week: 3, sets: [(205, 5)]), workout(week: 5, sets: [(125, 6)])]
        let p = BlockProgress.build(from: ws, exercise: "Barbell Bench Press", sessionName: "Upper A", block: 3, currentWeek: 4)
        #expect(p.weeks.map(\.weight) == [190, 195, 205, nil, 125])
        #expect(p.weightGain == 15)
        #expect(p.chipText == "+15 LB")
        #expect(p.chipSpokenText == "up 15 pounds this block")
        #expect(p.hasHistory)
    }

    @Test("Other blocks, other sessions and spelling variants are handled")
    func scoping() {
        let ws = [workout(week: 1, sets: [(190, 6)]),
                  workout(week: 2, "bench press", sets: [(200, 6)]),   // not the same canonical name
                  workout(week: 2, sets: [(195, 6)]),
                  workout(week: 3, block: 2, sets: [(400, 1)]),
                  workout(week: 3, session: "Upper B", sets: [(300, 1)])]
        let p = BlockProgress.build(from: ws, exercise: "Barbell Bench Press", sessionName: "Upper A", block: 3, currentWeek: 2)
        #expect(p.weeks.map(\.weight) == [190, 195, nil, nil, nil])
    }

    @Test("No chip for one week of history or a flat or falling block")
    func noChip() {
        let one = BlockProgress.build(from: [workout(week: 1, sets: [(190, 6)])], exercise: "Barbell Bench Press",
                                      sessionName: "Upper A", block: 3, currentWeek: 1)
        #expect(one.chipText == nil && !one.hasHistory)
        let flat = BlockProgress.build(from: [workout(week: 1, sets: [(190, 6)]), workout(week: 2, sets: [(185, 8)])],
                                       exercise: "Barbell Bench Press", sessionName: "Upper A", block: 3, currentWeek: 2)
        #expect(flat.chipText == nil)
    }

    @Test("Bodyweight work reports reps gained")
    func bodyweight() {
        let ws = [workout(week: 1, "Push-up", sets: [(0, 12)]), workout(week: 2, "Push-up", sets: [(0, 15)])]
        let p = BlockProgress.build(from: ws, exercise: "Push-up", sessionName: "Upper A", block: 3, currentWeek: 2)
        #expect(p.chipText == "+3 REPS")
        #expect(p.barFraction(p.weeks[1]) == 1)
    }

    @Test("Bars scale between the block's lightest and heaviest week")
    func bars() {
        let ws = [workout(week: 1, sets: [(190, 6)]), workout(week: 2, sets: [(200, 6)]), workout(week: 3, sets: [(210, 5)])]
        let p = BlockProgress.build(from: ws, exercise: "Barbell Bench Press", sessionName: "Upper A", block: 3, currentWeek: 3)
        #expect(p.barFraction(p.weeks[0]) == 0.35)
        #expect(p.barFraction(p.weeks[2]) == 1)
        #expect(p.barFraction(p.weeks[3]) == 0)
    }
}

@Suite("Block lift gains (DATA ticker)")
struct LiftGainsTests {

    private func workout(week: Int, block: Int = 1, _ lifts: [(String, Double)]) -> LoggedWorkout {
        let w = LoggedWorkout(date: .now, blockNumber: block, weekNumber: week, dayType: .lift, sessionName: "S")
        w.exercises = lifts.enumerated().map { i, l in
            let ex = LoggedExercise(name: l.0, isCompound: true, sortOrder: i)
            ex.sets = [LoggedSet(weight: l.1, reps: 5, completed: true, sortOrder: 0)]
            return ex
        }
        return w
    }

    @Test("Gains are best build week minus first week, biggest first, losers and bodyweight left out")
    func gains() {
        let ws = [workout(week: 1, [("Barbell Bench Press", 135), ("Barbell Back Squat", 185), ("DB Curl", 30), ("Push-up", 0)]),
                  workout(week: 2, [("Barbell Bench Press", 140), ("Barbell Back Squat", 205), ("DB Curl", 25), ("Push-up", 0)]),
                  workout(week: 3, [("Barbell Bench Press", 145)]),
                  workout(week: 5, [("Barbell Back Squat", 400)]),               // deload week ignored
                  workout(week: 2, block: 2, [("Barbell Bench Press", 300)])]   // other block ignored
        let g = BlockProgress.liftGains(from: ws, block: 1)
        #expect(g.map(\.name) == ["Barbell Back Squat", "Barbell Bench Press"])
        #expect(g.map(\.gainLb) == [20, 10])
    }
}
