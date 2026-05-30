import Foundation

/// Builds the Coach prompt for a "Plan Next Block" call and parses the response.
/// Returns strict JSON inside `<block_plan>...</block_plan>` so we never have to grep
/// freeform prose to find the structured payload.
public enum CoachBlockPlanner {

    // MARK: System prompt

    /// Persona + hard rules for the planner. Inherits the athlete profile so the
    /// Coach speaks in their context, but flips into structured-output mode.
    public static func systemPrompt(for profile: CoachProfile) -> String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        let who = name.isEmpty ? "your athlete" : name
        let stats = profile.statsClause
        let statsPart = stats.isEmpty ? "" : " (\(stats))"

        return """
        You are \(who)'s strength coach. \(profile.experience.coachPhrase)\(statsPart), 4-day Upper/Lower split, training for \(profile.goal.coachPhrase).
        TASK: Plan the next 5-week block. Keep main barbell lifts constant across blocks so progress is measurable. Rotate accessory lifts based on what stalled or what's underdeveloped. Address weak points the prior block surfaced. Match the volume profile (sets × rep range) to the goal — leaner ranges for strength, higher reps for size.
        PHASE STRUCTURE inside every block: Week 1 RAMP (3–4 reps left), W2–3 BUILD (2 reps left), W4 PEAK (0–1 reps left), W5 DELOAD. You don't author per-week prescriptions — the engine derives those from the block-level rep range and rpe target.
        RULES:
        - Same 4 sessions: Upper A (Push focus), Lower A (Squat focus), Upper B (Pull focus), Lower B (Hinge focus).
        - 5–7 exercises per session, 1 compound first, then accessories.
        - Use real, well-known lift names — bench press, romanian deadlift, lat pulldown, etc. No invented exercises.
        - rpeTarget is a string like "8" or "7→8→8" (RPE per set; the app translates it to reps-left for the user).
        - For each exercise, set `change`:
          - `{"type":"kept"}` if the same exercise is keeping its spot (typically main barbell lifts)
          - `{"type":"swapped","from":"<prior exercise name>"}` if you're replacing one
          - `{"type":"new"}` if you're adding an accessory the prior block didn't have
        - One-sentence `rationale` per exercise grounded in the data: PR trend, stall, weak point, recovery.
        OUTPUT FORMAT — STRICT:
        Wrap the JSON in <block_plan> tags. No prose outside. No markdown fences. No code blocks. Just <block_plan>{...}</block_plan>.
        Schema:
        <block_plan>
        {
          "blockNumber": <int>,
          "theme": "<short label>",
          "summary": "<1–2 sentences>",
          "sessions": [
            {
              "name": "Upper A",
              "subtitle": "Push focus",
              "exercises": [
                {
                  "name": "Barbell Bench Press",
                  "prescribedSets": 4,
                  "repRange": "5-7",
                  "rpeTarget": "7→8→8→8",
                  "notes": "",
                  "isCompound": true,
                  "isCardio": false,
                  "rationale": "Top set climbed +15 lb across Block 1 — keep it as the strength anchor.",
                  "change": {"type":"kept"}
                }
              ]
            }
          ]
        }
        </block_plan>
        """
    }

    // MARK: User prompt

    /// Snapshot of where the athlete is right now — current program structure, lifetime
    /// PRs, the just-finished block's adherence + readiness average. The Coach uses
    /// this to decide what to keep vs. rotate.
    public static func userPrompt(
        currentBlockNumber: Int,
        program: Program?,
        prs: [PRMoment],
        adherence: BlockAdherence?,
        readinessAvg: Int?
    ) -> String {
        var lines: [String] = []
        lines.append("# CONTEXT FOR NEXT BLOCK")
        lines.append("Next block number: \(currentBlockNumber + 1).")

        if let adherence {
            let pct = Int((adherence.completionPct * 100).rounded())
            lines.append("Block \(currentBlockNumber) adherence: \(adherence.sessionsCompleted)/\(adherence.sessionsPlanned) sessions (\(pct)%), \(adherence.trainingDays) days lifted.")
        }
        if let avg = readinessAvg {
            lines.append("Average readiness across the block: \(avg)/100.")
        }

        if let program, !program.orderedSessions.isEmpty {
            lines.append("\n## Current program (the one to rewrite)")
            for s in program.orderedSessions {
                lines.append("### \(s.name) — \(s.subtitle)")
                for ex in s.orderedExercises {
                    let cardio = ex.isCardio ? " [cardio]" : (ex.isCompound ? " [compound]" : "")
                    lines.append("- \(ex.name): \(ex.prescribedSets)×\(ex.repRange), rpe \(ex.rpeTarget)\(cardio)")
                }
            }
        }

        if !prs.isEmpty {
            lines.append("\n## Recent PRs (lifetime, most recent first)")
            for pr in prs.prefix(12) {
                let date = pr.date.formatted(.dateTime.month(.abbreviated).day())
                lines.append("- \(pr.exerciseName): \(fmt(pr.weight))×\(pr.reps), e1RM \(fmt(pr.estimatedOneRM.rounded())) on \(date) (W\(pr.weekNumber) B\(pr.blockNumber))")
            }
        }

        lines.append("\nReturn the next block's plan in the <block_plan> JSON format specified.")
        return lines.joined(separator: "\n")
    }

    // MARK: Response parsing

    /// Extract the JSON between `<block_plan>` tags and decode it. Returns nil if the
    /// tags are missing or the JSON doesn't match the schema — caller surfaces that as
    /// "couldn't parse, regenerate?"
    public static func parse(response: String) -> BlockPlan? {
        guard let start = response.range(of: "<block_plan>"),
              let end = response.range(of: "</block_plan>", range: start.upperBound..<response.endIndex)
        else { return nil }
        let json = response[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BlockPlan.self, from: data)
    }

    // MARK: Helpers

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
