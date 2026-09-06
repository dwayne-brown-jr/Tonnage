import Foundation

/// Models the coach can run. Haiku for everyday chat (cheap/fast); Opus for deeper
/// weekly reviews. (Verified against docs.claude.com — Messages API v2023-06-01.)
enum CoachModel: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-4-5"
    case opus = "claude-opus-4-8"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .haiku: "Fast · Haiku 4.5"
        case .opus:  "Deep · Opus 4.8"
        }
    }
}

struct CoachMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum CoachError: LocalizedError {
    case missingKey
    case network
    case http(Int, String)
    case serverUnavailable
    case decoding
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings to chat with your coach."
        case .network:    "Couldn't reach the network. Check your connection and try again."
        case .http(401, _): "Your API key was rejected (401). Double-check it in Settings."
        // 429 from the proxy carries the friendly daily-quota message — surface it directly.
        case .http(429, let message): message == "unknown" ? "Rate limited — give it a moment, then try again." : message
        case .http(let code, let message): "API error \(code): \(message)"
        case .serverUnavailable:
            "Coach is unavailable right now. Try again shortly — or add your own Anthropic API key in Settings for unlimited access."
        case .decoding:   "Got an unexpected response from the API."
        case .empty:      "The coach didn't return anything — try rephrasing."
        }
    }
}

/// Where a coach request goes: straight to Anthropic with the user's own key, or through
/// our proxy (which holds the shared key server-side, so nothing ships in the binary).
enum CoachRoute {
    case direct(apiKey: String)
    case proxy(url: URL)
}

/// Thin async wrapper over the Anthropic Messages API (direct or via the proxy).
struct AnthropicClient {
    let route: CoachRoute
    private let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Builds the request for whichever route. Direct calls carry the key + version header;
    /// proxied calls carry only a device id (for the server-side quota) — the proxy injects
    /// the key + version itself.
    private func makeRequest(timeout: TimeInterval) -> URLRequest {
        let url: URL
        switch route {
        case .direct: url = anthropicEndpoint
        case .proxy(let proxyURL): url = proxyURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch route {
        case .direct(let apiKey):
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .proxy:
            request.setValue(DeviceID.current, forHTTPHeaderField: "x-device-id")
        }
        return request
    }

    /// Reads the proxy's remaining-quota header (if present) into the display cache.
    private func cacheQuota(from response: URLResponse) {
        if case .proxy = route,
           let http = response as? HTTPURLResponse,
           let header = http.value(forHTTPHeaderField: "x-quota-remaining"),
           let n = Int(header) {
            SharedKeyQuota.cacheRemaining(n)
        }
    }

    func send(system: String, history: [CoachMessage], model: CoachModel, maxTokens: Int = 1024,
              timeout: TimeInterval = 60) async throws -> String {
        var request = makeRequest(timeout: timeout)

        let body = RequestBody(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: history.map { .init(role: $0.role.rawValue, content: $0.text) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CoachError.network
        }

        guard let http = response as? HTTPURLResponse else { throw CoachError.network }
        cacheQuota(from: response)
        guard http.statusCode == 200 else { throw failure(status: http.statusCode, data: data) }
        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw CoachError.decoding
        }
        let text = decoded.content.first(where: { $0.type == "text" })?.text ?? ""
        guard !text.isEmpty else { throw CoachError.empty }
        return text
    }

    /// Single-shot vision call: one user message carrying a JPEG image + a text prompt.
    /// Used by the photo body-measurement estimate. Same auth + error handling as `send`.
    func sendVision(system: String, userText: String, jpegBase64: String,
                    model: CoachModel, maxTokens: Int = 1024) async throws -> String {
        var request = makeRequest(timeout: 90)

        let body = VisionRequestBody(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: [
                .image(mediaType: "image/jpeg", base64: jpegBase64),
                .text(userText)
            ])]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CoachError.network
        }
        guard let http = response as? HTTPURLResponse else { throw CoachError.network }
        cacheQuota(from: response)
        guard http.statusCode == 200 else { throw failure(status: http.statusCode, data: data) }
        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else { throw CoachError.decoding }
        let text = decoded.content.first(where: { $0.type == "text" })?.text ?? ""
        guard !text.isEmpty else { throw CoachError.empty }
        return text
    }

    /// On the proxy route the user supplied no key, so an upstream failure is ours, not
    /// theirs — surfacing its text would tell them to fix a billing account they don't have.
    /// The 429 is the exception: that one carries our own daily-quota copy.
    private func failure(status: Int, data: Data) -> CoachError {
        if case .proxy = route, status != 429 { return .serverUnavailable }
        return .http(status, Self.parseError(data))
    }

    private static func parseError(_ data: Data) -> String {
        struct APIError: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        return (try? JSONDecoder().decode(APIError.self, from: data))?.error.message ?? "unknown"
    }

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ResponseBody: Decodable {
        let content: [Block]
        struct Block: Decodable { let type: String; let text: String? }
    }

    /// Request body for a vision call — `content` is an array of typed blocks (image +
    /// text) rather than a plain string, per the Messages API image format.
    private struct VisionRequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [Block]
        }

        enum Block: Encodable {
            case text(String)
            case image(mediaType: String, base64: String)

            private enum Keys: String, CodingKey { case type, text, source }
            private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                switch self {
                case .text(let t):
                    try c.encode("text", forKey: .type)
                    try c.encode(t, forKey: .text)
                case .image(let mediaType, let base64):
                    try c.encode("image", forKey: .type)
                    var src = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                    try src.encode("base64", forKey: .type)
                    try src.encode(mediaType, forKey: .mediaType)
                    try src.encode(base64, forKey: .data)
                }
            }
        }
    }
}
