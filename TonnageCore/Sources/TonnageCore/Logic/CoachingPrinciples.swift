import Foundation

/// Evidence-based coaching principles injected into both the chat coach and the block
/// planner prompts, so their advice and exercise selection rest on what actually drives
/// results (volume, frequency, proximity to failure, progressive overload) rather than
/// fads. Kept tight and high-signal — long prompts dilute, not sharpen.
public enum CoachingPrinciples {
    public static let evidenceBased = """
    EVIDENCE-BASED PRINCIPLES (apply these; ignore fads):
    - Volume drives hypertrophy: roughly 10–20 hard sets per muscle per week is the productive range. Bias the muscles they want to bring up toward the top of that range; hold others around 6–10 (maintenance).
    - Hitting each muscle about twice a week beats once for the same weekly volume.
    - Train most working sets at 1–3 reps in reserve — close to failure, not to it. The app derives week-to-week load from the rep range + effort target, so just set sensible ranges.
    - Rep ranges: main compounds 5–10, accessories 8–20 — all build muscle when taken near failure. Strength goal → lower reps, longer rest, more main-lift focus; size goal → more total volume and moderate-to-high reps.
    - Exercise selection: pick stable, trainable movements with a good loaded stretch. One compound first, then accessories. Keep the main barbell lifts constant across blocks so progress is measurable; rotate accessories.
    - To bring up a lagging muscle: train it first while fresh and add a little volume/frequency there — don't add sets everywhere, recovery is finite.
    - Progressive overload is the engine: more reps or load over time. Protein, sleep, and consistency matter more than any single exercise choice.
    - Deload when readiness or performance drops, or roughly every 4–6 weeks (the 5-week block's deload week handles this).
    """
}
