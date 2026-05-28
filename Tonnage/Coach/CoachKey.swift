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
