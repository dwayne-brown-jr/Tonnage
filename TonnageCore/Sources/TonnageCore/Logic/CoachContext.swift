import Foundation

/// Recovery snapshot (from HealthKit) passed into the coach context.
public struct CoachRecovery: Sendable, Equatable {
    public var bodyweightLb: Double?
    public var bodyweightChangeLb: Double?   // change over the visible window (− = down)
    public var restingHR: Double?
    public var hrvMs: Double?
    public var sleepHours: Double?

    public init(bodyweightLb: Double? = nil, bodyweightChangeLb: Double? = nil,
                restingHR: Double? = nil, hrvMs: Double? = nil, sleepHours: Double? = nil) {
        self.bodyweightLb = bodyweightLb
        self.bodyweightChangeLb = bodyweightChangeLb
        self.restingHR = restingHR
        self.hrvMs = hrvMs
        self.sleepHours = sleepHours
    }

    public var isEmpty: Bool {
        bodyweightLb == nil && restingHR == nil && hrvMs == nil && sleepHours == nil
    }
}

/// The coach's system prompt + a builder that appends the live training context.
public enum CoachContext {

    /// Coaching persona, personalized from the athlete's profile (so each person who
    /// uses Tonnage gets their own coach, not a hardcoded one).
    public static func systemPrompt(for profile: CoachProfile) -> String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        let who = name.isEmpty ? "your athlete" : name
        let subject = name.isEmpty ? "They are" : "\(name) is"
        let stats = profile.statsClause
        let statsPart = stats.isEmpty ? "" : " (\(stats))"
        let limits = profile.limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        let limitsLine = limits.isEmpty ? "" : "\nTrain around these limitations they flagged: \(limits)."
        return """
        You are \(who)'s strength coach. \(subject) \(profile.experience.coachPhrase)\(statsPart), on a 4-day Upper/Lower split, training for \(profile.goal.coachPhrase).\(limitsLine)
        Philosophy: RAMP first, push later — Week 1 is intentionally light to let connective tissue catch up; don't let them ego-lift early. Effort is tracked as reps in reserve ("reps left"): hit the prescribed reps-left target → +5 lb next week; 0–1 reps left → hold weight, add reps; failed reps → swap or deload. Pattern detection across weeks matters more than any single session — look for stalls, fatigue signals, imbalances. Active-rest conditioning (walks, stairs, bike) on off days counts toward total fatigue and recovery — don't double-load.
        When HealthKit data is available, use it: poor recent sleep or elevated resting HR → pull back intensity that day. Read the bodyweight trend against their goal (recomp: steady or slowly down while strength climbs; size: gaining slowly; strength: roughly stable).
        Style: concise, direct, no fluff. Talk to them like a peer athlete you respect. Numbers over vibes. Always talk effort as "reps left" (reps in reserve), never "RPE" — that's the language the app uses. If a swap broke your week-to-week comparison for a lift, say so. If you need data you don't have, ask.
        """
    }

    /// Builds a structured context block appended to the system prompt on each request.
    public static func build(program: Program?,
                             currentWeek: Int,
                             recentWorkouts: [LoggedWorkout],
                             activities: [Activity],
                             recovery: CoachRecovery,
                             readiness: Readiness? = nil,
                             focusSession: String? = nil,
                             focusDay: DayType? = nil,
                             maxWorkouts: Int = 6,
                             maxActivities: Int = 6) -> String {
        var lines: [String] = ["# LIVE CONTEXT"]

        let phase = WeekPhase.forWeek(currentWeek)
        let blockName = program.map { "\($0.name) — " } ?? ""
        lines.append("\(blockName)Week \(currentWeek) (\(phase.title) — \(phase.detail)).")

        // What the athlete is looking at on the TRAIN screen right now — answer "today"
        // / "should I train" questions against this exact session and day type.
        if let focusDay {
            switch focusDay {
            case .lift:
                if let focusSession {
                    lines.append("On the TRAIN screen right now: \(focusSession), lift day — treat this as today's session.")
                }
            case .activeRest:
                lines.append("On the TRAIN screen right now: an Active Rest day (easy conditioning, no lifting).")
            case .fullRest:
                lines.append("On the TRAIN screen right now: a Full Rest day.")
            }
        }

        // Readiness (drives whether to push or pull back today)
        if let r = readiness, r.band != .unknown, let score = r.score {
            let drivers = r.drivers.map(\.label).joined(separator: "; ")
            lines.append("Readiness: \(score)/100 — \(r.band.rawValue). \(r.trainingNote) Drivers: \(drivers).")
        }

        // Recovery
        if recovery.isEmpty {
            lines.append("Recovery: no HealthKit data shared.")
        } else {
            var r: [String] = []
            if let w = recovery.bodyweightLb {
                var s = "bodyweight \(fmt(w)) lb"
                if let d = recovery.bodyweightChangeLb, abs(d) >= 0.1 {
                    s += " (\(d < 0 ? "−" : "+")\(fmt(abs(d))) lb recent)"
                }
                r.append(s)
            }
            if let hr = recovery.restingHR { r.append("resting HR \(Int(hr)) bpm") }
            if let hrv = recovery.hrvMs { r.append("HRV \(Int(hrv)) ms") }
            if let sl = recovery.sleepHours { r.append(String(format: "last night sleep %.1f h", sl)) }
            lines.append("Recovery: " + r.joined(separator: ", ") + ".")
        }

        // Program plan — what each session actually prescribes, so the coach knows the
        // structure even for sessions not recently logged (e.g. "what's in Upper B?").
        if let program, !program.orderedSessions.isEmpty {
            lines.append("\n## Program plan (prescriptions per session)")
            for s in program.orderedSessions {
                let title = s.subtitle.isEmpty ? s.name : "\(s.name) — \(s.subtitle)"
                lines.append("### \(title)")
                for ex in s.orderedExercises {
                    lines.append("- " + prescription(ex))
                }
            }
        }

        // Recent sessions (most recent first)
        let sessions = recentWorkouts
            .sorted { $0.date > $1.date }
            .prefix(maxWorkouts)
        if sessions.isEmpty {
            lines.append("\nNo workouts logged yet.")
        } else {
            lines.append("\n## Recent sessions")
            for w in sessions {
                lines.append(summarize(w))
            }
        }

        // Recent activities
        let recent = activities.sorted { $0.date > $1.date }.prefix(maxActivities)
        if !recent.isEmpty {
            lines.append("\n## Recent active-rest / cardio")
            for a in recent {
                var parts = ["\(a.name) — \(a.durationMinutes) min"]
                if let d = a.distanceMiles, d > 0 { parts.append("\(fmt(d)) mi") }
                if let f = a.flights, f > 0 { parts.append("\(f) flights") }
                lines.append("- \(dateString(a.date)): " + parts.joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    /// One prescribed exercise, in the app's reps-left language (never RPE).
    private static func prescription(_ ex: ExerciseTemplate) -> String {
        if ex.isCardio {
            let effort = ex.rpeTarget.isEmpty ? "" : ", \(ex.rpeTarget)"
            return "\(ex.name): \(ex.repRange)\(effort)"
        }
        var s = "\(ex.name): \(ex.prescribedSets)×\(ex.repRange)"
        let reserve = CoachEngine.repsLeftTarget(from: ex.rpeTarget)
        if !reserve.isEmpty, reserve != ex.rpeTarget { s += ", \(reserve) reps left" }
        if ex.isCompound { s += " (compound)" }
        let notes = ex.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { s += " — \(notes)" }
        return s
    }

    private static func summarize(_ w: LoggedWorkout) -> String {
        let header = "B\(w.blockNumber) W\(w.weekNumber) \(w.sessionName) (\(dateString(w.date)), \(w.dayType.title))"
        switch w.dayType {
        case .activeRest, .fullRest:
            return "- \(header)"
        case .lift:
            let exercises = w.orderedExercises.compactMap { ex -> String? in
                guard let top = ex.topSet else { return nil }
                let reserve = top.rpe.map { " · \(CoachEngine.repsLeftLabel(fromRPE: $0)) left" } ?? ""
                return "\(ex.name) \(fmt(top.weight))×\(top.reps)\(reserve)"
            }
            var line = "- \(header): " + (exercises.isEmpty ? "no completed sets" : exercises.joined(separator: "; "))
            if !w.notes.isEmpty { line += " | note: \(w.notes)" }
            return line
        }
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
