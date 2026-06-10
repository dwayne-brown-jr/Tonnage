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

/// The default program's sessions. Kept as a thin alias over `SplitPreset.upperLower`
/// so existing callers (seed, tests) are unaffected by the multi-split refactor.
public enum SeedProgram {
    public static func makeSessions() -> [SessionTemplate] {
        SplitPreset.upperLower.makeSessions()
    }
}
