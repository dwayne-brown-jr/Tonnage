import Foundation
import SwiftData

/// A persisted coach chat message, so conversations survive app restarts. Stored in
/// the shared SwiftData store.
///
/// All properties are defaulted (no `.unique`, no required relationships) so this
/// model is already CloudKit-mirroring friendly for the later cloud-sync stage.
@Model
public final class CoachChatMessage {
    public var id: UUID = UUID()
    /// "user" or "assistant" — mirrors `CoachMessage.Role.rawValue` in the app.
    public var roleRaw: String = "user"
    public var text: String = ""
    public var timestamp: Date = Date.now

    public init(id: UUID = UUID(), roleRaw: String, text: String, timestamp: Date = .now) {
        self.id = id
        self.roleRaw = roleRaw
        self.text = text
        self.timestamp = timestamp
    }
}
