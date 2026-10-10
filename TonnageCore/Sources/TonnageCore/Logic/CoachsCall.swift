import Foundation

/// A prior top set used as the basis for this week's recommendation.
public struct LastTopSet: Sendable, Equatable {
    public let weight: Double
    public let reps: Int
    public let rpe: Double?
    /// The day this set was logged. Without it the engine can't tell a set from last week
    /// apart from one from last spring, and would hand a returning lifter pre-layoff loads.
    public let date: Date?

    public init(weight: Double, reps: Int, rpe: Double?, date: Date? = nil) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.date = date
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

    /// `load` decides jump sizes and the lightest loadable weight (the empty bar for
    /// barbells); `.standard` keeps flat 5 lb jumps. A top set at 0 lb is a bodyweight
    /// set and progresses reps, not load. Reps follow double progression: they climb
    /// toward the top of `repRange`, and once a set reaches it the call adds load and
    /// resets to the bottom.
    public static func call(week: Int, last: LastTopSet?, repRange: String, isCardio: Bool,
                            isTimed: Bool = false, load: LoadProfile = .standard,
                            holdProgression: Bool = false, forceDeload: Bool = false,
                            layoff: Layoff? = nil) -> CoachsCall {
        if isCardio {
            return CoachsCall(headline: "Easy effort — a finisher, not a test.",
                              suggestedWeight: nil, suggestedReps: nil, emphasis: .neutral)
        }
        if isTimed {
            return CoachsCall(headline: "Timed hold — add 5–10 s once the last one felt solid.",
                              suggestedWeight: nil, suggestedReps: nil, emphasis: .neutral)
        }

        let lowReps = lowRep(of: repRange)
        let topReps = highRep(of: repRange)
        /// Keeps a carried-over rep count inside the prescribed range.
        func inRange(_ reps: Int) -> Int {
            guard lowReps > 0, let topReps else { return reps }
            return min(max(reps, lowReps), topReps)
        }
        /// A reduced load (deload, layoff), rounded to something loadable.
        func scaled(_ weight: Double, by fraction: Double) -> Double {
            weight > 0 ? load.rounded(weight * fraction) : 0
        }
        /// Bodyweight sets have no load to cut, so a deload trims reps instead.
        func deloadReps(_ last: LastTopSet) -> Int {
            last.weight > 0 ? inRange(last.reps) : max(1, Int((Double(last.reps) * 0.6).rounded()))
        }

        // Coming back from real time off overrides the week's normal progression — the last
        // top set is stale, so where you are in the block matters less than how long you've
        // been gone. Scales the load rather than discarding it, and never suggests more than
        // an explicit deload would.
        if let layoff, layoff.isSignificant, let last {
            let multiplier = forceDeload ? min(layoff.loadMultiplier, 0.6) : layoff.loadMultiplier
            let w = scaled(last.weight, by: multiplier)
            let start = last.weight > 0 ? "start near \(fmt(w)) lb (~\(Int((multiplier * 100).rounded()))%)"
                                         : "start with ~\(Int((multiplier * 100).rounded()))% of your reps"
            let reps = last.weight > 0 ? inRange(last.reps) : max(1, Int((Double(last.reps) * multiplier).rounded()))
            return CoachsCall(
                headline: "Back after \(layoff.summary) — \(start) and rebuild.",
                suggestedWeight: w,
                suggestedReps: reps,
                emphasis: .deload)
        }

        // Early deload (readiness-triggered or manual) — treat this week like W5
        // regardless of where the calendar says you are.
        if forceDeload && week < 5 {
            let w = last.map { scaled($0.weight, by: 0.6) }
            return CoachsCall(headline: "Early deload — ~60% load, leave 4–5 in reserve. Recover, don't grind.",
                              suggestedWeight: w,
                              suggestedReps: last.map(deloadReps) ?? lowReps,
                              emphasis: .deload)
        }

        // Week 1 — intentional ramp.
        if week <= 1 {
            return CoachsCall(headline: "Ramp week — ease in, leave 3–4 reps in the tank.",
                              suggestedWeight: last?.weight,
                              suggestedReps: last.map { inRange($0.reps) } ?? lowReps,
                              emphasis: .ramp)
        }

        // Week 5 — deload to ~60%.
        if week >= 5 {
            let w = last.map { scaled($0.weight, by: 0.6) }
            return CoachsCall(headline: "Deload — ~60% load, leave 4–5 in reserve. Stay crisp, don't grind.",
                              suggestedWeight: w,
                              suggestedReps: last.map(deloadReps) ?? lowReps,
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

        // Bodyweight (logged at 0 lb) — progress reps. At the top of the range the next
        // step is load or a harder variation, which is the lifter's call, not a number.
        if last.weight <= 0 {
            if let topReps, last.reps >= topReps {
                return CoachsCall(headline: "Top of the range at \(last.reps) — add load (belt or vest) or a harder variation.",
                                  suggestedWeight: 0, suggestedReps: topReps, emphasis: .progress)
            }
            if let rpe = last.rpe, rpe >= 9.5 {
                return CoachsCall(headline: "All-out last week — match \(last.reps) reps with cleaner form.",
                                  suggestedWeight: 0, suggestedReps: last.reps, emphasis: .hold)
            }
            let reps = topReps.map { min(last.reps + 1, $0) } ?? last.reps + 1
            return CoachsCall(headline: "Bodyweight — add a rep: aim for \(reps).",
                              suggestedWeight: 0, suggestedReps: reps, emphasis: .progress)
        }

        let step = fmt(load.increment(from: last.weight))
        let heavier = load.nextWeight(after: last.weight)
        // Double progression: reaching the top of the range earns load and resets reps.
        if let topReps, lowReps > 0, last.reps >= topReps {
            return CoachsCall(headline: "Topped the range at \(last.reps) reps — add \(step) lb, reset to \(lowReps).",
                              suggestedWeight: heavier, suggestedReps: lowReps, emphasis: .progress)
        }

        guard let rpe = last.rpe else {
            return CoachsCall(headline: "Last week \(fmt(last.weight))×\(last.reps) — add ~\(step) lb if it moved well.",
                              suggestedWeight: heavier, suggestedReps: inRange(last.reps), emphasis: .progress)
        }

        switch rpe {
        case ..<7.0001:
            // ≥3 reps in reserve → add load.
            return CoachsCall(headline: "Last week left \(repsLeftLabel(fromRPE: rpe)) in the tank — add \(step) lb.",
                              suggestedWeight: heavier, suggestedReps: inRange(last.reps), emphasis: .progress)
        case ..<8.5001:
            // ~2 reps in reserve → on target, add load or a rep.
            return CoachsCall(headline: "On target (\(repsLeftLabel(fromRPE: rpe)) left) — add \(step) lb, or hold and add a rep.",
                              suggestedWeight: heavier, suggestedReps: inRange(last.reps), emphasis: .progress)
        default:
            // 0–1 reps in reserve → near max, hold the weight and chase a rep (never past
            // the top of the range — the branch above handles reaching it).
            let reps = topReps.map { min(last.reps + 1, $0) } ?? last.reps + 1
            return CoachsCall(headline: "Tough last week (\(repsLeftLabel(fromRPE: rpe)) left) — hold \(fmt(last.weight)) lb, chase +1 rep.",
                              suggestedWeight: last.weight, suggestedReps: reps, emphasis: .hold)
        }
    }

    // MARK: Set-to-set autoregulation

    /// The range an RPE target can sensibly take. Anything outside it (an AI plan's "12",
    /// a typo'd "80") is clamped, so it can't drive the set-to-set cue off a cliff.
    public static let rpeTargetRange: ClosedRange<Double> = 5...10

    /// Per-set RPE targets parsed from a target string: "7→8→8" → [7, 8, 8];
    /// "8" → [8]; "9" → [9]. Empty for non-numeric targets (e.g. "easy"). Each value is
    /// clamped to `rpeTargetRange`.
    public static func rpeTargets(_ s: String) -> [Double] {
        var out: [Double] = []
        var token = ""
        func flush() {
            if let v = Double(token) { out.append(min(max(v, rpeTargetRange.lowerBound), rpeTargetRange.upperBound)) }
            token = ""
        }
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
    /// are reserved for compounds. `increment` is one load step for this lift (5 lb by
    /// default, 2.5 for small lifts); a bodyweight set cues reps instead of load.
    public static func nextSetCue(loggedRPE: Double, targetRPE: Double?, isCompound: Bool,
                                  holdProgression: Bool = false, increment: Double = 5,
                                  isBodyweight: Bool = false) -> NextSetCue {
        let target = min(max(targetRPE ?? 8, rpeTargetRange.lowerBound), rpeTargetRange.upperBound)
        let gap = target - loggedRPE
        let cue: NextSetCue
        if isBodyweight {
            if gap >= 1.0 {
                cue = NextSetCue(label: "Easy — add a rep", weightDeltaLb: 0, direction: .up)
            } else if gap >= -0.5 {
                cue = NextSetCue(label: "On target — hold", weightDeltaLb: 0, direction: .hold)
            } else if loggedRPE >= 9.5 {
                cue = NextSetCue(label: "Heavy — drop a rep", weightDeltaLb: 0, direction: .down)
            } else {
                cue = NextSetCue(label: "Tough — hold", weightDeltaLb: 0, direction: .hold)
            }
        } else if gap >= 2.5 && isCompound {
            cue = NextSetCue(label: "Easy — add \(fmt(increment * 2)) lb", weightDeltaLb: increment * 2, direction: .up)
        } else if gap >= 1.0 {
            cue = NextSetCue(label: "Add \(fmt(increment)) lb", weightDeltaLb: increment, direction: .up)
        } else if gap >= -0.5 {
            cue = NextSetCue(label: "On target — hold", weightDeltaLb: 0, direction: .hold)
        } else if loggedRPE >= 9.5 {
            cue = NextSetCue(label: "Heavy — drop \(fmt(increment)) lb", weightDeltaLb: -increment, direction: .down)
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

    /// Parses the top of a rep range: "5-7"→7, "8–12"→12, "15"→15, "10/leg"→10.
    /// Nil when there's no number to read.
    public static func highRep(of repRange: String) -> Int? {
        if let m = repRange.firstMatch(of: /(\d+)\s*(?:-|–|—|to)\s*(\d+)/),
           let a = Int(m.1), let b = Int(m.2) {
            return max(a, b)
        }
        return repRange.firstMatch(of: /\d+/).flatMap { Int($0.0) }
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
