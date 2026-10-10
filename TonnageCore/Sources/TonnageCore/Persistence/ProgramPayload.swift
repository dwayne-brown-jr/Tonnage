import Foundation
import SwiftData

/// Codable snapshot of the program's session templates, sent phone → watch so the watch
/// runs the same sessions as the phone (after a split change or an AI plan), not its own
/// seeded defaults.
public struct ProgramPayload: Codable, Sendable, Equatable {

    public struct Exercise: Codable, Sendable, Equatable {
        public var name: String
        public var prescribedSets: Int
        public var repRange: String
        public var rpeTarget: String
        public var notes: String
        public var isCompound: Bool
        public var isCardio: Bool
        public var supersetWithNext: Bool

        public init(name: String, prescribedSets: Int, repRange: String, rpeTarget: String,
                    notes: String = "", isCompound: Bool = false, isCardio: Bool = false,
                    supersetWithNext: Bool = false) {
            self.name = name; self.prescribedSets = prescribedSets; self.repRange = repRange
            self.rpeTarget = rpeTarget; self.notes = notes; self.isCompound = isCompound
            self.isCardio = isCardio; self.supersetWithNext = supersetWithNext
        }
    }

    public struct Session: Codable, Sendable, Equatable {
        public var name: String
        public var subtitle: String
        public var exercises: [Exercise]

        public init(name: String, subtitle: String, exercises: [Exercise]) {
            self.name = name; self.subtitle = subtitle; self.exercises = exercises
        }
    }

    public var name: String
    public var sessions: [Session]

    public init(name: String, sessions: [Session]) {
        self.name = name
        self.sessions = sessions
    }

    @MainActor
    public init(from program: Program) {
        self.init(name: program.name, sessions: program.orderedSessions.map { s in
            Session(name: s.name, subtitle: s.subtitle, exercises: s.orderedExercises.map { e in
                Exercise(name: e.name, prescribedSets: e.prescribedSets, repRange: e.repRange,
                         rpeTarget: e.rpeTarget, notes: e.notes, isCompound: e.isCompound,
                         isCardio: e.isCardio, supersetWithNext: e.supersetWithNext)
            })
        })
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(from data: Data) -> ProgramPayload? { try? JSONDecoder().decode(Self.self, from: data) }
}

/// Rewrites the store's program to match `payload`. For the WATCH's local store, which
/// only mirrors the phone: the phone's program is the source of truth. No-op (returns
/// false) when the program already matches or the payload is empty.
@MainActor
@discardableResult
public func applyProgramPayload(_ payload: ProgramPayload, to context: ModelContext) -> Bool {
    guard !payload.sessions.isEmpty else { return false }
    let program: Program
    if let existing = try? context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt)])).first {
        guard ProgramPayload(from: existing) != payload else { return false }
        program = existing
    } else {
        program = Program(name: payload.name)
        context.insert(program)
    }

    program.name = payload.name
    for old in program.orderedSessions { context.delete(old) }   // cascades to exercise templates
    for (i, s) in payload.sessions.enumerated() {
        let session = SessionTemplate(name: s.name, subtitle: s.subtitle, sortOrder: i)
        session.program = program
        context.insert(session)
        for (j, e) in s.exercises.enumerated() {
            let t = ExerciseTemplate(name: e.name, prescribedSets: e.prescribedSets, repRange: e.repRange,
                                     rpeTarget: e.rpeTarget, notes: e.notes, isCompound: e.isCompound,
                                     isCardio: e.isCardio, sortOrder: j)
            t.supersetWithNext = e.supersetWithNext
            t.session = session
            context.insert(t)
        }
    }
    do {
        try context.save()
        return true
    } catch {
        context.rollback()
        return false
    }
}
