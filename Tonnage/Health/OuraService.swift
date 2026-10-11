import Foundation
import TonnageCore

/// Connects to the user's Oura account and reads today's readiness and last night's sleep.
///
/// Oura's API is OAuth-only and its token endpoint needs the client secret, so the two
/// secret-bearing steps (code exchange, token refresh) go through Tonnage's proxy
/// (`proxy/worker.js`, `/oura/*`). Everything else — the tokens (Keychain) and the data
/// calls to api.ouraring.com — stays on the phone, so Oura data never touches our server.
@MainActor
@Observable
final class OuraService {
    static let shared = OuraService()

    enum Status: Equatable {
        case disconnected
        case connected
        /// Oura rejected the saved sign-in (revoked, expired) — the user needs to connect again.
        case needsReconnect
        /// Oura refuses API access without an active membership.
        case membershipRequired
    }

    enum OuraError: LocalizedError {
        case notConfigured, cancelled, denied, stateMismatch, reconnect, membership, network

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Oura isn't set up in this build."
            case .cancelled:     "Oura sign-in was cancelled."
            case .denied:        "Oura access wasn't granted."
            case .stateMismatch: "That Oura sign-in didn't match this request. Try again."
            case .reconnect:     "Your Oura sign-in expired. Connect again."
            case .membership:    "Oura only shares data with an active Oura membership."
            case .network:       "Couldn't reach Oura. Check your connection and try again."
            }
        }
    }

    /// The Oura OAuth app's client id. Not a secret (it's in every authorize URL); the
    /// secret lives only in the proxy.
    static let clientID = "eea06ed5-b60a-41b8-91b2-36a7d9afad55"
    /// Readiness + sleep come from `daily`; HRV/heart rate detail from `heartrate`.
    static let scopes = "daily personal heartrate"
    private static let apiBase = URL(string: "https://api.ouraring.com/v2/usercollection/")!

    private enum Key {
        static let access = "oura.accessToken"
        static let refresh = "oura.refreshToken"
        static let expiresAt = "oura.expiresAt"
    }

    private(set) var status: Status
    private(set) var lastSyncedAt: Date?
    /// Whether Oura had a score for today at the last sync (false = ring not synced yet).
    private(set) var hasTodayScore = false
    private var pendingState: String?
    /// One refresh at a time: Oura rotates refresh tokens, so two concurrent refreshes
    /// would invalidate each other.
    private var refreshTask: Task<Void, Error>?

    private init() {
        status = Keychain.read(Key.refresh) != nil ? .connected : .disconnected
    }

    var isConnected: Bool { status == .connected }

    /// Worth a re-read: connected and not synced in the last 15 minutes.
    var isStale: Bool {
        guard isConnected else { return false }
        return lastSyncedAt.map { Date.now.timeIntervalSince($0) > 15 * 60 } ?? true
    }

    // MARK: Connect

    private var redirectURI: String? {
        CoachKey.proxyURL.map { $0.appendingPathComponent("oura/callback").absoluteString }
    }

    /// The Oura consent page to open, with a fresh `state` remembered for the callback.
    func authorizationURL() -> URL? {
        guard let redirectURI else { return nil }
        let state = UUID().uuidString
        pendingState = state
        var c = URLComponents(string: "https://cloud.ouraring.com/oauth/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state),
        ]
        return c.url
    }

    /// Finishes the sign-in from the `tonnage://oura?code=…&state=…` callback.
    func completeConnection(callbackURL: URL) async throws {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        defer { pendingState = nil }
        if let error = value("error") { throw error == "access_denied" ? OuraError.denied : OuraError.reconnect }
        guard let state = value("state"), state == pendingState else { throw OuraError.stateMismatch }
        guard let code = value("code") else { throw OuraError.reconnect }
        let tokens = try await tokenRequest(path: "oura/token", body: ["code": code])
        store(tokens)
        status = .connected
    }

    func disconnect() {
        Keychain.delete(Key.access)
        Keychain.delete(Key.refresh)
        Keychain.delete(Key.expiresAt)
        status = .disconnected
        lastSyncedAt = nil
        hasTodayScore = false
    }

    // MARK: Read

    /// Today's readiness from Oura, or nil when not connected, offline, or Oura has no score
    /// for today yet. Never throws — readiness falls back to Health in all those cases.
    func todayReadiness(now: Date = .now) async -> Readiness? {
        guard isConnected else { return nil }
        let cal = Calendar.current
        let start = OuraReadiness.dayString(cal.date(byAdding: .day, value: -1, to: now) ?? now)
        let end = OuraReadiness.dayString(cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let range = [URLQueryItem(name: "start_date", value: start), URLQueryItem(name: "end_date", value: end)]
        do {
            let readiness: OuraPage<OuraDailyReadiness> = try await get("daily_readiness", query: range)
            let sleep: OuraPage<OuraSleepPeriod>? = try? await get("sleep", query: range)
            let result = OuraReadiness.today(from: readiness.data, sleep: sleep?.data ?? [], now: now)
            lastSyncedAt = .now
            hasTodayScore = result != nil
            return result
        } catch OuraError.reconnect {
            disconnect()
            status = .needsReconnect
            return nil
        } catch OuraError.membership {
            status = .membershipRequired
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Plumbing

    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    private func store(_ t: Tokens) {
        Keychain.save(t.access_token, for: Key.access)
        if let r = t.refresh_token { Keychain.save(r, for: Key.refresh) }
        let expiry = Date.now.addingTimeInterval((t.expires_in ?? 86_400) - 120)
        Keychain.save(String(expiry.timeIntervalSince1970), for: Key.expiresAt)
    }

    private var accessTokenIsFresh: Bool {
        guard Keychain.read(Key.access) != nil,
              let s = Keychain.read(Key.expiresAt), let t = Double(s) else { return false }
        return Date(timeIntervalSince1970: t) > .now
    }

    /// GET an Oura usercollection endpoint, refreshing the token first if it's expired and
    /// once more if Oura still says 401.
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        if !accessTokenIsFresh { try await refreshTokens() }
        do {
            return try await rawGet(path, query: query)
        } catch OuraError.reconnect {
            try await refreshTokens()
            return try await rawGet(path, query: query)
        }
    }

    private func rawGet<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard let token = Keychain.read(Key.access) else { throw OuraError.reconnect }
        var c = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query
        var request = URLRequest(url: c.url!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200: break
        case 401: throw OuraError.reconnect
        case 403: throw OuraError.membership
        default: throw OuraError.network
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw OuraError.network }
        return decoded
    }

    private func refreshTokens() async throws {
        if let running = refreshTask { return try await running.value }
        let task = Task { @MainActor in
            guard let refresh = Keychain.read(Key.refresh) else { throw OuraError.reconnect }
            let tokens = try await tokenRequest(path: "oura/refresh", body: ["refresh_token": refresh])
            store(tokens)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    /// POST to the proxy's Oura endpoint (app token required).
    private func tokenRequest(path: String, body: [String: String]) async throws -> Tokens {
        guard let base = CoachKey.proxyURL, !BundledSecrets.proxyAppToken.isEmpty else { throw OuraError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BundledSecrets.proxyAppToken, forHTTPHeaderField: "x-app-token")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200:
            guard let tokens = try? JSONDecoder().decode(Tokens.self, from: data) else { throw OuraError.network }
            return tokens
        case 401: throw OuraError.reconnect
        default: throw OuraError.network
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OuraError.network }
            return (data, http)
        } catch let e as OuraError {
            throw e
        } catch {
            throw OuraError.network
        }
    }
}
