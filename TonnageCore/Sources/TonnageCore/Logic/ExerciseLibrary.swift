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
            ]),
        // MARK: Expanded swap pool — more variety per muscle group
        "db bench press": .init(
            summary: "Flat dumbbell press — a deeper-stretch bench variation.",
            targets: "Chest · front delts · triceps",
            steps: [
                "Lie back, dumbbells at chest height, elbows ~45° from your torso.",
                "Press up and slightly together to lockout over your chest.",
                "Lower under control to a full stretch.",
                "Keep your shoulder blades pinned down and back."
            ]),
        "machine chest press": .init(
            summary: "Fixed-path chest press — easy to push close to failure safely.",
            targets: "Chest · front delts · triceps",
            steps: [
                "Set the seat so the handles sit at mid-chest.",
                "Press out to lockout without shrugging.",
                "Return under control to a stretch.",
                "Keep your back against the pad."
            ]),
        "pec deck fly": .init(
            summary: "Machine fly — chest isolation with a constant stretch.",
            targets: "Chest",
            steps: [
                "Set the pads/handles so your arms are wide with a soft elbow.",
                "Bring the handles together in front of your chest.",
                "Squeeze, then return slowly to a stretch.",
                "Keep the movement at the shoulder, not the elbow."
            ]),
        "pull-up": .init(
            summary: "Bodyweight vertical pull for lats and upper back.",
            targets: "Lats · upper back · biceps",
            steps: [
                "Hang from the bar with active shoulders, hands just outside shoulders.",
                "Pull your chest toward the bar, driving the elbows down.",
                "Get your chin over the bar without swinging.",
                "Lower under control to a full hang. Add a belt for load."
            ]),
        "push-up": .init(
            summary: "Bodyweight horizontal push — scalable anywhere.",
            targets: "Chest · front delts · triceps",
            steps: [
                "Hands a bit wider than shoulders, body in one straight line from head to heels.",
                "Brace your core and squeeze your glutes — no sagging hips.",
                "Lower until your chest is just above the floor, elbows ~45° from your torso.",
                "Press to lockout. Elevate the hands to scale down, or add a plate on your back to scale up."
            ]),
        "chin-up": .init(
            summary: "Underhand (palms-toward-you) vertical pull — big biceps involvement.",
            targets: "Lats · biceps · mid-back",
            steps: [
                "Hang from the bar with an underhand grip, hands about shoulder width.",
                "Pull your elbows down and back, driving your chest toward the bar.",
                "Get your chin over the bar without kipping or swinging.",
                "Lower under control to a full hang. Add a belt once you pass ~12 clean reps."
            ]),
        "bodyweight dip": .init(
            summary: "Vertical push on parallel bars — lean forward for chest, stay upright for triceps.",
            targets: "Chest · triceps · front delts",
            steps: [
                "Support yourself on parallel bars, arms locked, shoulders down away from your ears.",
                "Lower under control until your upper arms are about parallel to the floor.",
                "Lean the torso slightly forward to bias chest, or stay vertical to bias triceps.",
                "Press back to lockout. Use an assisted-dip machine or a band to scale down."
            ]),
        "inverted row": .init(
            summary: "Bodyweight horizontal pull — the row counterpart to a push-up.",
            targets: "Mid-back · lats · rear delts · biceps",
            steps: [
                "Set a bar (or rings) at about hip height; hang underneath with a straight body.",
                "Grip just outside shoulder width, heels on the floor, body rigid.",
                "Pull your chest to the bar, squeezing your shoulder blades together.",
                "Lower under control. Raise the bar to scale down; lower it or elevate your feet to scale up."
            ]),
        "pike push-up": .init(
            summary: "Bodyweight vertical press — a shoulder-focused push-up.",
            targets: "Shoulders · triceps · upper chest",
            steps: [
                "Start in a downward-dog pike: hips high, hands shoulder-width, head pointing down.",
                "Keep your hips stacked over your shoulders as much as you can.",
                "Lower the crown of your head toward the floor between your hands.",
                "Press back to the pike. Elevate your feet to make it harder."
            ]),
        "bodyweight squat": .init(
            summary: "Unloaded squat pattern — knee-and-hip strength, anywhere.",
            targets: "Quads · glutes",
            steps: [
                "Stand shoulder-width, toes slightly out, chest tall.",
                "Sit down and back, knees tracking over your toes.",
                "Descend to at least parallel, keeping your heels down.",
                "Drive up through the whole foot. Slow the tempo or move to one leg (pistol) to progress."
            ]),
        "hanging leg raise": .init(
            summary: "The hardest hanging core flexion — straight legs to hips.",
            targets: "Abs · hip flexors",
            steps: [
                "Hang from a bar, shoulders active (slightly pulled down), legs straight.",
                "Without swinging, raise your legs by curling your pelvis up.",
                "Bring your thighs to at least parallel — higher if you can keep the legs straight.",
                "Lower slowly. Bend the knees (hanging knee raise) to scale down."
            ]),
        "t-bar row": .init(
            summary: "Supported barbell row for back thickness.",
            targets: "Mid-back · lats",
            steps: [
                "Straddle the bar, hinge to ~45°, neutral spine, chest up.",
                "Row the handle to your lower chest, elbows back.",
                "Squeeze the shoulder blades hard at the top.",
                "Lower under control to a full stretch."
            ]),
        "straight-arm pulldown": .init(
            summary: "Cable lat isolation with straight arms.",
            targets: "Lats",
            steps: [
                "Stand at a high pulley, slight hinge, arms extended out front.",
                "Keep your elbows nearly locked and pull the bar to your thighs.",
                "Feel the lats; don't turn it into a triceps pushdown.",
                "Return slowly to a full overhead stretch."
            ]),
        "arnold press": .init(
            summary: "Rotating dumbbell shoulder press for full delt coverage.",
            targets: "Shoulders · triceps",
            steps: [
                "Start with dumbbells at chin height, palms facing you.",
                "Press overhead while rotating palms to face forward.",
                "Lock out without flaring the ribs.",
                "Reverse the rotation on the way down."
            ]),
        "cable lateral raise": .init(
            summary: "Cable side raise — constant tension on the side delts.",
            targets: "Side delts",
            steps: [
                "Stand side-on to a low pulley, handle in the far hand.",
                "Raise out to shoulder height, leading with the elbow.",
                "Keep a soft elbow; don't shrug.",
                "Lower slowly against the cable's pull."
            ]),
        "hammer curl": .init(
            summary: "Neutral-grip curl for the biceps and forearm.",
            targets: "Biceps · brachialis · forearm",
            steps: [
                "Stand tall, dumbbells at your sides, palms facing in.",
                "Curl without rotating the wrist; keep the upper arms still.",
                "Squeeze at the top.",
                "Lower slowly to full extension."
            ]),
        "preacher curl": .init(
            summary: "Supported curl that kills momentum for the biceps.",
            targets: "Biceps",
            steps: [
                "Rest the backs of your upper arms on the preacher pad.",
                "Curl the bar/dumbbell up, keeping your arms on the pad.",
                "Squeeze at the top.",
                "Lower slowly to near-full extension — don't bounce."
            ]),
        "skull crusher": .init(
            summary: "Lying triceps extension for the long head.",
            targets: "Triceps",
            steps: [
                "Lie back, EZ-bar or dumbbells over your chest, arms vertical.",
                "Bend at the elbows to lower toward your forehead/behind your head.",
                "Keep your upper arms still.",
                "Extend back to lockout, squeezing the triceps."
            ]),
        "close-grip bench press": .init(
            summary: "Narrow-grip bench biased to the triceps.",
            targets: "Triceps · chest",
            steps: [
                "Grip the bar about shoulder-width, elbows tucked.",
                "Lower to your lower chest, keeping elbows close.",
                "Press to lockout, driving with the triceps.",
                "Stay tight — don't let the elbows flare."
            ]),
        "triceps dips": .init(
            summary: "Bodyweight dip biased to the triceps.",
            targets: "Triceps · chest",
            steps: [
                "Support yourself on parallel bars, torso fairly upright.",
                "Lower until your elbows reach ~90°.",
                "Press back to lockout, squeezing the triceps.",
                "Keep the movement controlled; add a belt to load."
            ]),
        "hack squat": .init(
            summary: "Machine squat with a fixed path — quad-focused.",
            targets: "Quads · glutes",
            steps: [
                "Shoulders and back against the pads, feet mid-platform.",
                "Release the safeties and squat to at least parallel.",
                "Keep your whole foot down and back flat against the pad.",
                "Drive up through mid-foot without locking the knees hard."
            ]),
        "goblet squat": .init(
            summary: "Dumbbell/kettlebell squat held at the chest.",
            targets: "Quads · glutes · core",
            steps: [
                "Hold a dumbbell vertically at your chest, elbows down.",
                "Squat between your knees with an upright torso.",
                "Hit depth, then drive up through mid-foot.",
                "Keep the weight tight to your chest throughout."
            ]),
        "seated leg curl": .init(
            summary: "Seated machine hamstring curl with a strong stretch.",
            targets: "Hamstrings",
            steps: [
                "Pad on your lower shins, thigh pad locked down.",
                "Curl your heels down and under, squeezing the hamstrings.",
                "Pause briefly at the bottom.",
                "Return slowly to a full stretch."
            ]),
        "stiff-leg deadlift": .init(
            summary: "Hinge with near-straight legs for a deep hamstring stretch.",
            targets: "Hamstrings · glutes",
            steps: [
                "Bar at your thighs, knees only slightly bent and fixed.",
                "Push your hips back, lowering the bar down your legs.",
                "Go to a deep hamstring stretch with a neutral spine.",
                "Drive the hips forward to stand tall."
            ]),
        "barbell hip thrust": .init(
            summary: "Loaded bridge — the big glute builder.",
            targets: "Glutes · hamstrings",
            steps: [
                "Upper back on a bench, bar across your hips (use a pad).",
                "Drive through your heels to full hip extension.",
                "Squeeze the glutes hard at the top, ribs down.",
                "Lower under control without resting the bar."
            ]),
        "glute kickback": .init(
            summary: "Cable/machine kickback to isolate the glute.",
            targets: "Glutes",
            steps: [
                "Anchor a cuff to your ankle at a low pulley (or use the machine).",
                "Kick the leg straight back, squeezing the glute.",
                "Keep your back flat — don't arch to cheat range.",
                "Return slowly under control."
            ]),
        "single-leg calf raise": .init(
            summary: "One-legged calf raise for extra load and balance.",
            targets: "Calves",
            steps: [
                "Ball of one foot on a step, other foot tucked, hold a DB.",
                "Drop the heel for a full stretch.",
                "Press up onto your toes as high as you can.",
                "Pause at the top, then lower slowly."
            ]),
        "cable crunch": .init(
            summary: "Weighted ab flexion at a high pulley.",
            targets: "Abs",
            steps: [
                "Kneel facing a high pulley, rope behind your head.",
                "Crunch down by rounding your spine, not bending at the hips.",
                "Squeeze the abs hard at the bottom.",
                "Return slowly under tension."
            ]),
        "plank": .init(
            summary: "Isometric core brace.",
            targets: "Core · abs",
            steps: [
                "Forearms and toes down, body in a straight line.",
                "Brace your abs and squeeze your glutes — no sagging hips.",
                "Keep your neck neutral, breathe steadily.",
                "Hold for time."
            ]),
        "rowing machine": .init(
            summary: "Full-body cardio erg.",
            targets: "Cardio · back · legs",
            steps: [
                "Drive with the legs first, then lean back and pull to your sternum.",
                "Return arms-then-body-then-legs in reverse order.",
                "Keep a smooth, steady stroke rate.",
                "Use easy pressure for conditioning, not a sprint."
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
        .chest:      ["Barbell Bench Press", "DB Bench Press", "Incline Barbell Press", "Incline DB Press",
                      "Machine Chest Press", "Push-up", "Bodyweight Dip", "Cable Fly", "Pec Deck Fly"],
        .back:       ["Barbell Row", "Pull-up", "Chin-up", "Weighted Pull-up / Lat Pulldown", "Cable Lat Pulldown",
                      "Seated Cable Row", "T-Bar Row", "Chest-Supported Row", "Single-arm DB Row",
                      "Inverted Row", "Straight-Arm Pulldown"],
        .shoulders:  ["Overhead Press", "Seated Shoulder Press", "Arnold Press", "Pike Push-up", "DB Lateral Raise",
                      "Cable Lateral Raise", "Cable Face Pull", "Rear-delt Fly"],
        .biceps:     ["Barbell or EZ-bar Curl", "EZ-bar or DB Curl", "DB Incline Curl", "Hammer Curl",
                      "Preacher Curl"],
        .triceps:    ["Cable Triceps Pushdown", "Overhead Triceps Extension", "Skull Crusher",
                      "Close-Grip Bench Press", "Triceps Dips"],
        .quads:      ["Barbell Back Squat", "Front Squat", "Hack Squat", "Leg Press", "Goblet Squat",
                      "Bulgarian Split Squat", "Walking DB Lunges", "Bodyweight Squat", "Leg Extension"],
        .hamstrings: ["Romanian Deadlift", "Stiff-Leg Deadlift", "Deadlift", "Leg Curl", "Seated Leg Curl"],
        .glutes:     ["Barbell Hip Thrust", "Cable Pull-Through", "Glute Kickback"],
        .calves:     ["Standing Calf Raise", "Seated Calf Raise", "Single-Leg Calf Raise"],
        .core:       ["Hanging Knee Raise", "Hanging Leg Raise", "Cable Crunch", "Cable Wood Chop / Pallof", "Plank"],
        .cardio:     ["Stair Master", "Bike intervals", "Rowing Machine"]
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
    /// itself and anything in `excluding` (e.g. exercises already in the current session,
    /// so suggestions are context-specific rather than the same list every time).
    /// Empty for movements we don't recognize.
    static func alternatives(for name: String, excluding: Set<String> = [], limit: Int = 6) -> [String] {
        guard let group = muscleGroup(for: name) else { return [] }
        var avoid = Set(excluding.map { normalize($0) })
        avoid.insert(normalize(name))
        return Array((exercisesByGroup[group] ?? []).filter { !avoid.contains(normalize($0)) }.prefix(limit))
    }

    /// Whether a known movement is a compound — used to prefill the swap form sensibly.
    static func isCompound(_ name: String) -> Bool { compoundNames.contains(normalize(name)) }

    private static let compoundNames: Set<String> = Set([
        "Barbell Bench Press", "DB Bench Press", "Incline Barbell Press", "Incline DB Press",
        "Machine Chest Press", "Close-Grip Bench Press", "Triceps Dips",
        "Barbell Row", "Pull-up", "Weighted Pull-up / Lat Pulldown", "Cable Lat Pulldown",
        "Seated Cable Row", "T-Bar Row", "Chest-Supported Row", "Single-arm DB Row",
        "Overhead Press", "Seated Shoulder Press", "Arnold Press",
        "Barbell Back Squat", "Front Squat", "Front Squat / Goblet Squat", "Hack Squat",
        "Leg Press", "Goblet Squat", "Bulgarian Split Squat", "Walking DB Lunges",
        "Romanian Deadlift", "Stiff-Leg Deadlift", "Deadlift", "Barbell Hip Thrust",
        // Calisthenics compounds.
        "Push-up", "Chin-up", "Bodyweight Dip", "Inverted Row", "Pike Push-up", "Bodyweight Squat"
    ].map { ExerciseLibrary.normalize($0) })

    /// Curated movements for the "Add Exercise" quick-add grid — calisthenics first, then
    /// popular accessories. Every name resolves in the directions catalog + a muscle group.
    static let quickAddSuggestions: [String] = [
        "Push-up", "Pull-up", "Chin-up", "Bodyweight Dip", "Inverted Row", "Pike Push-up",
        "Bodyweight Squat", "Hanging Leg Raise",
        "DB Lateral Raise", "Hammer Curl", "Cable Triceps Pushdown", "Cable Face Pull",
        "Leg Curl", "Leg Extension", "Standing Calf Raise", "Cable Crunch"
    ]
}
