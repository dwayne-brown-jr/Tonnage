import Foundation

/// The one-line "Today" verdict at the top of TRAIN — fuses the day's readiness band with
/// today's planned focus so the readiness card reads as an actionable plan, not just a score.
public enum TodayPlan {

    public static func verdict(band: Readiness.Band, focus: String?, dayType: DayType) -> String {
        if dayType != .lift {
            return dayType == .activeRest
                ? "Active recovery — easy conditioning, keep it light."
                : "Full rest — eat, sleep, let the work catch up."
        }
        let f = (focus?.isEmpty == false) ? focus! : "today's session"
        switch band {
        case .primed:      return "Primed — go hard on \(f), chase your top sets."
        case .ready:       return "Recovered — progress \(f) as planned."
        case .compromised: return "Under-recovered — hold loads on \(f); quality over PRs."
        case .drained:     return "Drained — keep \(f) light, or take active rest."
        case .unknown:
            return focus.flatMap { $0.isEmpty ? nil : $0 }.map { "\($0) today — connect Apple Health for a readiness read." }
                ?? "Connect Apple Health for a daily readiness read."
        }
    }
}
