import Foundation
import SwiftData

/// A tracked body measurement (circumference or body-fat %). Bodyweight stays in
/// HealthKit — this covers the tape-measure metrics Health doesn't.
public enum MeasurementType: String, Codable, CaseIterable, Sendable, Identifiable {
    case shoulders, chest, arm, waist, hips, thigh, calf, neck, bodyFat

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shoulders: "Shoulders"
        case .chest:     "Chest"
        case .arm:       "Arm"
        case .waist:     "Waist"
        case .hips:      "Hips"
        case .thigh:     "Thigh"
        case .calf:      "Calf"
        case .neck:      "Neck"
        case .bodyFat:   "Body Fat"
        }
    }

    /// Unit suffix shown in the UI.
    public var unit: String { self == .bodyFat ? "%" : "in" }

    /// True when a smaller number is generally the goal (waist, body fat); the UI tints
    /// deltas accordingly (down = good for these, up = good for the rest).
    public var lowerIsBetter: Bool { self == .waist || self == .bodyFat }

    /// Forgiving match for free-form labels (e.g. from the photo estimator): handles
    /// synonyms and underscores so "bicep" → .arm, "body_fat" → .bodyFat, etc.
    public static func loose(_ s: String) -> MeasurementType? {
        let n = s.lowercased().replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch n {
        case "shoulders", "shoulder", "delts", "deltoids": return .shoulders
        case "chest", "pecs", "bust": return .chest
        case "arm", "arms", "bicep", "biceps", "upper arm": return .arm
        case "waist", "stomach", "abdomen", "belly": return .waist
        case "hips", "hip", "glutes": return .hips
        case "thigh", "thighs", "quad", "quads", "leg", "legs": return .thigh
        case "calf", "calves": return .calf
        case "neck": return .neck
        case "body fat", "bodyfat", "body fat %", "body fat percentage", "bf", "bf%": return .bodyFat
        default: return MeasurementType(rawValue: s)
        }
    }
}

/// One logged measurement. CloudKit-friendly: every stored property has a default and
/// there are no unique constraints or required relationships.
@Model
public final class BodyMeasurement {
    public var type: MeasurementType = MeasurementType.waist
    public var value: Double = 0
    public var date: Date = Date.now

    public init(type: MeasurementType, value: Double, date: Date = .now) {
        self.type = type
        self.value = value
        self.date = date
    }
}

/// Pure, testable reductions over logged measurements — kept out of the views so the
/// "latest + delta" and trend logic can be unit-tested without SwiftData.
public enum BodyMetrics {

    public struct Point: Sendable, Equatable, Identifiable {
        public let date: Date
        public let value: Double
        public var id: Date { date }
        public init(date: Date, value: Double) { self.date = date; self.value = value }
    }

    public struct Latest: Sendable, Equatable, Identifiable {
        public let type: MeasurementType
        public let value: Double
        public let date: Date
        /// value − the previous entry of the same type (nil when it's the first).
        public let delta: Double?
        public var id: MeasurementType { type }
        public init(type: MeasurementType, value: Double, date: Date, delta: Double?) {
            self.type = type; self.value = value; self.date = date; self.delta = delta
        }
    }

    /// Most-recent value per type (with delta from the prior entry), ordered by the
    /// canonical `MeasurementType.allCases` order so the grid is stable.
    public static func latest(_ measurements: [BodyMeasurement]) -> [Latest] {
        MeasurementType.allCases.compactMap { type in
            let entries = measurements.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard let last = entries.last else { return nil }
            let delta = entries.count >= 2 ? last.value - entries[entries.count - 2].value : nil
            return Latest(type: type, value: last.value, date: last.date, delta: delta)
        }
    }

    /// Time-ordered series for one measurement type (for the trend chart).
    public static func series(of type: MeasurementType, in measurements: [BodyMeasurement]) -> [Point] {
        measurements
            .filter { $0.type == type }
            .sorted { $0.date < $1.date }
            .map { Point(date: $0.date, value: $0.value) }
    }

    /// Measurement types that have at least one logged entry, in canonical order.
    public static func trackedTypes(in measurements: [BodyMeasurement]) -> [MeasurementType] {
        let present = Set(measurements.map(\.type))
        return MeasurementType.allCases.filter { present.contains($0) }
    }
}
