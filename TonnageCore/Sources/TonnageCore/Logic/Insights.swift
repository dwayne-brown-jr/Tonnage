import Foundation

/// Pure trend math over a chronological (oldest → newest) series of values. Kept free of
/// SwiftUI/HealthKit so it's unit-testable; callers map their `DatedValue` series to `[Double]`.
public enum TrendEngine {
    public enum Direction: Sendable, Equatable { case rising, flat, falling }

    /// Least-squares slope across the series, classified with a deadband so small noise
    /// reads as `flat`. `band` is the fraction of the series mean the *projected change*
    /// across the window must exceed to count as rising/falling.
    public static func direction(_ values: [Double], minPoints: Int = 4, band: Double = 0.05) -> Direction {
        guard values.count >= minPoints else { return .flat }
        let n = Double(values.count)
        let xs = (0..<values.count).map(Double.init)
        let meanX = xs.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n
        let cov = zip(xs, values).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let varX = xs.reduce(0.0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard varX > 0 else { return .flat }
        let slope = cov / varX                 // value change per step
        let projected = slope * (n - 1)        // change across the whole window
        let ref = max(abs(meanY), 1) * band
        if projected > ref { return .rising }
        if projected < -ref { return .falling }
        return .flat
    }

    /// How many of the last `window` values fall below `threshold`.
    public static func countBelow(_ values: [Double], threshold: Double, window: Int) -> Int {
        values.suffix(window).filter { $0 < threshold }.count
    }

    /// A strength stall: the most recent `lookback` e1RMs haven't beaten the prior best by
    /// more than `tol` (1% default). Needs enough history to judge.
    public static func isStalled(_ e1rms: [Double], lookback: Int = 3, tol: Double = 0.01) -> Bool {
        guard e1rms.count >= lookback + 1 else { return false }
        let priorBest = e1rms.prefix(e1rms.count - lookback).max() ?? 0
        guard priorBest > 0 else { return false }
        let recentBest = e1rms.suffix(lookback).max() ?? 0
        return recentBest <= priorBest * (1 + tol)
    }
}

/// One piece of plain-language coaching surfaced from the trends (Oura-style storytelling).
public struct TrainingInsight: Sendable, Equatable, Identifiable {
    public enum Severity: Sendable, Equatable { case positive, info, caution }
    public let id: String
    public let severity: Severity
    public let systemImage: String
    public let title: String
    public let message: String

    public init(id: String, severity: Severity, systemImage: String, title: String, message: String) {
        self.id = id
        self.severity = severity
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }
}

/// Turns recovery + strength trends into a short, prioritized list of insights. The headline
/// rule is an ADVISORY deload nudge — it never mutates the plan, so it can't fight the
/// calendar (Week-5) deload or the day-level readiness hold; it just tells the truth.
public enum InsightEngine {
    public struct Inputs: Sendable {
        public var readiness: [Double]                    // chronological readiness scores
        public var hrv: [Double]                          // chronological HRV (ms)
        public var lifts: [Lift]                          // per main lift, chronological e1RM
        public var currentWeek: Int
        public var deloadWeek: Int

        public struct Lift: Sendable { public let name: String; public let e1rm: [Double]
            public init(name: String, e1rm: [Double]) { self.name = name; self.e1rm = e1rm } }

        public init(readiness: [Double], hrv: [Double], lifts: [Lift],
                    currentWeek: Int, deloadWeek: Int = 5) {
            self.readiness = readiness; self.hrv = hrv; self.lifts = lifts
            self.currentWeek = currentWeek; self.deloadWeek = deloadWeek
        }
    }

    public static func generate(_ i: Inputs) -> [TrainingInsight] {
        var out: [TrainingInsight] = []

        let readinessDir = TrendEngine.direction(i.readiness)
        let hrvDir = TrendEngine.direction(i.hrv)
        let compromisedDays = TrendEngine.countBelow(i.readiness, threshold: 65, window: 5)
        let stalled = i.lifts.filter { TrendEngine.isStalled($0.e1rm) }.map(\.name)
        let recoverySlipping = readinessDir == .falling || compromisedDays >= 3

        // Headline: advisory deload when recovery is slipping AND a main lift has stalled,
        // and you're not already on your planned deload week.
        if recoverySlipping, let lift = stalled.first, i.currentWeek != i.deloadWeek {
            out.append(.init(
                id: "deload", severity: .caution, systemImage: "arrow.down.circle",
                title: "Consider a deload",
                message: "Recovery is trending down and \(lift) has stalled — a lighter (deload) week could let your progress catch up."))
        } else {
            if readinessDir == .falling {
                out.append(.init(
                    id: "readiness-down", severity: .caution, systemImage: "chart.line.downtrend.xyaxis",
                    title: "Readiness trending down",
                    message: "Your readiness has slipped over the past week. Prioritize sleep, and hold loads on under-recovered days."))
            } else if hrvDir == .falling {
                out.append(.init(
                    id: "hrv-down", severity: .caution, systemImage: "waveform.path.ecg",
                    title: "HRV trending down",
                    message: "Your HRV is drifting below baseline — an early sign recovery may be slipping. Watch sleep and stress."))
            }
            for name in stalled.prefix(2) {
                out.append(.init(
                    id: "stall-\(name)", severity: .info, systemImage: "minus.circle",
                    title: "\(name) has stalled",
                    message: "No e1RM progress on \(name) lately. Try a small load bump, an extra rep, or back off then re-approach."))
            }
        }

        // Positive reinforcement only when nothing needs attention.
        if out.isEmpty && readinessDir == .rising {
            out.append(.init(
                id: "readiness-up", severity: .positive, systemImage: "chart.line.uptrend.xyaxis",
                title: "Recovery trending up",
                message: "Readiness is climbing — a good window to push your top sets."))
        }

        return out
    }
}
