import Foundation
import SwiftData
import TonnageCore

/// Owns the coach conversation + networking. The view supplies the freshly-built
/// system context (program + logs + recovery) on each send.
///
/// Messages are persisted to SwiftData (`CoachChatMessage`) so the conversation
/// survives app restarts; the in-memory `messages` array drives the UI.
@MainActor
@Observable
final class CoachViewModel {
    private(set) var messages: [CoachMessage] = []
    private(set) var isSending = false
    var errorText: String?

    @ObservationIgnored private var context: ModelContext?

    var hasKey: Bool { CoachKey.hasBackend }
    /// Shared-key daily allowance — surfaced in the UI so testers see it. nil until the
    /// proxy reports a remaining count (enforcement is server-side now).
    var usingSharedKey: Bool { CoachKey.usingSharedProxy }
    var quotaRemaining: Int? { SharedKeyQuota.cachedRemaining }
    /// A turn failed if the transcript ends on a user message with no reply — offer a retry.
    var canRetry: Bool { !isSending && messages.last?.role == .user }

    /// How many trailing messages of the transcript we actually send to the API. The full
    /// conversation is persisted for display, but re-sending all of it every turn would
    /// grow input tokens (and cost) without bound — so we bound the wire payload here.
    private static let historyWindow = 20

    /// Attach the store and load any saved conversation. Safe to call repeatedly.
    func configure(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadHistory()
    }

    func send(_ userText: String, system: String, model: CoachModel) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let route = CoachKey.route else {
            errorText = CoachError.missingKey.errorDescription
            return
        }
        // The shared-key daily cap is enforced server-side by the proxy now (so it can't be
        // bypassed by reinstalling); an over-quota call comes back as a friendly 429.
        errorText = nil
        append(CoachMessage(role: .user, text: trimmed))
        isSending = true
        defer { isSending = false }

        do {
            let reply = try await AnthropicClient(route: route)
                .send(system: system, history: windowed(messages), model: model, maxTokens: model == .opus ? 1800 : 1024, timeout: 35)
            append(CoachMessage(role: .assistant, text: reply))
        } catch {
            errorText = (error as? CoachError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Re-send the last user message after a failed turn, without duplicating its bubble
    /// (the failed turn left it as the transcript tail).
    func retryLast(system: String, model: CoachModel) async {
        guard canRetry else { return }
        guard let route = CoachKey.route else {
            errorText = CoachError.missingKey.errorDescription
            return
        }
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await AnthropicClient(route: route)
                .send(system: system, history: windowed(messages), model: model, maxTokens: model == .opus ? 1800 : 1024, timeout: 35)
            append(CoachMessage(role: .assistant, text: reply))
        } catch {
            errorText = (error as? CoachError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Trailing window of the transcript, trimmed so it begins on a user message — the
    /// Messages API requires the first entry in `messages` to be from the user.
    private func windowed(_ all: [CoachMessage]) -> [CoachMessage] {
        var window = Array(all.suffix(Self.historyWindow))
        while let first = window.first, first.role != .user { window.removeFirst() }
        return window
    }

    func clear() {
        messages.removeAll()
        errorText = nil
        try? context?.delete(model: CoachChatMessage.self)
        try? context?.save()
    }

    // MARK: Persistence

    private func append(_ message: CoachMessage) {
        messages.append(message)
        guard let context else { return }
        context.insert(CoachChatMessage(id: message.id, roleRaw: message.role.rawValue, text: message.text))
        try? context.save()
    }

    private func loadHistory() {
        guard let context else { return }
        let descriptor = FetchDescriptor<CoachChatMessage>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        guard let saved = try? context.fetch(descriptor) else { return }
        messages = saved.compactMap { m in
            guard let role = CoachMessage.Role(rawValue: m.roleRaw) else { return nil }
            return CoachMessage(id: m.id, role: role, text: m.text)
        }
    }
}
