import Foundation

/// An exercise's top set week by week across one block — drives the week bars and the
/// "+15 LB THIS BLOCK" chip on the exercise card.
public struct BlockProgress: Equatable, Sendable {

    public struct Week: Equatable, Sendable, Identifiable {
        public let week: Int
        /// Heaviest completed working set that week, or nil if the exercise wasn't logged.
        public let weight: Double?
        public let reps: Int?
        public var id: Int { week }
    }

    /// Weeks 1–5, always five entries so the bars line up across exercises.
    public let weeks: [Week]

    /// The week being viewed on TRAIN (highlighted bar).
    public let currentWeek: Int

    /// Load gained this block: the best top set in the build weeks (1–4, so a week-5
    /// deload never reads as a loss) minus the first logged week's. Nil until at least
    /// two weeks are logged, and nil for bodyweight work (see `repGain`).
    public var weightGain: Double? {
        let build = weeks.filter { $0.week <= 4 }.compactMap { w in w.weight.map { (w.week, $0) } }
        guard let first = build.first, build.count >= 2, first.1 > 0,
              let best = build.map(\.1).max() else { return nil }
        return best - first.1
    }

    /// For bodyweight exercises (every logged week at 0 lb): reps gained on the top set.
    public var repGain: Int? {
        let logged = weeks.filter { $0.week <= 4 && $0.weight != nil }
        guard logged.count >= 2, logged.allSatisfy({ ($0.weight ?? 0) == 0 }),
              let first = logged.first?.reps, let best = logged.compactMap(\.reps).max() else { return nil }
        return best - first
    }

    /// The chip text, e.g. "+15 LB" or "+3 REPS" — short enough to sit beside the card's
    /// tags. Only for real gains. VoiceOver reads `chipSpokenText`.
    public var chipText: String? {
        if let g = weightGain, g > 0 { return "+\(CoachEngine.fmt(g)) LB" }
        if let r = repGain, r > 0 { return "+\(r) REP\(r == 1 ? "" : "S")" }
        return nil
    }

    /// e.g. "up 15 pounds this block".
    public var chipSpokenText: String? {
        if let g = weightGain, g > 0 { return "up \(CoachEngine.fmt(g)) pounds this block" }
        if let r = repGain, r > 0 { return "up \(r) rep\(r == 1 ? "" : "s") this block" }
        return nil
    }

    /// Whether there's anything worth drawing (at least two logged weeks).
    public var hasHistory: Bool { weeks.filter { $0.weight != nil }.count >= 2 }

    /// Bar height 0…1 for a week: its weight relative to the block's range, with a floor so
    /// the lightest logged week still shows. Bodyweight work scales by reps instead.
    public func barFraction(_ w: Week) -> Double {
        let bodyweight = weeks.allSatisfy { ($0.weight ?? 0) == 0 }
        let value: Double? = bodyweight ? w.reps.map(Double.init) : w.weight
        guard let v = value else { return 0 }
        let all = weeks.compactMap { bodyweight ? $0.reps.map(Double.init) : $0.weight }
        guard let lo = all.min(), let hi = all.max(), hi > 0 else { return 0.35 }
        if hi == lo { return 0.7 }
        return 0.35 + 0.65 * (v - lo) / (hi - lo)
    }

    public init(weeks: [Week], currentWeek: Int) {
        self.weeks = weeks
        self.currentWeek = currentWeek
    }

    /// Builds the block's progress for one exercise in one session (so Lower A's RDL
    /// isn't compared with Lower B's lighter RDL). Spelling variants count as the same lift.
    public static func build(from workouts: [LoggedWorkout], exercise name: String, sessionName: String,
                             block: Int, currentWeek: Int) -> BlockProgress {
        let key = ExerciseLibrary.historyKey(for: name)
        var byWeek: [Int: LoggedSet] = [:]
        for w in workouts where w.blockNumber == block && w.sessionName == sessionName && (1...5).contains(w.weekNumber) {
            for ex in w.exercises ?? [] where !ex.isCardio && ExerciseLibrary.historyKey(for: ex.name) == key {
                guard let top = ex.topSet else { continue }
                if let existing = byWeek[w.weekNumber],
                   (existing.weight, existing.reps) >= (top.weight, top.reps) { continue }
                byWeek[w.weekNumber] = top
            }
        }
        let weeks = (1...5).map { wk in
            Week(week: wk, weight: byWeek[wk]?.weight, reps: byWeek[wk]?.reps)
        }
        return BlockProgress(weeks: weeks, currentWeek: currentWeek)
    }
}

public extension BlockProgress {

    /// One lift's gain this block, for the DATA ticker.
    struct LiftGain: Equatable, Sendable {
        public let name: String
        public let gainLb: Double
    }

    /// Every lift that's gone up this block, biggest gain first: the best top set in weeks
    /// 1–4 minus the first logged week's, per lift (spelling variants merged, sessions
    /// combined). Bodyweight and cardio work is left out.
    static func liftGains(from workouts: [LoggedWorkout], block: Int, limit: Int = 8) -> [LiftGain] {
        var byLift: [String: (name: String, weeks: [Int: Double])] = [:]
        for w in workouts where w.blockNumber == block && (1...4).contains(w.weekNumber) {
            for ex in w.exercises ?? [] where !ex.isCardio {
                guard let top = ex.topSet, top.weight > 0 else { continue }
                let key = ExerciseLibrary.historyKey(for: ex.name)
                var entry = byLift[key] ?? (ExerciseLibrary.canonicalDisplayName(for: ex.name), [:])
                entry.weeks[w.weekNumber] = max(entry.weeks[w.weekNumber] ?? 0, top.weight)
                byLift[key] = entry
            }
        }
        let gains: [LiftGain] = byLift.values.compactMap { entry in
            guard entry.weeks.count >= 2, let firstWeek = entry.weeks.keys.min(),
                  let first = entry.weeks[firstWeek], let best = entry.weeks.values.max(), best > first else { return nil }
            return LiftGain(name: entry.name, gainLb: best - first)
        }
        return Array(gains.sorted { ($0.gainLb, $1.name) > ($1.gainLb, $0.name) }.prefix(limit))
    }
}
