import Foundation

/// A prior top set used as the basis for this week's recommendation.
public struct LastTopSet: Sendable, Equatable {
    public let weight: Double
    public let reps: Int
    public let rpe: Double?

    public init(weight: Double, reps: Int, rpe: Double?) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
    }
}

/// The rule-based load recommendation shown per exercise on the TRAIN screen.
public struct CoachsCall: Sendable, Equatable {
    public enum Emphasis: Sendable { case ramp, progress, hold, deload, neutral }

    /// One-line directive (e.g. "Hold the weight, chase +1 rep.").
    public let headline: String
    /// Suggested working weight to pre-fill the first set (nil = leave blank).
    public let suggestedWeight: Double?
    /// Suggested reps to pre-fill the first set.
    public let suggestedReps: Int?
    public let emphasis: Emphasis

    public init(headline: String, suggestedWeight: Double?, suggestedReps: Int?, emphasis: Emphasis) {
        self.headline = headline
        self.suggestedWeight = suggestedWeight
        self.suggestedReps = suggestedReps
        self.emphasis = emphasis
    }
}

/// A reactive, set-to-set load cue shown after you complete a set and log its RPE.
/// Compares the effort you just logged against that set's target RPE: came in easy →
/// add weight; on target → hold; harder than planned → hold or back off. This is the
/// within-session autoregulation the week-level Coach's Call doesn't cover.
public struct NextSetCue: Sendable, Equatable {
    public enum Direction: Sendable { case up, hold, down }
    /// Short directive, e.g. "Add 5 lb" / "On target — hold".
    public let label: String
    /// Weight change to apply to the next set (lb); 0 for a hold.
    public let weightDeltaLb: Double
    public let direction: Direction

    public init(label: String, weightDeltaLb: Double, direction: Direction) {
        self.label = label
        self.weightDeltaLb = weightDeltaLb
        self.direction = direction
    }
}

/// Rule-based progression. Mirrors the coaching philosophy in the spec:
/// RAMP first (W1), RPE-driven progression (W2–4), deload (W5).
public enum CoachEngine {

    public static func call(week: Int, last: LastTopSet?, repRange: String, isCardio: Bool,
                            holdProgression: Bool = false, forceDeload: Bool = false) -> CoachsCall {
        if isCardio {
            return CoachsCall(headline: "Easy effort — a finisher, not a test.",
                              suggestedWeight: nil, suggestedReps: nil, emphasis: .neutral)
        }

        let lowReps = lowRep(of: repRange)

        // Early deload (readiness-triggered or manual) — treat this week like W5
        // regardless of where the calendar says you are.
        if forceDeload && week < 5 {
            let w = last.map { roundToStep($0.weight * 0.6, step: 5) }
            return CoachsCall(headline: "Early deload — ~60% load, leave 4–5 in reserve. Recover, don't grind.",
                              suggestedWeight: w,
                              suggestedReps: last?.reps ?? lowReps,
                              emphasis: .deload)
        }

        // Week 1 — intentional ramp.
        if week <= 1 {
            return CoachsCall(headline: "Ramp week — ease in, leave 3–4 reps in the tank.",
                              suggestedWeight: last?.weight,
                              suggestedReps: last?.reps ?? lowReps,
                              emphasis: .ramp)
        }

        // Week 5 — deload to ~60%.
        if week >= 5 {
            let w = last.map { roundToStep($0.weight * 0.6, step: 5) }
            return CoachsCall(headline: "Deload — ~60% load, leave 4–5 in reserve. Stay crisp, don't grind.",
                              suggestedWeight: w,
                              suggestedReps: last?.reps ?? lowReps,
                              emphasis: .deload)
        }

        // Weeks 2–4 — progress off last week's top set.
        guard let last else {
            return CoachsCall(headline: "No log last week — match your working weight and record it.",
                              suggestedWeight: nil, suggestedReps: lowReps, emphasis: .neutral)
        }

        // Under-recovered → don't add load today regardless of last week's effort.
        if holdProgression {
            return CoachsCall(headline: "Low readiness — hold \(fmt(last.weight)) lb today, don't add.",
                              suggestedWeight: last.weight, suggestedReps: last.reps, emphasis: .hold)
        }

        guard let rpe = last.rpe else {
            let w = roundToStep(last.weight + 5, step: 5)
            return CoachsCall(headline: "Last week \(fmt(last.weight))×\(last.reps) — add ~5 lb if it moved well.",
                              suggestedWeight: w, suggestedReps: last.reps, emphasis: .progress)
        }

        switch rpe {
        case ..<7.0001:
            // ≥3 reps in reserve → add load.
            let w = roundToStep(last.weight + 5, step: 5)
            return CoachsCall(headline: "Last week left \(repsLeftLabel(fromRPE: rpe)) in the tank — add 5 lb.",
                              suggestedWeight: w, suggestedReps: last.reps, emphasis: .progress)
        case ..<8.5001:
            // ~2 reps in reserve → on target, +5 lb or +1 rep.
            let w = roundToStep(last.weight + 5, step: 5)
            return CoachsCall(headline: "On target (\(repsLeftLabel(fromRPE: rpe)) left) — add 5 lb, or hold and add a rep.",
                              suggestedWeight: w, suggestedReps: last.reps, emphasis: .progress)
        default:
            // 0–1 reps in reserve → near max, hold the weight and chase a rep.
            return CoachsCall(headline: "Tough last week (\(repsLeftLabel(fromRPE: rpe)) left) — hold \(fmt(last.weight)) lb, chase +1 rep.",
                              suggestedWeight: last.weight, suggestedReps: last.reps + 1, emphasis: .hold)
        }
    }

    // MARK: Set-to-set autoregulation

    /// Per-set RPE targets parsed from a target string: "7→8→8" → [7, 8, 8];
    /// "8" → [8]; "9" → [9]. Empty for non-numeric targets (e.g. "easy").
    public static func rpeTargets(_ s: String) -> [Double] {
        var out: [Double] = []
        var token = ""
        func flush() { if let v = Double(token) { out.append(v) }; token = "" }
        for ch in s {
            if ch.isNumber || ch == "." { token.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    /// Target RPE for a 0-based set index, clamped to the last authored value
    /// (so "7→8→8" gives 7, 8, 8, 8, … and a single "8" applies to every set).
    public static func targetRPE(forSetIndex i: Int, in rpeTarget: String) -> Double? {
        let t = rpeTargets(rpeTarget)
        guard !t.isEmpty else { return nil }
        return t[min(max(0, i), t.count - 1)]
    }

    // MARK: Reps-in-reserve (the user-facing "reps left" scale = 10 − RPE)

    /// Short "reps left" label for an RPE: "0" (all-out) … "4+" (easy). The app
    /// speaks reps-left everywhere; RPE stays internal to the engine + storage.
    public static func repsLeftLabel(fromRPE rpe: Double) -> String {
        if rpe >= 10 { return "0" }
        if rpe <= 6  { return "4+" }
        return fmt(10 - rpe)
    }

    /// Converts an authored RPE target string to a reps-left target:
    /// "7→8→8" → "3→2→2", "8" → "2". Non-numeric targets (cardio "easy") pass through.
    public static func repsLeftTarget(from rpeTarget: String) -> String {
        let targets = rpeTargets(rpeTarget)
        guard !targets.isEmpty else { return rpeTarget }
        return targets.map { repsLeftLabel(fromRPE: $0) }.joined(separator: "→")
    }

    /// Cue for the NEXT set from the set you just logged. `gap` = target − logged;
    /// positive means it came in easier than planned (room to add load). Bigger jumps
    /// are reserved for compounds.
    public static func nextSetCue(loggedRPE: Double, targetRPE: Double?, isCompound: Bool,
                                  holdProgression: Bool = false) -> NextSetCue {
        let target = targetRPE ?? 8
        let gap = target - loggedRPE
        let cue: NextSetCue
        if gap >= 2.5 && isCompound {
            cue = NextSetCue(label: "Easy — add 10 lb", weightDeltaLb: 10, direction: .up)
        } else if gap >= 1.0 {
            cue = NextSetCue(label: "Add 5 lb", weightDeltaLb: 5, direction: .up)
        } else if gap >= -0.5 {
            cue = NextSetCue(label: "On target — hold", weightDeltaLb: 0, direction: .hold)
        } else if loggedRPE >= 9.5 {
            cue = NextSetCue(label: "Heavy — drop 5 lb", weightDeltaLb: -5, direction: .down)
        } else {
            cue = NextSetCue(label: "Tough — hold", weightDeltaLb: 0, direction: .hold)
        }
        // Under-recovered → never chase more load, even if the set felt easy.
        if holdProgression, cue.direction == .up {
            return NextSetCue(label: "Under-recovered — hold", weightDeltaLb: 0, direction: .hold)
        }
        return cue
    }

    // MARK: Helpers

    /// Parses the low end of a rep range string: "5-7"→5, "10/leg"→10, "15"→15, "10 min"→10.
    public static func lowRep(of repRange: String) -> Int {
        var digits = ""
        for ch in repRange {
            if ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        return Int(digits) ?? 0
    }

    public static func roundToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Formats a number without a trailing ".0" (e.g. 135.0 → "135", 7.5 → "7.5").
    public static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
