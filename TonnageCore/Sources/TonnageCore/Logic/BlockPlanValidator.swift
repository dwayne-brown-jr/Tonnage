import Foundation

/// Checks an AI-written block plan before anyone sees it. Small problems are repaired and
/// listed (sets clamped to 1–10, RPE clamped to 5–10, a reversed rep range flipped, a
/// duplicate session or exercise dropped). Problems that can't be fixed without guessing
/// reject the plan with a reason the user can read.
public enum BlockPlanValidator {

    public static let setRange = 1...10
    public static let exercisesPerSession = 3...8

    public enum Outcome: Equatable, Sendable {
        /// Safe to show. `fixes` lists what was changed, empty when nothing was.
        case ok(BlockPlan, fixes: [String])
        case rejected(String)
    }

    public static func validate(_ plan: BlockPlan) -> Outcome {
        var fixes: [String] = []
        var sessions: [SessionPlan] = []
        var seenSessions = Set<String>()

        for session in plan.sessions {
            let name = PromptSafety.sanitized(session.name, limit: PromptSafety.maxNameLength)
            guard !name.isEmpty else {
                fixes.append("Dropped a session with no name.")
                continue
            }
            guard seenSessions.insert(name.lowercased()).inserted else {
                fixes.append("Dropped a second session named \(name).")
                continue
            }

            var exercises: [ExercisePlan] = []
            var seenExercises = Set<String>()
            for ex in session.exercises {
                let exName = PromptSafety.sanitized(ex.name, limit: PromptSafety.maxNameLength)
                guard !exName.isEmpty else {
                    fixes.append("\(name): dropped an exercise with no name.")
                    continue
                }
                guard seenExercises.insert(exName.lowercased()).inserted else {
                    fixes.append("\(name): dropped a repeat of \(exName).")
                    continue
                }
                switch check(ex, named: exName, in: name) {
                case .keep(let fixed, let notes):
                    exercises.append(fixed)
                    fixes.append(contentsOf: notes)
                case .drop(let reason):
                    fixes.append(reason)
                }
            }

            if exercises.count > exercisesPerSession.upperBound {
                fixes.append("\(name): trimmed to \(exercisesPerSession.upperBound) exercises (the plan had \(exercises.count)).")
                exercises = Array(exercises.prefix(exercisesPerSession.upperBound))
            }
            guard exercises.count >= exercisesPerSession.lowerBound else {
                return .rejected("\(name) came back with only \(exercises.count) usable exercise\(exercises.count == 1 ? "" : "s"). A session needs at least \(exercisesPerSession.lowerBound).")
            }
            sessions.append(SessionPlan(name: name,
                                        subtitle: PromptSafety.sanitized(session.subtitle, limit: PromptSafety.maxNameLength),
                                        exercises: exercises))
        }

        guard !sessions.isEmpty else { return .rejected("The plan had no usable sessions.") }
        let cleaned = BlockPlan(blockNumber: plan.blockNumber,
                                theme: PromptSafety.sanitized(plan.theme, limit: PromptSafety.maxNameLength),
                                summary: PromptSafety.sanitized(plan.summary, limit: 400),
                                sessions: sessions)
        return .ok(cleaned, fixes: fixes)
    }

    private enum ExerciseCheck {
        case keep(ExercisePlan, [String])
        case drop(String)
    }

    private static func check(_ ex: ExercisePlan, named name: String, in session: String) -> ExerciseCheck {
        var notes: [String] = []

        var sets = ex.prescribedSets
        if !setRange.contains(sets) {
            sets = min(max(sets, setRange.lowerBound), setRange.upperBound)
            notes.append("\(session): \(name) set to \(sets) sets (the plan said \(ex.prescribedSets)).")
        }

        var repRange = ex.repRange.trimmingCharacters(in: .whitespacesAndNewlines)
        var rpeTarget = ex.rpeTarget.trimmingCharacters(in: .whitespacesAndNewlines)

        if !ex.isCardio {
            guard CoachEngine.lowRep(of: repRange) > 0, let high = CoachEngine.highRep(of: repRange), high <= 100 else {
                return .drop("\(session): dropped \(name) — its rep range \"\(PromptSafety.sanitized(repRange, limit: 20))\" doesn't parse.")
            }
            if let m = repRange.firstMatch(of: /(\d+)\s*(?:-|–|—|to)\s*(\d+)/),
               let a = Int(m.1), let b = Int(m.2), a > b {
                repRange = "\(b)-\(a)"
                notes.append("\(session): \(name) rep range flipped to \(repRange).")
            }

            let raw = rawRPEValues(rpeTarget)
            if raw.isEmpty {
                rpeTarget = "8"
                notes.append("\(session): \(name) had no usable RPE target; set to 8.")
            } else if raw.contains(where: { !CoachEngine.rpeTargetRange.contains($0) }) {
                rpeTarget = CoachEngine.rpeTargets(rpeTarget).map(CoachEngine.fmt).joined(separator: "→")
                notes.append("\(session): \(name) RPE target clamped to \(rpeTarget).")
            }
        }

        let fixed = ExercisePlan(name: name,
                                 prescribedSets: sets,
                                 repRange: PromptSafety.sanitized(repRange, limit: 30),
                                 rpeTarget: PromptSafety.sanitized(rpeTarget, limit: 30),
                                 notes: PromptSafety.sanitized(ex.notes),
                                 isCompound: ex.isCompound,
                                 isCardio: ex.isCardio,
                                 rationale: PromptSafety.sanitized(ex.rationale),
                                 change: ex.change)
        return .keep(fixed, notes)
    }

    /// RPE numbers as written, before clamping.
    private static func rawRPEValues(_ s: String) -> [Double] {
        s.matches(of: /\d+(?:\.\d+)?/).compactMap { Double($0.0) }
    }
}
