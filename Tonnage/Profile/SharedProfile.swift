import Foundation
import TonnageCore

/// Bridges the athlete's starting point to the shared App Group container so the Tonnage
/// Fuel companion app can pick up the matching nutrition goal — answered once in Tonnage,
/// acted on in both apps. No-op if the App Group entitlement isn't present.
enum SharedProfile {
    static let suiteName = "group.com.dwayne.tonnage"
    private static var store: UserDefaults? { UserDefaults(suiteName: suiteName) }

    enum Key {
        static let startingPoint = "shared.startingPoint"      // StartingPoint rawValue
        static let recommendedGoal = "shared.recommendedGoal"  // Tonnage Fuel Goal rawValue
        static let updatedAt = "shared.updatedAt"
    }

    /// Write a starting point + its recommended Fuel goal to the shared store, and publish
    /// the full `shared.v1.profile` JSON record alongside it (age / sex / height / weight /
    /// goal / experience / days per week) so Fuel can seed macro defaults without re-asking.
    static func write(_ startingPoint: StartingPoint) {
        guard let store else { return }
        store.set(startingPoint.rawValue, forKey: Key.startingPoint)
        if let goal = startingPoint.fuelGoalRaw {
            store.set(goal, forKey: Key.recommendedGoal)
        } else {
            store.removeObject(forKey: Key.recommendedGoal)
        }
        store.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)

        // The caller may have just written the starting point to @AppStorage; take the
        // passed value as authoritative rather than racing the defaults read.
        var profile = ProfileStore.current
        profile.startingPoint = startingPoint
        FuelBridge.writeProfile(profile, defaults: store)
    }

    /// Mirror the current profile's starting point into the shared store. Called at launch
    /// so existing users who set it before this shipped still propagate it to Fuel.
    static func syncFromProfile() {
        write(ProfileStore.current.startingPoint)
    }
}
