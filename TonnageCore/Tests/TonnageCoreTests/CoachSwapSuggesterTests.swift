import Testing
@testable import TonnageCore

@Suite("Coach swap suggester")
struct CoachSwapSuggesterTests {

    @Test("Parses the swaps array out of tagged JSON surrounded by prose")
    func parsesTagged() {
        let response = """
        Sure, here are some options.
        <swaps>["Front Squat", "Leg Press", "Hack Squat"]</swaps>
        Pick whichever fits your gym.
        """
        #expect(CoachSwapSuggester.parse(response) == ["Front Squat", "Leg Press", "Hack Squat"])
    }

    @Test("De-dupes (case-insensitive), trims, and caps at 6")
    func dedupeAndCap() {
        let response = #"<swaps>["Leg Press"," leg press ","A","B","C","D","E","F"]</swaps>"#
        let out = CoachSwapSuggester.parse(response)
        #expect(out.count == 6)
        #expect(out.prefix(2) == ["Leg Press", "A"])   // duplicate "leg press" dropped
    }

    @Test("Returns empty on missing tags or malformed JSON")
    func emptyOnBadInput() {
        #expect(CoachSwapSuggester.parse("no tags").isEmpty)
        #expect(CoachSwapSuggester.parse("<swaps>not json</swaps>").isEmpty)
    }

    @Test("System prompt has the schema marker and folds in limitations")
    func systemPrompt() {
        let p = CoachSwapSuggester.systemPrompt(for: CoachProfile(name: "Test", limitations: "bad left shoulder"))
        #expect(p.contains("<swaps>"))
        #expect(p.contains("bad left shoulder"))
    }
}
