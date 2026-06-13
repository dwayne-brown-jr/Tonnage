import Foundation
import SwiftData

/// Seeds the database with the default program on first launch (idempotent).
@MainActor
public func seedIfNeeded(_ context: ModelContext) {
    let existing = (try? context.fetchCount(FetchDescriptor<Program>())) ?? 0
    guard existing == 0 else { return }

    let program = Program(name: "Block 01 / Recomp")
    program.sessions = SeedProgram.makeSessions()
    context.insert(program)
    context.saveOrReport()
}

/// Rewrites a program's sessions to match a chosen split. Past logged workouts are kept
/// (their template links nullify); only the future plan changes. Used by the onboarding
/// split picker and the "change split" flow in Settings.
@MainActor
public func applySplit(_ preset: SplitPreset, to program: Program, in context: ModelContext) {
    for old in program.orderedSessions { context.delete(old) }   // cascade-deletes its exercises
    for session in preset.makeSessions() {
        session.program = program
        context.insert(session)
    }
    context.saveOrReport()
}

/// Heals any session TEMPLATE that ended up with no exercises — e.g. a program built by an older
/// version, or a partial CloudKit sync where a session's exercises didn't arrive. Re-populates each
/// empty session from the matching session of the user's chosen split (matched by sort order, then
/// name). Idempotent and additive: only touches empty sessions, only inserts exercises, never
/// deletes — so it can run safely on every launch. Returns how many sessions it repaired.
@MainActor
@discardableResult
public func repairEmptySessions(_ context: ModelContext, split: SplitPreset) -> Int {
    guard let program = try? context.fetch(FetchDescriptor<Program>()).first else { return 0 }
    let empties = program.orderedSessions.filter { ($0.exercises ?? []).isEmpty }
    guard !empties.isEmpty else { return 0 }

    let template = split.makeSessions()
    var repaired = 0
    for session in empties {
        guard let source = template.first(where: { $0.sortOrder == session.sortOrder })
                            ?? template.first(where: { $0.name == session.name }) else { continue }
        for e in source.orderedExercises {
            // Fresh copies attached to the EXISTING session (the `template` ones are never
            // inserted, so they're discarded — no relationship tangles).
            let copy = ExerciseTemplate(name: e.name, prescribedSets: e.prescribedSets,
                                        repRange: e.repRange, rpeTarget: e.rpeTarget, notes: e.notes,
                                        isCompound: e.isCompound, isCardio: e.isCardio, sortOrder: e.sortOrder)
            copy.session = session
            context.insert(copy)
        }
        repaired += 1
    }
    if repaired > 0 { context.saveOrReport() }
    return repaired
}

/// The default program's sessions. Kept as a thin alias over `SplitPreset.upperLower`
/// so existing callers (seed, tests) are unaffected by the multi-split refactor.
public enum SeedProgram {
    public static func makeSessions() -> [SessionTemplate] {
        SplitPreset.upperLower.makeSessions()
    }
}
