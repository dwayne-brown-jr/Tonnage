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

    var hasKey: Bool { CoachKey.hasKey }

    /// Attach the store and load any saved conversation. Safe to call repeatedly.
    func configure(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadHistory()
    }

    func send(_ userText: String, system: String, model: CoachModel) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let key = CoachKey.resolved else {
            errorText = CoachError.missingKey.errorDescription
            return
        }

        errorText = nil
        append(CoachMessage(role: .user, text: trimmed))
        isSending = true
        defer { isSending = false }

        do {
            let reply = try await AnthropicClient(apiKey: key)
                .send(system: system, history: messages, model: model, maxTokens: model == .opus ? 1800 : 1024)
            append(CoachMessage(role: .assistant, text: reply))
        } catch {
            errorText = (error as? CoachError)?.errorDescription ?? error.localizedDescription
        }
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
