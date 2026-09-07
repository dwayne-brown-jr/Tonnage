import Testing
@testable import TonnageCore

@Suite("Insight engine (streak)")
struct InsightStreakTests {

    @Test("A long training streak surfaces a rest insight")
    func restStreak() {
        let insights = InsightEngine.generate(.init(
            readiness: [70, 72, 74, 76, 78], hrv: [], lifts: [], currentWeek: 3, trainingStreak: 6))
        #expect(insights.contains { $0.id == "rest-streak" })
    }

    @Test("Below the threshold, no rest insight")
    func noRestStreak() {
        let insights = InsightEngine.generate(.init(
            readiness: [70, 72, 74, 76, 78], hrv: [], lifts: [], currentWeek: 3, trainingStreak: 5))
        #expect(!insights.contains { $0.id == "rest-streak" })
    }

    @Test("HRV-down fires only when readiness isn't also falling")
    func hrvDownAlone() {
        let insights = InsightEngine.generate(.init(
            readiness: [70, 70, 71, 70, 71], hrv: [60, 58, 55, 52, 49], lifts: [], currentWeek: 3))
        #expect(insights.contains { $0.id == "hrv-down" })
        #expect(!insights.contains { $0.id == "readiness-down" })
        #expect(!insights.contains { $0.id == "deload" })
    }
}
