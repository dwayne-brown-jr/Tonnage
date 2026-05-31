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
    case decoding
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings to chat with your coach."
        case .network:    "Couldn't reach the network. Check your connection and try again."
        case .http(401, _): "Your API key was rejected (401). Double-check it in Settings."
        case .http(429, _): "Rate limited (429). Give it a moment, then try again."
        case .http(let code, let message): "API error \(code): \(message)"
        case .decoding:   "Got an unexpected response from the API."
        case .empty:      "The coach didn't return anything — try rephrasing."
        }
    }
}

/// Thin async wrapper over the Anthropic Messages API.
struct AnthropicClient {
    let apiKey: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func send(system: String, history: [CoachMessage], model: CoachModel, maxTokens: Int = 1024) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

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
        guard http.statusCode == 200 else {
            throw CoachError.http(http.statusCode, Self.parseError(data))
        }
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

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
        guard http.statusCode == 200 else { throw CoachError.http(http.statusCode, Self.parseError(data)) }
        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else { throw CoachError.decoding }
        let text = decoded.content.first(where: { $0.type == "text" })?.text ?? ""
        guard !text.isEmpty else { throw CoachError.empty }
        return text
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
