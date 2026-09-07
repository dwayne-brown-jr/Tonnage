import Testing
import Foundation
@testable import TonnageCore

struct LayoffTests {

    // MARK: Decay tiers

    @Test("A missed week is not a layoff — loads are untouched")
    func shortGapKeepsLoad() {
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 0) == 1.0)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 6) == 1.0)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 13) == 1.0)
    }

    @Test("Longer gaps scale loads down in steps, never below the deload floor")
    func tiersDecay() {
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 14) == 0.90)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 20) == 0.90)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 21) == 0.80)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 41) == 0.80)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 42) == 0.70)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 83) == 0.70)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 84) == 0.60)
        #expect(LayoffEngine.loadMultiplier(daysSinceLastLift: 900) == 0.60)
    }

    @Test("The multiplier never falls below the deload load, however long the gap")
    func neverBelowFloor() {
        for d in stride(from: 0, through: 1000, by: 7) {
            let m = LayoffEngine.loadMultiplier(daysSinceLastLift: d)
            #expect(m >= 0.6 && m <= 1.0)
        }
    }

    @Test("Significance threshold sits at two weeks")
    func significance() {
        #expect(Layoff(days: 13, loadMultiplier: 1.0).isSignificant == false)
        #expect(Layoff(days: 14, loadMultiplier: 0.9).isSignificant == true)
    }

    @Test("Gaps read in human units")
    func summaryPhrasing() {
        #expect(Layoff(days: 1, loadMultiplier: 1).summary == "1 day")
        #expect(Layoff(days: 5, loadMultiplier: 1).summary == "5 days")
        #expect(Layoff(days: 21, loadMultiplier: 0.8).summary == "3 weeks")
        #expect(Layoff(days: 63, loadMultiplier: 0.7).summary == "2 months")
    }

    // MARK: Days since last lift

    @Test("Counts from the most recent completed lift, ignoring rest days")
    func daysSinceIgnoresRest() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let lift = workout(daysAgo: 30, from: now, cal: cal, type: .lift, completed: true)
        let rest = workout(daysAgo: 2, from: now, cal: cal, type: .fullRest, completed: false)
        let days = LayoffEngine.daysSinceLastLift(workouts: [lift, rest], now: now, calendar: cal)
        #expect(days == 30)
    }

    @Test("An unlogged lift shell doesn't count as training")
    func emptyWorkoutIgnored() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let real = workout(daysAgo: 40, from: now, cal: cal, type: .lift, completed: true)
        let shell = workout(daysAgo: 1, from: now, cal: cal, type: .lift, completed: false)
        #expect(LayoffEngine.daysSinceLastLift(workouts: [real, shell], now: now, calendar: cal) == 40)
    }

    @Test("A brand-new user with no history is not 'returning'")
    func noHistoryIsNotALayoff() {
        #expect(LayoffEngine.assess(workouts: []) == nil)
    }

    // MARK: Effect on the Coach's Call

    @Test("A long layoff overrides normal week progression and cuts the load")
    func callHonoursLayoff() {
        let last = LastTopSet(weight: 225, reps: 5, rpe: 7.0)
        let fresh = CoachEngine.call(week: 3, last: last, repRange: "4-6", isCardio: false)
        #expect(fresh.suggestedWeight == 230)          // normal week 3 → add 5 lb

        let returning = CoachEngine.call(week: 3, last: last, repRange: "4-6", isCardio: false,
                                         layoff: Layoff(days: 63, loadMultiplier: 0.7))
        #expect(returning.suggestedWeight == 160)      // 225 × 0.7 = 157.5 → nearest 5
        #expect(returning.emphasis == .deload)
        #expect(returning.headline.contains("2 months"))
    }

    @Test("A short gap leaves the normal call alone")
    func shortGapDoesNotOverride() {
        let last = LastTopSet(weight: 225, reps: 5, rpe: 7.0)
        let call = CoachEngine.call(week: 3, last: last, repRange: "4-6", isCardio: false,
                                    layoff: Layoff(days: 9, loadMultiplier: 1.0))
        #expect(call.suggestedWeight == 230)
    }

    @Test("An explicit deload still wins when it is the lighter of the two")
    func deloadWinsWhenLighter() {
        let last = LastTopSet(weight: 200, reps: 5, rpe: 7.0)
        let call = CoachEngine.call(week: 2, last: last, repRange: "4-6", isCardio: false,
                                    forceDeload: true,
                                    layoff: Layoff(days: 20, loadMultiplier: 0.9))
        #expect(call.suggestedWeight == 120)           // 0.6 floor, not 0.9
    }

    @Test("With no prior top set there is nothing to scale")
    func noLastSetNoOverride() {
        let call = CoachEngine.call(week: 3, last: nil, repRange: "4-6", isCardio: false,
                                    layoff: Layoff(days: 90, loadMultiplier: 0.6))
        #expect(call.suggestedWeight == nil)
    }

    // MARK: Helpers

    private func workout(daysAgo: Int, from now: Date, cal: Calendar,
                         type: DayType, completed: Bool) -> LoggedWorkout {
        let w = LoggedWorkout(date: cal.date(byAdding: .day, value: -daysAgo, to: now)!,
                              weekNumber: 1, dayType: type, sessionName: "Legs A")
        if completed {
            let ex = LoggedExercise(name: "Squat", sortOrder: 0)
            ex.sets = [LoggedSet(weight: 225, reps: 5, rpe: 7, completed: true, sortOrder: 0)]
            w.exercises = [ex]
        }
        return w
    }
}
