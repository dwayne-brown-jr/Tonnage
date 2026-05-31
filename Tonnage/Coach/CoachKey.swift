import Foundation

/// Resolves which Anthropic API key the coach should use:
/// 1. the user's own key (entered in Settings → Keychain), if present;
/// 2. otherwise the bundled shared key from `Secrets.swift`, if set.
/// This lets TestFlight testers use the coach without their own key, while still
/// letting anyone override with their own.
enum CoachKey {
    static var resolved: String? {
        if let own = Keychain.read(Keychain.apiKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !own.isEmpty {
            return own
        }
        let bundled = BundledSecrets.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return bundled.isEmpty ? nil : bundled
    }

    static var hasKey: Bool { resolved != nil }

    /// True when the active key is the shared bundled one (not the user's own).
    static var usingSharedKey: Bool {
        let own = Keychain.read(Keychain.apiKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return own.isEmpty && !BundledSecrets.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Caps daily Coach usage when running on the shared bundled key, so a single tester
/// can't run up an unbounded bill on the owner's account. Completely inert when the user
/// has supplied their own key — they're never limited. Counts only successful messages,
/// and rolls over at local midnight.
enum SharedKeyQuota {
    static let dailyLimit = 30
    private static let countKey = "coach.sharedKey.count"
    private static let dayKey = "coach.sharedKey.day"

    /// True if there's at least one message left today — or if the user is on their own
    /// key, in which case there's no cap at all.
    static var hasRemaining: Bool {
        guard CoachKey.usingSharedKey else { return true }
        return used < dailyLimit
    }

    static var remaining: Int { CoachKey.usingSharedKey ? max(0, dailyLimit - used) : .max }

    static var limitMessage: String {
        "You've used today's \(dailyLimit) free Coach messages on the shared key. Add your own Anthropic API key in Settings for unlimited chat — the free allowance resets tomorrow."
    }

    /// Record one successful message against today's allowance. No-op on the user's own key.
    static func recordUse() {
        guard CoachKey.usingSharedKey else { return }
        UserDefaults.standard.set(used + 1, forKey: countKey)   // `used` handles the daily rollover
    }

    private static var used: Int {
        rolloverIfNeeded()
        return UserDefaults.standard.integer(forKey: countKey)
    }

    private static func rolloverIfNeeded() {
        if UserDefaults.standard.string(forKey: dayKey) != todayStamp {
            UserDefaults.standard.set(todayStamp, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }

    private static var todayStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: .now)
    }
}
