import Foundation

/// The App Group shared between the app and its extensions. The same identifier must
/// be enabled (Signing & Capabilities → App Groups) on every target that reads or
/// writes the snapshot — currently the app and the widget extension.
public enum AppGroup {
    public static let id = "group.com.dwayne.tonnage"
    /// Shared defaults suite. `nil` only if the App Group capability isn't wired up
    /// (e.g. before the entitlement is added) — callers degrade gracefully.
    public static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// A small, read-mostly snapshot of the current training state that the home-screen
/// widget renders. The app owns the SwiftData store and writes this; the widget only
/// reads it (extensions can't open the app's container without extra plumbing, and a
/// tiny JSON blob in shared defaults is cheaper and refresh-friendly).
public struct WidgetSnapshot: Codable, Hashable {
    public var block: Int
    public var week: Int
    public var sessionName: String
    public var sessionFocus: String
    public var weekSets: Int
    public var weekReps: Int
    public var weekVolume: Double
    public var updated: Date

    public init(block: Int, week: Int, sessionName: String, sessionFocus: String,
                weekSets: Int, weekReps: Int, weekVolume: Double, updated: Date = .now) {
        self.block = block
        self.week = week
        self.sessionName = sessionName
        self.sessionFocus = sessionFocus
        self.weekSets = weekSets
        self.weekReps = weekReps
        self.weekVolume = weekVolume
        self.updated = updated
    }

    public static let defaultsKey = "widget.snapshot"

    /// Persist into the shared App Group container.
    public func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.defaultsKey)
    }

    /// The latest snapshot the app wrote, if any.
    public static func read() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: Self.defaultsKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    /// Stand-in for the widget gallery / first launch before any real data exists.
    public static var placeholder: WidgetSnapshot {
        .init(block: 1, week: 1, sessionName: "Upper A", sessionFocus: "Push focus",
              weekSets: 0, weekReps: 0, weekVolume: 0)
    }
}
