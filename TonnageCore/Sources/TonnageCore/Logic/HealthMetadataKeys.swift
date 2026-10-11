import Foundation

/// Custom metadata keys stamped on every HealthKit lift workout Tonnage writes (phone
/// `HKWorkoutBuilder` + watch `HKLiveWorkoutBuilder`). Tonnage Fuel reads these literal
/// strings straight off the workout, so they're frozen here — never rename a key without
/// versioning it.
public enum HealthMetadataKeys {
    /// Value for `HKMetadataKeyWorkoutBrandName` (the HK constant lives in HealthKit; the
    /// app targets add it so this package stays HealthKit-free).
    public static let brandName = "Tonnage"

    public static let sessionName   = "com.dwayne.tonnage.sessionName"     // String
    public static let totalVolumeLb = "com.dwayne.tonnage.totalVolumeLb"   // Double
    public static let setCount      = "com.dwayne.tonnage.setCount"        // Int
    public static let totalReps     = "com.dwayne.tonnage.totalReps"       // Int
    public static let block         = "com.dwayne.tonnage.block"           // Int
    public static let week          = "com.dwayne.tonnage.week"            // Int
    public static let isDeload      = "com.dwayne.tonnage.isDeload"        // Bool
    public static let topSetRPE     = "com.dwayne.tonnage.topSetRPE"       // Double, omitted if unknown
}

/// What a finished (or in-progress) lift session looks like to HealthKit — the values
/// behind `HealthMetadataKeys`. Built from a `LoggedWorkout` on the phone or from the
/// watch's in-memory session model.
public struct LiftSessionMeta: Sendable, Equatable {
    public var sessionName: String
    public var totalVolumeLb: Double
    public var setCount: Int
    public var totalReps: Int
    public var block: Int
    public var week: Int
    public var isDeload: Bool
    /// RPE of the top set on the first compound lift (falls back to the first exercise
    /// with a rated top set). nil when nothing was rated.
    public var topSetRPE: Double?

    public init(sessionName: String, totalVolumeLb: Double, setCount: Int, totalReps: Int,
                block: Int, week: Int, isDeload: Bool, topSetRPE: Double? = nil) {
        self.sessionName = sessionName
        self.totalVolumeLb = totalVolumeLb
        self.setCount = setCount
        self.totalReps = totalReps
        self.block = block
        self.week = week
        self.isDeload = isDeload
        self.topSetRPE = topSetRPE
    }

    /// Snapshot a logged workout. `isDeload` is true for W5 or an early-deload override.
    public init(workout: LoggedWorkout, isDeload: Bool) {
        let exercises = workout.orderedExercises
        let rpe = exercises.first(where: { $0.isCompound })?.topSet?.rpe
            ?? exercises.compactMap { $0.topSet?.rpe }.first
        self.init(sessionName: workout.sessionName,
                  totalVolumeLb: workout.totalVolume,
                  setCount: workout.completedSetCount,
                  totalReps: workout.totalReps,
                  block: workout.blockNumber,
                  week: workout.weekNumber,
                  isDeload: isDeload,
                  topSetRPE: rpe)
    }

    /// The custom-key dictionary for `HKWorkoutBuilder.addMetadata`. Callers add the
    /// brand-name entry themselves (`HKMetadataKeyWorkoutBrandName: HealthMetadataKeys.brandName`).
    public var metadata: [String: Any] {
        var md: [String: Any] = [
            HealthMetadataKeys.sessionName: sessionName,
            HealthMetadataKeys.totalVolumeLb: totalVolumeLb,
            HealthMetadataKeys.setCount: setCount,
            HealthMetadataKeys.totalReps: totalReps,
            HealthMetadataKeys.block: block,
            HealthMetadataKeys.week: week,
            HealthMetadataKeys.isDeload: isDeload
        ]
        if let topSetRPE { md[HealthMetadataKeys.topSetRPE] = topSetRPE }
        return md
    }
}
