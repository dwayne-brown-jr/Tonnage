import Foundation

/// Builds the prompt for an AI swap suggestion ("Ask Coach for alternatives") and parses
/// the reply into exercise names. The rule-based chips cover same-muscle swaps instantly;
/// this is the optional smarter pass that can factor in the athlete's goal + limitations
/// and reach beyond the built-in catalog.
public enum CoachSwapSuggester {

    public static func systemPrompt(for profile: CoachProfile) -> String {
        let limits = profile.limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        let limitsLine = limits.isEmpty ? "" : " Work around these limitations they flagged: \(limits)."
        return """
        You suggest alternative exercises for a lifter mid-program. Given a movement they want to swap out, propose 5 alternatives that train the SAME primary muscles so their program stays balanced.\(limitsLine) They're training for \(profile.goal.coachPhrase).
        Use real, well-known exercise names — no inventions. Favor practical gym options with some variety in equipment/setup. Never repeat the original movement.
        OUTPUT: only a JSON array of exercise-name strings wrapped in <swaps> tags. No prose, no markdown.
        <swaps>["Front Squat","Leg Press","Hack Squat","Bulgarian Split Squat","Walking Lunge"]</swaps>
        """
    }

    public static func userPrompt(exerciseName: String, isCardio: Bool) -> String {
        let kind = isCardio ? "conditioning option" : "movement"
        return "Suggest 5 alternatives to \"\(exerciseName)\" — the same \(kind), training the same primary muscles. Return the <swaps> JSON array only."
    }

    /// Extract the exercise names from the `<swaps>` array. Trims, de-dupes, caps at 6.
    public static func parse(_ response: String) -> [String] {
        guard let start = response.range(of: "<swaps>"),
              let end = response.range(of: "</swaps>", range: start.upperBound..<response.endIndex)
        else { return [] }
        let json = response[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }

        var seen = Set<String>()
        var out: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
            if out.count >= 6 { break }
        }
        return out
    }
}
