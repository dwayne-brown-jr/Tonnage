import Foundation

/// A single loggable metric for a set. Strength uses weight/reps/rpe; cardio uses
/// some combination of time/distance/flights depending on the movement.
public enum SetMetric: String, Sendable, CaseIterable, Identifiable {
    case weight, reps, rpe, time, distance, flights
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .weight:   "lb"
        case .reps:     "reps"
        case .rpe:      "RPE"
        case .time:     "time"
        case .distance: "mi"
        case .flights:  "flights"
        }
    }
}

/// How-to directions for a movement, shown in the per-exercise info sheet.
public struct ExerciseDirections: Sendable, Equatable {
    public let summary: String
    public let targets: String
    public let steps: [String]

    public init(summary: String, targets: String, steps: [String]) {
        self.summary = summary
        self.targets = targets
        self.steps = steps
    }
}

/// Knows which metrics each movement logs and how to perform it. Inference is
/// name-based so it also works for ad-hoc / custom exercises.
public enum ExerciseLibrary {

    /// Which metrics to log for an exercise. Strength → weight/reps/rpe.
    /// Cardio → inferred from the movement (stairs → flights+time, bike → time+distance, …).
    public static func metrics(for name: String, isCardio: Bool) -> [SetMetric] {
        guard isCardio else { return [.weight, .reps, .rpe] }
        let n = name.lowercased()
        if n.contains("stair") || n.contains("stadium") || n.contains("step mill") {
            return [.flights, .time]
        }
        if n.contains("bike") || n.contains("cycle") || n.contains("spin") || n.contains("assault") || n.contains("echo") {
            return [.time, .distance]
        }
        if n.contains("walk") || n.contains("run") || n.contains("treadmill") || n.contains("jog") || n.contains("ruck") || n.contains("vest") {
            return [.distance, .time]
        }
        if n.contains("row") || n.contains("erg") || n.contains("swim") {
            return [.distance, .time]
        }
        return [.time]
    }

    public static func directions(for name: String) -> ExerciseDirections? {
        catalog[normalize(name)]
    }

    /// Lowercase, drop any "(…)" suffix like "(finisher)", trim.
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")") {
            s.removeSubrange(open...close)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let catalog: [String: ExerciseDirections] = [
        "barbell bench press": .init(
            summary: "Flat barbell press — your main upper-body push.",
            targets: "Chest · front delts · triceps",
            steps: [
                "Lie back with eyes under the bar, feet planted, shoulder blades pinched down and back.",
                "Grip just outside shoulder width; unrack to a locked-out arm over your chest.",
                "Lower under control to mid-chest, elbows about 45° from your torso.",
                "Press up and slightly back to lockout — keep the bar over your shoulders."
            ]),
        "seated shoulder press": .init(
            summary: "Vertical press for overhead strength.",
            targets: "Shoulders · triceps",
            steps: [
                "Set the seat so the handles/bar start around chin height.",
                "Back flat against the pad, feet flat, ribs down.",
                "Press straight overhead without flaring the ribcage.",
                "Lower under control until elbows are just below 90°."
            ]),
        "chest-supported row": .init(
            summary: "Strict horizontal pull with the chest braced.",
            targets: "Mid-back · lats · rear delts",
            steps: [
                "Set the chest pad so your sternum is supported and arms hang free.",
                "Take a neutral or pronated grip, arms long.",
                "Row by driving the elbows back and squeezing the shoulder blades together.",
                "Pause, then lower slowly to a full stretch (slow eccentric)."
            ]),
        "cable lat pulldown": .init(
            summary: "Vertical pull for lat width.",
            targets: "Lats · biceps",
            steps: [
                "Lock the thigh pad; grip the bar (wide or close as prescribed).",
                "Start with arms fully extended and a slight lean back.",
                "Pull the bar to your upper chest by driving the elbows down.",
                "Control the bar back up to a full overhead stretch."
            ]),
        "cable triceps pushdown": .init(
            summary: "Elbow-extension isolation for the triceps.",
            targets: "Triceps",
            steps: [
                "Stand tall at a high pulley, elbows pinned to your sides.",
                "Push the handle down to full lockout.",
                "Squeeze the triceps; don't let the elbows drift forward.",
                "Return slowly to about 90° without losing tension."
            ]),
        "db incline curl": .init(
            summary: "Stretch-biased biceps curl.",
            targets: "Biceps (long head)",
            steps: [
                "Set an incline bench ~45–60°; sit back with arms hanging straight down.",
                "Curl the dumbbells without moving your upper arms.",
                "Supinate (turn pinkies up) near the top.",
                "Lower slowly to a full stretch."
            ]),
        "stair master": .init(
            summary: "Steady-state stair climbing — easy conditioning.",
            targets: "Cardio · legs",
            steps: [
                "Set an easy, steady pace you can hold for the whole block.",
                "Stand tall; a light hand on the rail for balance only — don't lean.",
                "Drive through the whole foot, don't tiptoe.",
                "Keep it conversational — this is recovery work, not a sprint."
            ]),
        "barbell back squat": .init(
            summary: "The primary lower-body strength lift.",
            targets: "Quads · glutes · whole body",
            steps: [
                "Bar on your upper traps, hands tight, big breath, brace your core.",
                "Unrack, step back, feet ~shoulder width, toes slightly out.",
                "Sit down and back, knees tracking over toes, to at least parallel.",
                "Drive through mid-foot back to standing, staying braced."
            ]),
        "romanian deadlift": .init(
            summary: "Hip hinge for the posterior chain.",
            targets: "Hamstrings · glutes · low back",
            steps: [
                "Stand tall with the bar/DBs at your thighs, knees soft.",
                "Push your hips back, keeping the weight close to your legs.",
                "Lower until you feel a hamstring stretch — keep a neutral spine.",
                "Drive the hips forward to stand tall and squeeze the glutes."
            ]),
        "walking db lunges": .init(
            summary: "Loaded single-leg pattern, moving forward.",
            targets: "Quads · glutes",
            steps: [
                "Hold dumbbells at your sides, stand tall.",
                "Step forward into a lunge — both knees bend to about 90°.",
                "Push off the front foot and step straight into the next rep.",
                "Keep your torso tall and core braced throughout."
            ]),
        "leg curl": .init(
            summary: "Knee-flexion isolation for the hamstrings.",
            targets: "Hamstrings",
            steps: [
                "Set the pad to rest just above your heels.",
                "Curl your heels toward your glutes.",
                "Squeeze hard at the top.",
                "Lower slowly to a full stretch."
            ]),
        "standing calf raise": .init(
            summary: "Straight-leg calf raise for the gastrocnemius.",
            targets: "Calves (gastrocnemius)",
            steps: [
                "Balls of feet on the platform, legs straight.",
                "Drop the heels for a full stretch.",
                "Press up onto your toes as high as possible.",
                "Pause at the top, then lower slowly."
            ]),
        "hanging knee raise": .init(
            summary: "Hanging core flexion for the abs.",
            targets: "Abs · hip flexors",
            steps: [
                "Hang from a bar with active (not slack) shoulders.",
                "Raise your knees toward your chest by curling the pelvis up.",
                "Don't swing — control the movement.",
                "Lower slowly to a dead hang."
            ]),
        "barbell row": .init(
            summary: "Bent-over horizontal pull for the back.",
            targets: "Mid-back · lats · rear delts",
            steps: [
                "Hinge at the hips to ~45°, neutral spine, bar hanging.",
                "Pull the bar to your lower ribs / upper abdomen.",
                "Drive the elbows back and squeeze the shoulder blades.",
                "Lower under control; keep the torso angle fixed."
            ]),
        "incline db press": .init(
            summary: "Upper-chest biased dumbbell press.",
            targets: "Upper chest · front delts · triceps",
            steps: [
                "Set the bench to ~30°.",
                "Start with dumbbells at upper-chest level, elbows ~45°.",
                "Press up and slightly together to lockout.",
                "Lower under control to a stretch."
            ]),
        "db lateral raise": .init(
            summary: "Isolation for shoulder width.",
            targets: "Side delts",
            steps: [
                "Stand with a slight forward lean, dumbbells at your sides.",
                "Raise out to the sides to shoulder height, leading with the elbows.",
                "Keep a soft elbow; don't shrug the traps.",
                "Lower slowly — light weight, strict form."
            ]),
        "cable face pull": .init(
            summary: "Rear-delt and upper-back health movement.",
            targets: "Rear delts · upper back",
            steps: [
                "Set the pulley to head height with a rope.",
                "Pull toward your face, splitting the rope apart.",
                "Drive the elbows high and back; squeeze the rear delts.",
                "Return under control."
            ]),
        "ez-bar or db curl": .init(
            summary: "Standing biceps curl.",
            targets: "Biceps",
            steps: [
                "Stand tall, elbows pinned at your sides.",
                "Curl the bar/dumbbells without swinging.",
                "Squeeze at the top.",
                "Lower slowly to full extension."
            ]),
        "bike intervals": .init(
            summary: "Interval conditioning on the bike.",
            targets: "Cardio · legs",
            steps: [
                "Warm up 1–2 minutes easy.",
                "Alternate ~30s hard / 60s easy as prescribed.",
                "Stay seated with a smooth pedal stroke.",
                "Cool down easy at the end."
            ]),
        "front squat / goblet squat": .init(
            summary: "Quad-biased squat with an upright torso.",
            targets: "Quads · core",
            steps: [
                "Front-rack the bar on your delts, or hold a DB at your chest (goblet).",
                "Elbows high, brace your core.",
                "Squat down with an upright torso to depth.",
                "Drive up through mid-foot."
            ]),
        "bulgarian split squat": .init(
            summary: "Rear-foot-elevated single-leg squat.",
            targets: "Quads · glutes · balance",
            steps: [
                "Rest your rear foot on a bench behind you.",
                "Keep most of the weight on the front leg, torso tall.",
                "Lower until the front thigh is about parallel.",
                "Drive through the front heel to stand."
            ]),
        "cable pull-through": .init(
            summary: "Cable hip hinge for the glutes.",
            targets: "Glutes · hamstrings",
            steps: [
                "Face away from a low pulley, rope between your legs.",
                "Hinge at the hips, pushing them back.",
                "Stand tall by snapping the hips forward.",
                "Squeeze the glutes at the top — it's a hinge, not a squat."
            ]),
        "seated calf raise": .init(
            summary: "Bent-knee calf raise for the soleus.",
            targets: "Calves (soleus)",
            steps: [
                "Pad on your lower thighs, balls of feet on the platform.",
                "Drop the heels for a full stretch.",
                "Press up onto your toes.",
                "Pause, then lower slowly."
            ]),
        "cable wood chop / pallof": .init(
            summary: "Anti-rotation core work.",
            targets: "Core (obliques) · anti-rotation",
            steps: [
                "Set the pulley to chest/shoulder height.",
                "Wood chop: pull diagonally across your body. Pallof: press straight out and resist rotation.",
                "Keep your hips square and core braced.",
                "Move slowly and with control — quality over speed."
            ])
    ]
}
