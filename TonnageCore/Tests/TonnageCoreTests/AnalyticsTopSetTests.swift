import Testing
import Foundation
@testable import TonnageCore

@Suite("Top-set series")
struct AnalyticsTopSetTests {

    private func wk(_ week: Int, _ weight: Double, _ reps: Int) -> LoggedWorkout {
        let w = LoggedWorkout(date: Date(timeIntervalSince1970: 1_700_000_000 + Double(week) * 86_400),
                              blockNumber: 1, weekNumber: week, dayType: .lift, sessionName: "Upper")
        let ex = LoggedExercise(name: "Bench", sortOrder: 0)
        ex.sets = [LoggedSet(weight: weight, reps: reps, rpe: nil, completed: true, sortOrder: 0)]
        w.exercises = [ex]
        return w
    }

    @Test("A week logged twice yields one point — the heavier — with no id collision")
    func dedupWeek() {
        let series = Analytics.topSetSeries(for: "Bench", in: [wk(2, 135, 5), wk(2, 155, 5)])
        #expect(series.count == 1)
        #expect(series.first?.week == 2)
        #expect(series.first?.weight == 155)
        #expect(Set(series.map(\.id)).count == series.count)
    }

    @Test("Distinct weeks each produce a point, ascending")
    func ascendingWeeks() {
        let series = Analytics.topSetSeries(for: "Bench", in: [wk(3, 145, 5), wk(1, 135, 5), wk(2, 140, 5)])
        #expect(series.map(\.week) == [1, 2, 3])
    }

    @Test("TopSetPoint e1RM matches Epley")
    func e1rmMatchesEpley() {
        let p = Analytics.TopSetPoint(week: 1, weight: 200, reps: 5)
        #expect(abs(p.estimatedOneRepMax - PersonalRecords.epley(weight: 200, reps: 5)) < 0.001)
    }
}
