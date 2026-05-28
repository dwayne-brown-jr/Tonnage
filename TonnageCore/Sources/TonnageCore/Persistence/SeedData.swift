import Foundation
import SwiftData

/// Seeds the database with the Block 01 program on first launch (idempotent).
@MainActor
public func seedIfNeeded(_ context: ModelContext) {
    let existing = (try? context.fetchCount(FetchDescriptor<Program>())) ?? 0
    guard existing == 0 else { return }

    let program = Program(name: "Block 01 / Recomp")
    program.sessions = SeedProgram.makeSessions()
    context.insert(program)
    try? context.save()
}

/// Builds the Block 01 session templates. Pure data — no persistence side effects.
enum SeedProgram {

    /// Small builder so the seed reads like the program sheet.
    private static func ex(
        _ order: Int,
        _ name: String,
        sets: Int,
        reps: String,
        rpe: String,
        compound: Bool = false,
        cardio: Bool = false,
        notes: String = ""
    ) -> ExerciseTemplate {
        ExerciseTemplate(
            name: name,
            prescribedSets: sets,
            repRange: reps,
            rpeTarget: rpe,
            notes: notes,
            isCompound: compound,
            isCardio: cardio,
            sortOrder: order
        )
    }

    static func makeSessions() -> [SessionTemplate] {
        [upperA(), lowerA(), upperB(), lowerB()]
    }

    // MARK: UPPER A — Push focus
    private static func upperA() -> SessionTemplate {
        SessionTemplate(name: "Upper A", subtitle: "Push focus", sortOrder: 0, exercises: [
            ex(0, "Barbell Bench Press", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true,
               notes: "Ramp up, last set is your top set"),
            ex(1, "Seated Shoulder Press", sets: 3, reps: "8-10", rpe: "8", compound: true,
               notes: "Machine or DB"),
            ex(2, "Chest-Supported Row", sets: 3, reps: "10-12", rpe: "8", compound: true,
               notes: "Squeeze, slow eccentric"),
            ex(3, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8", notes: "Wide grip"),
            ex(4, "Cable Triceps Pushdown", sets: 2, reps: "12-15", rpe: "9"),
            ex(5, "DB Incline Curl", sets: 2, reps: "10-12", rpe: "9"),
            ex(6, "Stair Master (finisher)", sets: 1, reps: "10 min", rpe: "easy", cardio: true,
               notes: "Optional")
        ])
    }

    // MARK: LOWER A — Squat focus
    private static func lowerA() -> SessionTemplate {
        SessionTemplate(name: "Lower A", subtitle: "Squat focus", sortOrder: 1, exercises: [
            ex(0, "Barbell Back Squat", sets: 3, reps: "5-7", rpe: "7→8→8", compound: true,
               notes: "Log top set"),
            ex(1, "Romanian Deadlift", sets: 3, reps: "8-10", rpe: "8", compound: true,
               notes: "Hinge, neutral spine"),
            ex(2, "Walking DB Lunges", sets: 2, reps: "10/leg", rpe: "8"),
            ex(3, "Leg Curl", sets: 2, reps: "12-15", rpe: "9", notes: "Or DB RDL if no machine"),
            ex(4, "Standing Calf Raise", sets: 3, reps: "12-15", rpe: "9",
               notes: "Full stretch, pause top"),
            ex(5, "Hanging Knee Raise", sets: 3, reps: "12-15", rpe: "8", notes: "Or cable crunch")
        ])
    }

    // MARK: UPPER B — Pull focus
    private static func upperB() -> SessionTemplate {
        SessionTemplate(name: "Upper B", subtitle: "Pull focus", sortOrder: 2, exercises: [
            ex(0, "Barbell Row", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true,
               notes: "Log top set. Or chest-supported row."),
            ex(1, "Incline DB Press", sets: 3, reps: "8-10", rpe: "8", compound: true),
            ex(2, "Cable Lat Pulldown", sets: 3, reps: "10-12", rpe: "8", notes: "Close grip"),
            ex(3, "DB Lateral Raise", sets: 3, reps: "12-15", rpe: "9", notes: "Light, strict, slow"),
            ex(4, "Cable Face Pull", sets: 2, reps: "15", rpe: "8", notes: "Rear delts + upper back"),
            ex(5, "EZ-bar or DB Curl", sets: 2, reps: "10-12", rpe: "9"),
            ex(6, "Bike intervals (finisher)", sets: 1, reps: "10 min", rpe: "moderate", cardio: true,
               notes: "30s hard / 60s easy")
        ])
    }

    // MARK: LOWER B — Hinge focus
    private static func lowerB() -> SessionTemplate {
        SessionTemplate(name: "Lower B", subtitle: "Hinge focus", sortOrder: 3, exercises: [
            ex(0, "Romanian Deadlift", sets: 3, reps: "6-8", rpe: "7→8→8", compound: true,
               notes: "DB or barbell. Log top set."),
            ex(1, "Front Squat / Goblet Squat", sets: 3, reps: "8-10", rpe: "8", compound: true,
               notes: "Heavy DB OK"),
            ex(2, "Bulgarian Split Squat", sets: 2, reps: "10/leg", rpe: "8"),
            ex(3, "Cable Pull-Through", sets: 3, reps: "12-15", rpe: "8",
               notes: "Or hip thrust. Glute focus."),
            ex(4, "Seated Calf Raise", sets: 3, reps: "12-15", rpe: "9"),
            ex(5, "Cable Wood Chop / Pallof", sets: 3, reps: "10/side", rpe: "8",
               notes: "Anti-rotation")
        ])
    }
}
