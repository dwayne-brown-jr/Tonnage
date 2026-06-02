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
            ]),
        "leg press": .init(
            summary: "Machine compound for the quads and glutes.",
            targets: "Quads · glutes · hamstrings",
            steps: [
                "Feet shoulder-width, mid-platform; back and hips flat against the pads.",
                "Release the safeties and lower until your knees reach about 90°.",
                "Don't let your lower back round off the pad at the bottom.",
                "Press through mid-foot to near-lockout without slamming the knees."
            ]),
        "leg extension": .init(
            summary: "Knee-extension isolation for the quads.",
            targets: "Quads",
            steps: [
                "Pad on your lower shins, knees aligned with the machine's pivot.",
                "Extend to full lockout and squeeze the quads.",
                "Pause briefly at the top.",
                "Lower slowly without letting the stack rest."
            ]),
        "deadlift": .init(
            summary: "Conventional pull from the floor — full posterior-chain strength.",
            targets: "Hamstrings · glutes · back · grip",
            steps: [
                "Bar over mid-foot, shins about an inch away; grip just outside your legs.",
                "Hips back, flat back, take the slack out of the bar, brace.",
                "Drive the floor away, keeping the bar against your legs.",
                "Lock out hips and knees together; lower by hinging back."
            ]),
        "front squat": .init(
            summary: "Front-racked squat — upright, quad-biased pattern.",
            targets: "Quads · core",
            steps: [
                "Rack the bar on your front delts, elbows high, fingers under the bar.",
                "Brace, then squat down keeping your torso tall and elbows up.",
                "Hit depth with knees tracking over the toes.",
                "Drive up through mid-foot, elbows leading."
            ]),
        "overhead press": .init(
            summary: "Standing barbell press — vertical pushing strength.",
            targets: "Shoulders · triceps · core",
            steps: [
                "Bar on your front delts, grip just outside shoulders, brace hard.",
                "Press straight up, moving your head back slightly to clear the bar.",
                "Lock out overhead with the bar over your mid-foot.",
                "Lower under control back to the front-rack."
            ]),
        "incline barbell press": .init(
            summary: "Upper-chest biased barbell press.",
            targets: "Upper chest · front delts · triceps",
            steps: [
                "Set the bench to about 30°; grip just outside shoulder width.",
                "Unrack over your shoulders; lower to the upper chest, elbows ~45°.",
                "Press up and slightly back to lockout.",
                "Keep your shoulder blades pinned throughout."
            ]),
        "cable fly": .init(
            summary: "Cable isolation for the chest stretch and squeeze.",
            targets: "Chest",
            steps: [
                "Pulleys about shoulder height; a handle in each hand, one foot forward.",
                "Soft bend in the elbows, arms wide to feel a chest stretch.",
                "Bring the handles together in front of your chest in an arc.",
                "Squeeze, then return slowly to the stretch."
            ]),
        "overhead triceps extension": .init(
            summary: "Overhead extension for the triceps long head.",
            targets: "Triceps (long head)",
            steps: [
                "Hold a dumbbell, EZ-bar, or rope overhead, elbows pointing up.",
                "Lower behind your head for a deep stretch, upper arms still.",
                "Extend to lockout, squeezing the triceps.",
                "Keep your elbows tucked and ribs down."
            ]),
        "seated cable row": .init(
            summary: "Horizontal cable pull for back thickness.",
            targets: "Mid-back · lats · biceps",
            steps: [
                "Feet on the platform, slight knee bend, tall chest, arms extended.",
                "Row the handle to your lower ribs, driving the elbows back.",
                "Squeeze the shoulder blades; don't heave with the low back.",
                "Return to a full stretch under control."
            ]),
        "single-arm db row": .init(
            summary: "Unilateral row for the lats and mid-back.",
            targets: "Lats · mid-back",
            steps: [
                "Brace a hand and knee on a bench, back flat and parallel to the floor.",
                "Let the dumbbell hang, then row it to your hip / lower ribs.",
                "Drive the elbow back and squeeze; don't rotate the torso.",
                "Lower slowly to a full stretch."
            ]),
        "rear-delt fly": .init(
            summary: "Reverse fly for the rear delts.",
            targets: "Rear delts · upper back",
            steps: [
                "Hinge forward (or use a chest pad), light dumbbells hanging.",
                "Raise out to the sides in a wide arc, leading with the elbows.",
                "Squeeze the rear delts at the top; keep the traps relaxed.",
                "Lower slowly — light and strict."
            ]),
        "weighted pull-up / lat pulldown": .init(
            summary: "Vertical pull for lat width and strength.",
            targets: "Lats · biceps · upper back",
            steps: [
                "Pull-up: hang from the bar (add load via belt/DB); pulldown: lock the thigh pad.",
                "Start from a full stretch with active shoulders.",
                "Pull your chest to the bar / the bar to your chest, elbows driving down.",
                "Lower under control to a full stretch."
            ]),
        "barbell or ez-bar curl": .init(
            summary: "Standing barbell biceps curl.",
            targets: "Biceps",
            steps: [
                "Stand tall, elbows pinned at your sides, shoulder-width grip.",
                "Curl the bar without swinging or leaning back.",
                "Squeeze at the top.",
                "Lower slowly to full extension."
            ])
    ]
}

/// Primary muscle group, used to suggest same-muscle swaps.
public enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, cardio
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .chest:      "Chest"
        case .back:       "Back"
        case .shoulders:  "Shoulders"
        case .biceps:     "Biceps"
        case .triceps:    "Triceps"
        case .quads:      "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes:     "Glutes"
        case .calves:     "Calves"
        case .core:       "Core"
        case .cardio:     "Cardio"
        }
    }
}

public extension ExerciseLibrary {

    /// Known movements per muscle group (compounds first). Every name also exists in the
    /// directions catalog, so any suggested swap comes with full how-to directions.
    static let exercisesByGroup: [MuscleGroup: [String]] = [
        .chest:      ["Barbell Bench Press", "Incline Barbell Press", "Incline DB Press", "Cable Fly"],
        .back:       ["Barbell Row", "Weighted Pull-up / Lat Pulldown", "Cable Lat Pulldown",
                      "Seated Cable Row", "Chest-Supported Row", "Single-arm DB Row"],
        .shoulders:  ["Overhead Press", "Seated Shoulder Press", "DB Lateral Raise",
                      "Cable Face Pull", "Rear-delt Fly"],
        .biceps:     ["Barbell or EZ-bar Curl", "EZ-bar or DB Curl", "DB Incline Curl"],
        .triceps:    ["Cable Triceps Pushdown", "Overhead Triceps Extension"],
        .quads:      ["Barbell Back Squat", "Front Squat", "Leg Press", "Bulgarian Split Squat",
                      "Walking DB Lunges", "Leg Extension"],
        .hamstrings: ["Romanian Deadlift", "Deadlift", "Leg Curl"],
        .glutes:     ["Cable Pull-Through"],
        .calves:     ["Standing Calf Raise", "Seated Calf Raise"],
        .core:       ["Hanging Knee Raise", "Cable Wood Chop / Pallof"],
        .cardio:     ["Stair Master", "Bike intervals"]
    ]

    /// The muscle group a movement belongs to (nil for unknown / custom names).
    static func muscleGroup(for name: String) -> MuscleGroup? {
        let n = normalize(name)
        for (group, names) in exercisesByGroup where names.contains(where: { normalize($0) == n }) {
            return group
        }
        return nil
    }

    /// Same-muscle alternatives to a movement (display names), excluding the movement
    /// itself. Empty for movements we don't recognize.
    static func alternatives(for name: String, limit: Int = 6) -> [String] {
        guard let group = muscleGroup(for: name) else { return [] }
        let n = normalize(name)
        return Array((exercisesByGroup[group] ?? []).filter { normalize($0) != n }.prefix(limit))
    }

    /// Whether a known movement is a compound — used to prefill the swap form sensibly.
    static func isCompound(_ name: String) -> Bool { compoundNames.contains(normalize(name)) }

    private static let compoundNames: Set<String> = Set([
        "Barbell Bench Press", "Incline Barbell Press", "Incline DB Press",
        "Barbell Row", "Weighted Pull-up / Lat Pulldown", "Cable Lat Pulldown",
        "Seated Cable Row", "Chest-Supported Row", "Single-arm DB Row",
        "Overhead Press", "Seated Shoulder Press",
        "Barbell Back Squat", "Front Squat", "Front Squat / Goblet Squat", "Leg Press",
        "Bulgarian Split Squat", "Walking DB Lunges",
        "Romanian Deadlift", "Deadlift"
    ].map { ExerciseLibrary.normalize($0) })
}
