import Foundation

/// Barbell plate math: how to load a target weight per side.
public enum PlateMath {

    /// Standard lb plate denominations, heaviest first.
    public static let defaultPlates: [Double] = [45, 35, 25, 10, 5, 2.5]
    public static let defaultBar: Double = 45

    public struct PlatePair: Sendable, Identifiable, Equatable {
        public let plate: Double
        public let perSide: Int
        public var id: Double { plate }
    }

    public struct Loadout: Sendable, Equatable {
        /// Plates to put on EACH side, heaviest first.
        public let perSide: [PlatePair]
        /// The exact weight reachable with the available plates (≤ target).
        public let achievable: Double
        /// Weight per side that couldn't be matched (0 if exact).
        public let remainderPerSide: Double
        public var isExact: Bool { remainderPerSide < 0.001 }
    }

    /// Greedy load of `target` onto a `bar` using `available` plates.
    public static func loadout(target: Double, bar: Double = defaultBar,
                               available: [Double] = defaultPlates) -> Loadout {
        let perSideTarget = max(0, (target - bar) / 2)
        var remaining = perSideTarget
        var pairs: [PlatePair] = []
        for plate in available.sorted(by: >) where plate > 0 {
            let count = Int((remaining + 1e-6) / plate)
            if count > 0 {
                pairs.append(PlatePair(plate: plate, perSide: count))
                remaining -= Double(count) * plate
            }
        }
        let loadedPerSide = perSideTarget - remaining
        return Loadout(perSide: pairs,
                       achievable: bar + 2 * loadedPerSide,
                       remainderPerSide: max(0, remaining))
    }
}
