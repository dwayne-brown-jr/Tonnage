import Testing
@testable import TonnageCore

@Suite("Coaching principles")
struct CoachingPrinciplesTests {

    @Test("Principles cover the key levers")
    func content() {
        let p = CoachingPrinciples.evidenceBased
        #expect(p.contains("sets per muscle"))
        #expect(p.lowercased().contains("reps in reserve"))
        #expect(p.lowercased().contains("progressive overload"))
        #expect(p.lowercased().contains("deload"))
    }

    @Test("Both the coach and planner prompts include the principles")
    func wiredIntoPrompts() {
        let profile = CoachProfile(name: "Test")
        #expect(CoachContext.systemPrompt(for: profile).contains("EVIDENCE-BASED PRINCIPLES"))
        #expect(CoachBlockPlanner.systemPrompt(for: profile).contains("EVIDENCE-BASED PRINCIPLES"))
    }
}
