import Foundation

/// Decides how the coach reaches Anthropic:
/// 1. the user's own key (entered in Settings → Keychain), if present → call Anthropic directly;
/// 2. otherwise the shared proxy (if a proxy URL is configured) → no key ships in the app;
/// 3. otherwise no backend → the UI prompts the user to add their own key.
enum CoachKey {
    /// The user's own Anthropic key, or nil if they haven't set one.
    static var ownKey: String? {
        let k = Keychain.read(Keychain.apiKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }

    /// The configured shared-proxy endpoint, or nil if none is set (see `BundledSecrets`).
    static var proxyURL: URL? {
        let s = BundledSecrets.proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s) else { return nil }
        return url
    }

    /// The route a request should take, or nil when there's no usable backend.
    static var route: CoachRoute? {
        if let own = ownKey { return .direct(apiKey: own) }
        if let proxy = proxyURL { return .proxy(url: proxy) }
        return nil
    }

    /// True when the coach can run at all (own key OR shared proxy available).
    static var hasBackend: Bool { route != nil }

    /// True when the athlete is on the shared proxy (no own key) — the path the daily
    /// free-message quota applies to.
    static var usingSharedProxy: Bool { ownKey == nil && proxyURL != nil }
}

/// Stable per-install identifier sent to the proxy so it can meter the shared-key quota
/// per device. Not tied to any Apple identifier; resets on reinstall.
enum DeviceID {
    private static let key = "coach.deviceID"
    static var current: String {
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// Display-only view of the shared-key daily allowance. Enforcement now lives SERVER-SIDE
/// in the proxy (so it can't be bypassed by reinstalling); the proxy returns how many
/// messages remain in an `x-quota-remaining` header, which we cache here just to show the
/// athlete. Inert when the user is on their own key (no cap).
enum SharedKeyQuota {
    static var usingSharedKey: Bool { CoachKey.usingSharedProxy }

    private static let remainingKey = "coach.sharedKey.remaining"

    /// Last remaining count the proxy reported, or nil if we haven't called yet today.
    static var cachedRemaining: Int? { UserDefaults.standard.object(forKey: remainingKey) as? Int }

    static func cacheRemaining(_ n: Int) { UserDefaults.standard.set(max(0, n), forKey: remainingKey) }

    static var limitMessage: String {
        "You've used today's free Coach messages on the shared key. Add your own Anthropic API key in Settings for unlimited chat — the free allowance resets tomorrow."
    }
}
