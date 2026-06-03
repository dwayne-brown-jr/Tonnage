import Testing
import Foundation
@testable import TonnageCore

@Suite("Block plan")
struct BlockPlanTests {

    // MARK: BlockPlan codable

    @Test("BlockPlan + PlanChange round-trip through Codable")
    func roundTrip() throws {
        let plan = BlockPlan(
            blockNumber: 2,
            theme: "Pull focus + hypertrophy accessories",
            summary: "Same main lifts. Rotates rows + lateral raises to address the shoulder gap.",
            sessions: [
                SessionPlan(name: "Upper A", subtitle: "Push focus", exercises: [
                    ExercisePlan(name: "Barbell Bench Press", prescribedSets: 4, repRange: "5-7",
                                 rpeTarget: "7→8→8→8", isCompound: true,
                                 rationale: "Anchor — keep it.", change: .kept),
                    ExercisePlan(name: "Chest-Supported Row", prescribedSets: 3, repRange: "10-12",
                                 rpeTarget: "8",
                                 rationale: "Top set stalled W3-5.", change: .swapped(from: "Cable Row")),
                    ExercisePlan(name: "Lateral Raise", prescribedSets: 3, repRange: "12-15",
                                 rpeTarget: "8", rationale: "Address shoulder weak point.", change: .new)
                ])
            ]
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BlockPlan.self, from: data)
        #expect(decoded == plan)
    }

    @Test("PlanChange decodes from the documented tagged-JSON shapes")
    func planChangeTaggedJSON() throws {
        // Key order in JSON output isn't guaranteed, so test by decoding the shapes the
        // schema documents — what the model will actually produce.
        let decoder = JSONDecoder()
        let kept = try decoder.decode(PlanChange.self, from: Data(#"{"type":"kept"}"#.utf8))
        let new = try decoder.decode(PlanChange.self, from: Data(#"{"type":"new"}"#.utf8))
        let swapped = try decoder.decode(PlanChange.self, from: Data(#"{"type":"swapped","from":"Cable Row"}"#.utf8))
        let swappedReordered = try decoder.decode(PlanChange.self, from: Data(#"{"from":"Cable Row","type":"swapped"}"#.utf8))

        #expect(kept == .kept)
        #expect(new == .new)
        #expect(swapped == .swapped(from: "Cable Row"))
        #expect(swappedReordered == .swapped(from: "Cable Row"))   // key order doesn't matter
    }

    // MARK: Parser

    @Test("Parser pulls the JSON out of <block_plan> tags surrounded by prose")
    func parserExtractsTaggedJSON() {
        let response = """
        Sure, here's the plan I'd run next.
        <block_plan>
        {
          "blockNumber": 2,
          "theme": "Strength peak",
          "summary": "Keeps main lifts, peaks bench in W4.",
          "sessions": [
            {
              "name": "Upper A",
              "subtitle": "Push focus",
              "exercises": [
                {
                  "name": "Barbell Bench Press",
                  "prescribedSets": 4,
                  "repRange": "3-5",
                  "rpeTarget": "8→8→9→9",
                  "notes": "",
                  "isCompound": true,
                  "isCardio": false,
                  "rationale": "Top set climbed Block 1 — push to a hard triple in W4.",
                  "change": {"type":"kept"}
                }
              ]
            }
          ]
        }
        </block_plan>
        Let me know if you want me to swap anything.
        """

        let plan = CoachBlockPlanner.parse(response: response)
        #expect(plan != nil)
        #expect(plan?.blockNumber == 2)
        #expect(plan?.sessions.first?.exercises.first?.name == "Barbell Bench Press")
        #expect(plan?.sessions.first?.exercises.first?.change == .kept)
    }

    @Test("Parser returns nil on missing tags or malformed JSON")
    func parserNilOnBadInput() {
        #expect(CoachBlockPlanner.parse(response: "No tags here, just chat.") == nil)
        #expect(CoachBlockPlanner.parse(response: "<block_plan>not json</block_plan>") == nil)
        #expect(CoachBlockPlanner.parse(response: "<block_plan>{ \"blockNumber\": 2 }</block_plan>") == nil)  // missing required fields
    }

    // MARK: Prompt sanity

    @Test("System prompt includes the structured-output rules and the schema marker")
    func systemPromptCoversTheBasics() {
        let prompt = CoachBlockPlanner.systemPrompt(for: CoachProfile(name: "Test", goal: .strength, experience: .experienced))
        #expect(prompt.contains("<block_plan>"))
        #expect(prompt.contains("Upper A"))
        #expect(prompt.contains("Lower B"))
        #expect(prompt.contains("reps-left"))
    }

    @Test("userPrompt switches framing between next-block and re-plan-current")
    func userPromptReplanFraming() {
        let next = CoachBlockPlanner.userPrompt(currentBlockNumber: 2, program: nil, prs: [],
                                                adherence: nil, readinessAvg: nil)
        let replan = CoachBlockPlanner.userPrompt(currentBlockNumber: 2, program: nil, prs: [],
                                                  adherence: nil, readinessAvg: nil, replanCurrent: true)
        #expect(next.contains("NEXT BLOCK"))
        #expect(next.contains("Next block number: 3"))
        #expect(replan.contains("RE-PLAN THE CURRENT BLOCK"))
        #expect(replan.contains("Re-plan Block 2"))
        #expect(!replan.contains("Next block number"))
    }
}
