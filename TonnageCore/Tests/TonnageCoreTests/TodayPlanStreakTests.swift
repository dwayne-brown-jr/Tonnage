import Testing
@testable import TonnageCore

@Suite("Today verdict (streak)")
struct TodayPlanStreakTests {

    @Test("A 6-day streak overrides a primed band with a rest nudge")
    func streakOverrides() {
        let v = TodayPlan.verdict(band: .primed, focus: "Upper A", dayType: .lift, trainingStreak: 6)
        #expect(v.contains("days straight"))
        #expect(!v.contains("Primed"))
    }

    @Test("Just below the rest threshold keeps the band verdict")
    func belowThreshold() {
        let v = TodayPlan.verdict(band: .primed, focus: "Upper A", dayType: .lift, trainingStreak: 5)
        #expect(v.contains("Primed"))
    }

    @Test("Rest days ignore the streak override")
    func restIgnoresStreak() {
        let v = TodayPlan.verdict(band: .primed, focus: "Upper A", dayType: .fullRest, trainingStreak: 10)
        #expect(v.contains("Full rest"))
    }
}
