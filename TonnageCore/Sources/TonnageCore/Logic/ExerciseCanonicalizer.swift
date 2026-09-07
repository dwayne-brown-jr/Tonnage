import Foundation

/// Maps free-text exercise names onto the library's canonical display names so the
/// same movement never fragments into parallel histories ("Dumbbell Incline Press"
/// vs "Incline DB Press" → separate PRs, ghosts, and chart series).
///
/// Matching is deliberately conservative: a name only rewrites when its token set —
/// after alias expansion (db/dumbbell, RDL, pushups…) — exactly equals a known
/// movement's. Anything else (true custom movements) passes through untouched.
public extension ExerciseLibrary {

    /// The library's display name for this movement, or the trimmed input unchanged
    /// if it isn't a recognized variant of a known movement.
    static func canonicalDisplayName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let exact = canonicalIndex.displayByKey[normalize(trimmed)] { return exact }
        if let key = canonicalIndex.keyByTokenSet[Set(matchTokens(for: trimmed))],
           let name = canonicalIndex.displayByKey[key] { return name }
        return trimmed
    }

    // MARK: - Matching internals

    /// Order-insensitive match tokens: lowercased, parens stripped, "-"/"/" split,
    /// aliases expanded, simple plurals stemmed, pulldown/pushdown re-joined.
    internal static func matchTokens(for name: String) -> [String] {
        let base = normalize(name)
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        var expanded: [String] = []
        for t in base.split(separator: " ").map(String.init) {
            expanded.append(contentsOf: expand(t))
        }
        var merged: [String] = []
        var i = 0
        while i < expanded.count {
            if i + 1 < expanded.count, let join = bigramMerges["\(expanded[i]) \(expanded[i + 1])"] {
                merged.append(join); i += 2
            } else {
                merged.append(expanded[i]); i += 1
            }
        }
        return merged
    }

    private static func expand(_ token: String) -> [String] {
        if let alias = tokenAliases[token] { return alias }
        // Simple plural stem ("raises" → "raise") — never after "ss" ("press" stays).
        let stemmed = (token.hasSuffix("s") && !token.hasSuffix("ss")) ? String(token.dropLast()) : token
        if let alias = tokenAliases[stemmed] { return alias }
        return [stemmed]
    }

    /// Shorthand and synonym expansion, applied per token (both to library names and input).
    private static let tokenAliases: [String: [String]] = [
        "dumbbell": ["db"], "dumbell": ["db"],
        "bb": ["barbell"],
        "ohp": ["overhead", "press"],
        "rdl": ["romanian", "deadlift"],
        "sldl": ["stiff", "leg", "deadlift"],
        "legged": ["leg"],                      // "stiff-legged" → "stiff-leg"
        "pushup": ["push", "up"],
        "pullup": ["pull", "up"],
        "chinup": ["chin", "up"],
        "stepup": ["step", "up"],
        "flye": ["fly"], "flies": ["fly"],
    ]

    /// Two-word forms that the library writes as one ("lat pull down" → "lat pulldown").
    private static let bigramMerges: [String: String] = [
        "pull down": "pulldown",
        "push down": "pushdown",
    ]

    /// Built once from the library's display vocabulary, deterministically
    /// (MuscleGroup order, then list order) so token-set collisions resolve stably.
    private static let canonicalIndex: (displayByKey: [String: String], keyByTokenSet: [Set<String>: String]) = {
        var displayByKey: [String: String] = [:]
        var keyByTokenSet: [Set<String>: String] = [:]
        for group in MuscleGroup.allCases {
            for name in exercisesByGroup[group] ?? [] {
                let key = normalize(name)
                if displayByKey[key] == nil { displayByKey[key] = name }
                let set = Set(matchTokens(for: name))
                if keyByTokenSet[set] == nil { keyByTokenSet[set] = key }
            }
        }
        return (displayByKey, keyByTokenSet)
    }()
}
