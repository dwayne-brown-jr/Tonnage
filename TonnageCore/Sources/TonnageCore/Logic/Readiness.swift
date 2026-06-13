import Foundation

/// Inputs for the daily readiness read — all sourced from HealthKit. Each is optional
/// so the score degrades gracefully when a signal isn't available.
public struct ReadinessInputs: Sendable, Equatable {
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    public var sleepHours: Double?
    public var trainedYesterday: Bool
    /// Overnight body/skin temperature (°C) and your personal baseline. A ring (Oura,
    /// Apple Watch) writes this to HealthKit; a rise vs baseline flags illness / strain.
    public var bodyTempC: Double?
    public var bodyTempBaselineC: Double?
    /// Overnight respiratory rate (breaths/min) and baseline. Elevated breathing at rest
    /// is an early stress / illness signal.
    public var respiratoryRate: Double?
    public var respiratoryRateBaseline: Double?

    public init(hrvMs: Double? = nil, hrvBaselineMs: Double? = nil,
                restingHR: Double? = nil, restingHRBaseline: Double? = nil,
                sleepHours: Double? = nil, trainedYesterday: Bool = false,
                bodyTempC: Double? = nil, bodyTempBaselineC: Double? = nil,
                respiratoryRate: Double? = nil, respiratoryRateBaseline: Double? = nil) {
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.sleepHours = sleepHours
        self.trainedYesterday = trainedYesterday
        self.bodyTempC = bodyTempC
        self.bodyTempBaselineC = bodyTempBaselineC
        self.respiratoryRate = respiratoryRate
        self.respiratoryRateBaseline = respiratoryRateBaseline
    }
}

/// A transparent, training-focused readiness read. NOT a medical metric — it's an
/// explainable heuristic over HRV, resting HR, and sleep (vs. your own baselines)
/// that steers today's training intensity.
public struct Readiness: Sendable, Equatable {
    public enum Band: String, Sendable { case primed, ready, compromised, drained, unknown }

    public struct Driver: Sendable, Equatable, Identifiable {
        public enum Sign: Sendable { case positive, negative, neutral }
        public let label: String
        public let sign: Sign
        /// Signed points this signal added to (or subtracted from) the score.
        public let points: Double
        /// Max |points| this signal can contribute — for scaling a contribution bar.
        public let magnitude: Double
        public var id: String { label }
        /// Contribution as a fraction of this signal's max, clamped to [-1, 1].
        public var fraction: Double { magnitude > 0 ? max(-1, min(1, points / magnitude)) : 0 }

        public init(_ label: String, _ sign: Sign, points: Double = 0, magnitude: Double = 1) {
            self.label = label
            self.sign = sign
            self.points = points
            self.magnitude = magnitude
        }
    }

    public let score: Int?          // 0–100; nil when there isn't enough data
    public let band: Band
    public let drivers: [Driver]
    public let headline: String     // short, e.g. "Ready"
    public let trainingNote: String // one-line guidance

    /// When true, the progression engine should hold loads rather than add — you're
    /// under-recovered, so chasing PRs today isn't the move.
    public var holdsProgression: Bool { band == .compromised || band == .drained }
}

/// Rule-based readiness. Starts neutral (70) and nudges from each available signal
/// relative to your baseline, then bands the result. Every nudge is surfaced as a
/// `Driver` so the score is never a black box.
public enum ReadinessEngine {

    public static func evaluate(_ i: ReadinessInputs) -> Readiness {
        var score = 70.0
        var drivers: [Readiness.Driver] = []
        var signals = 0

        // HRV vs baseline — higher is better.
        if let hrv = i.hrvMs, let base = i.hrvBaselineMs, base > 0 {
            signals += 1
            let dev = (hrv - base) / base
            let pts = clamp(dev * 80, -22, 22)
            score += pts
            let sign: Readiness.Driver.Sign = dev > 0.04 ? .positive : (dev < -0.04 ? .negative : .neutral)
            drivers.append(.init("HRV \(Int(hrv.rounded())) ms (\(pct(dev)) vs baseline)", sign, points: pts, magnitude: 22))
        }

        // Resting HR vs baseline — lower is better.
        if let rhr = i.restingHR, let base = i.restingHRBaseline, base > 0 {
            signals += 1
            let dev = (base - rhr) / base
            let pts = clamp(dev * 120, -16, 12)
            score += pts
            let sign: Readiness.Driver.Sign = dev > 0.02 ? .positive : (dev < -0.02 ? .negative : .neutral)
            drivers.append(.init("Resting HR \(Int(rhr.rounded())) bpm", sign, points: pts, magnitude: 16))
        }

        // Overnight body/wrist temperature vs baseline — a rise flags illness / incomplete
        // recovery. A 0.3°C (~0.5°F) deadband absorbs normal night-to-night skin/wrist-temp noise
        // (wrist temperature swings more than core), so only a real elevation is penalized; cooler
        // gives just a small credit (being a touch cold isn't strongly restorative).
        if let temp = i.bodyTempC, let base = i.bodyTempBaselineC, base > 0 {
            signals += 1
            let devC = temp - base
            let over = devC > 0 ? max(0, devC - 0.3) : min(0, devC + 0.3)
            let pts = clamp(-over * 30, -16, 6)
            score += pts
            let sign: Readiness.Driver.Sign = pts > 1 ? .positive : (pts < -1 ? .negative : .neutral)
            let arrow = devC >= 0 ? "+" : "−"
            drivers.append(.init("Body temp \(arrow)\(String(format: "%.1f", abs(devC)))°C vs baseline",
                                 sign, points: pts, magnitude: 16))
        }

        // Respiratory rate vs baseline — elevated breathing at rest = stress / illness signal.
        // 0.5 br/min deadband for measurement noise; scored in absolute breaths since a rise
        // of even 1–2 br/min over your norm is meaningful.
        if let rr = i.respiratoryRate, let base = i.respiratoryRateBaseline, base > 0 {
            signals += 1
            let delta = rr - base
            let over = delta > 0 ? max(0, delta - 0.5) : min(0, delta + 0.5)
            let pts = clamp(-over * 6, -12, 6)
            score += pts
            let sign: Readiness.Driver.Sign = pts > 1 ? .positive : (pts < -1 ? .negative : .neutral)
            drivers.append(.init(String(format: "Resp rate %.0f br/min", rr), sign, points: pts, magnitude: 12))
        }

        // Sleep vs a 7.5h target.
        if let sleep = i.sleepHours {
            signals += 1
            let pts = clamp((sleep - 7.5) * 6, -18, 10)
            score += pts
            // Sign must track the points it adds, or a "green" driver that actually subtracts
            // (e.g. 7.3h) misleads the contribution bar. Small deadband around the 7.5h target.
            let sign: Readiness.Driver.Sign = pts > 1 ? .positive : (pts < -1 ? .negative : .neutral)
            drivers.append(.init(String(format: "Slept %.1fh", sleep), sign, points: pts, magnitude: 18))
        }

        if i.trainedYesterday {
            score -= 7
            drivers.append(.init("Trained yesterday", .negative, points: -7, magnitude: 7))
        }

        guard signals > 0 else {
            return Readiness(
                score: nil, band: .unknown, drivers: [],
                headline: "No readiness data",
                trainingNote: "Connect Apple Health (HRV, resting HR, sleep) to get a daily readiness read."
            )
        }

        let final = Int(clamp(score, 0, 100).rounded())
        let band: Readiness.Band = final >= 80 ? .primed : (final >= 65 ? .ready : (final >= 45 ? .compromised : .drained))
        return Readiness(score: final, band: band, drivers: drivers,
                         headline: headline(band), trainingNote: note(band))
    }

    // MARK: Copy

    private static func headline(_ b: Readiness.Band) -> String {
        switch b {
        case .primed:      "Primed"
        case .ready:       "Ready"
        case .compromised: "Under-recovered"
        case .drained:     "Drained"
        case .unknown:     "No data"
        }
    }

    private static func note(_ b: Readiness.Band) -> String {
        switch b {
        case .primed:      "Green light — chase your top sets and progress as planned."
        case .ready:       "Recovered. Progress as planned."
        case .compromised: "Hold your loads today, maybe cut a set. Quality over PRs."
        case .drained:     "Consider active rest or a lighter session — don't force new loads."
        case .unknown:     "Connect Apple Health for a readiness read."
        }
    }

    // MARK: Helpers

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
    private static func pct(_ dev: Double) -> String { "\(dev >= 0 ? "+" : "")\(Int((dev * 100).rounded()))%" }
}
