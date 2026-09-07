import Foundation

/// Generates a classic warm-up ramp toward a working weight: lighter × more reps
/// stepping up to heavier × few, so the lifter is primed without burning working
/// capacity. Equipment-agnostic (percent-based) so it works for barbells, dumbbells,
/// and machines alike.
public enum WarmupRamp {

    public struct Step: Equatable, Sendable {
        public let weight: Double
        public let reps: Int

        public init(weight: Double, reps: Int) {
            self.weight = weight
            self.reps = reps
        }
    }

    /// Ramp steps for a working weight (lb), rounded to 5 lb:
    /// 40% × 8 → 60% × 5 → 80% × 3. Light working weights get a single 50% × 8;
    /// anything under 20 lb needs no ramp at all. Steps that round into each other
    /// or up to the working weight are dropped.
    public static func steps(workingWeight: Double) -> [Step] {
        guard workingWeight >= 20 else { return [] }
        guard workingWeight >= 50 else {
            let w = round5(workingWeight * 0.5)
            return w > 0 && w < workingWeight ? [Step(weight: w, reps: 8)] : []
        }
        let fractions: [(fraction: Double, reps: Int)] = [(0.4, 8), (0.6, 5), (0.8, 3)]
        var result: [Step] = []
        for f in fractions {
            let w = round5(workingWeight * f.fraction)
            guard w > 0, w < workingWeight, result.last?.weight != w else { continue }
            result.append(Step(weight: w, reps: f.reps))
        }
        return result
    }

    private static func round5(_ x: Double) -> Double { (x / 5).rounded() * 5 }
}
