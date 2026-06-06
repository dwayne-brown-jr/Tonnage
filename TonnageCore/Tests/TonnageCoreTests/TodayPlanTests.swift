import Testing
@testable import TonnageCore

@Suite("Today verdict")
struct TodayPlanTests {

    @Test("Lift verdict is band + session aware")
    func lift() {
        #expect(TodayPlan.verdict(band: .primed, focus: "Lower A", dayType: .lift).contains("Lower A"))
        #expect(TodayPlan.verdict(band: .compromised, focus: "Lower A", dayType: .lift).contains("hold loads"))
        #expect(TodayPlan.verdict(band: .unknown, focus: nil, dayType: .lift).contains("Connect Apple Health"))
    }

    @Test("Rest days speak to recovery, not the session")
    func rest() {
        #expect(TodayPlan.verdict(band: .primed, focus: "Lower A", dayType: .fullRest).localizedCaseInsensitiveContains("rest"))
        #expect(TodayPlan.verdict(band: .primed, focus: "Lower A", dayType: .activeRest).localizedCaseInsensitiveContains("recovery"))
    }
}
