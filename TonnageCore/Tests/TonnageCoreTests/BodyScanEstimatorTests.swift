import Testing
@testable import TonnageCore

@Suite("Body scan estimator")
struct BodyScanEstimatorTests {

    @Test("Parses estimates from a tagged response surrounded by prose")
    func parsesTagged() {
        let response = """
        Sure — here's my read.
        <measurements>
        {
          "estimates": [
            {"type":"chest","value":42},
            {"type":"waist","value":33.5},
            {"type":"bodyFat","value":16}
          ],
          "confidence":"low",
          "note":"Rough estimate."
        }
        </measurements>
        Confirm with a tape!
        """
        let result = BodyScanEstimator.parse(response: response)
        #expect(result != nil)
        #expect(result?.estimates.count == 3)
        #expect(result?.estimates.first(where: { $0.type == .waist })?.value == 33.5)
        #expect(result?.confidence == "low")
    }

    @Test("Maps loose/synonym type names to the canonical types")
    func mapsAliases() {
        let response = """
        <measurements>
        {"estimates":[{"type":"bicep","value":15},{"type":"body_fat","value":18},{"type":"quads","value":24}],"confidence":"medium","note":""}
        </measurements>
        """
        let result = BodyScanEstimator.parse(response: response)
        let types = Set(result?.estimates.map(\.type) ?? [])
        #expect(types == [.arm, .bodyFat, .thigh])
    }

    @Test("Filters unknown types and non-positive values")
    func filtersJunk() {
        let response = """
        <measurements>
        {"estimates":[{"type":"chest","value":42},{"type":"wingspan","value":70},{"type":"waist","value":0}],"confidence":"low","note":""}
        </measurements>
        """
        let result = BodyScanEstimator.parse(response: response)
        #expect(result?.estimates.map(\.type) == [.chest])   // wingspan dropped, 0-waist dropped
    }

    @Test("Returns nil on missing tags, bad JSON, or no usable estimates")
    func nilOnBadInput() {
        #expect(BodyScanEstimator.parse(response: "no tags here") == nil)
        #expect(BodyScanEstimator.parse(response: "<measurements>not json</measurements>") == nil)
        #expect(BodyScanEstimator.parse(response: "<measurements>{\"estimates\":[],\"confidence\":\"low\"}</measurements>") == nil)
    }

    @Test("System prompt covers the schema marker, allowed keys, and the honesty cue")
    func systemPromptBasics() {
        let p = BodyScanEstimator.systemPrompt(for: CoachProfile(name: "Test"))
        #expect(p.contains("<measurements>"))
        #expect(p.contains("bodyFat"))
        #expect(p.contains("INCHES"))
        #expect(p.lowercased().contains("rough"))
    }
}
