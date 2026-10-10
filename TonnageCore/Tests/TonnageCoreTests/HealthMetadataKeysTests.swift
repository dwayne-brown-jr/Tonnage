import Testing
import Foundation
@testable import TonnageCore

/// The literal metadata keys are a cross-app contract: Tonnage Fuel reads them straight
/// off the HealthKit workout. Renaming one silently breaks Fuel, so pin the strings.
@Suite("HealthKit workout metadata")
struct HealthMetadataKeysTests {

    @Test("Key strings are frozen — Tonnage Fuel reads these literals")
    func exactKeyStrings() {
        #expect(HealthMetadataKeys.brandName == "Tonnage")
        #expect(HealthMetadataKeys.sessionName == "com.dwayne.tonnage.sessionName")
        #expect(HealthMetadataKeys.totalVolumeLb == "com.dwayne.tonnage.totalVolumeLb")
        #expect(HealthMetadataKeys.setCount == "com.dwayne.tonnage.setCount")
        #expect(HealthMetadataKeys.totalReps == "com.dwayne.tonnage.totalReps")
        #expect(HealthMetadataKeys.block == "com.dwayne.tonnage.block")
        #expect(HealthMetadataKeys.week == "com.dwayne.tonnage.week")
        #expect(HealthMetadataKeys.isDeload == "com.dwayne.tonnage.isDeload")
        #expect(HealthMetadataKeys.topSetRPE == "com.dwayne.tonnage.topSetRPE")
    }

    @Test("Metadata dictionary carries every value at its documented type")
    func metadataDictionary() {
        let meta = LiftSessionMeta(sessionName: "Upper A", totalVolumeLb: 12_450, setCount: 18,
                                   totalReps: 132, block: 2, week: 3, isDeload: false, topSetRPE: 8.5)
        let md = meta.metadata
        #expect(md[HealthMetadataKeys.sessionName] as? String == "Upper A")
        #expect(md[HealthMetadataKeys.totalVolumeLb] as? Double == 12_450)
        #expect(md[HealthMetadataKeys.setCount] as? Int == 18)
        #expect(md[HealthMetadataKeys.totalReps] as? Int == 132)
        #expect(md[HealthMetadataKeys.block] as? Int == 2)
        #expect(md[HealthMetadataKeys.week] as? Int == 3)
        #expect(md[HealthMetadataKeys.isDeload] as? Bool == false)
        #expect(md[HealthMetadataKeys.topSetRPE] as? Double == 8.5)
    }

    @Test("An unrated session omits the RPE key rather than writing a placeholder")
    func omitsUnknownRPE() {
        let meta = LiftSessionMeta(sessionName: "Lower B", totalVolumeLb: 8_000, setCount: 12,
                                   totalReps: 90, block: 1, week: 1, isDeload: true)
        #expect(meta.metadata[HealthMetadataKeys.topSetRPE] == nil)
        #expect(meta.metadata[HealthMetadataKeys.isDeload] as? Bool == true)
    }

    @Test("Built from a LoggedWorkout: working-set totals and the compound's top-set RPE")
    func fromLoggedWorkout() {
        let squat = LoggedExercise(name: "Barbell Back Squat", isCompound: true, sortOrder: 0)
        squat.sets = [
            LoggedSet(weight: 135, reps: 5, completed: true, isWarmup: true, sortOrder: 0),  // excluded
            LoggedSet(weight: 225, reps: 5, rpe: 8, completed: true, sortOrder: 1),
            LoggedSet(weight: 245, reps: 3, rpe: 9, completed: true, sortOrder: 2)           // top set
        ]
        let curl = LoggedExercise(name: "DB Curl", isCompound: false, sortOrder: 1)
        curl.sets = [LoggedSet(weight: 30, reps: 10, rpe: 7, completed: true, sortOrder: 0)]
        let workout = LoggedWorkout(blockNumber: 2, weekNumber: 4, dayType: .lift, sessionName: "Lower A")
        workout.exercises = [squat, curl]

        let meta = LiftSessionMeta(workout: workout, isDeload: false)
        #expect(meta.sessionName == "Lower A")
        #expect(meta.block == 2)
        #expect(meta.week == 4)
        #expect(meta.setCount == 3)                                  // warm-up excluded
        #expect(meta.totalReps == 18)                                // 5 + 3 + 10
        let expectedVolume: Double = 1125 + 735 + 300     // 225×5, 245×3, 30×10
        #expect(meta.totalVolumeLb == expectedVolume)
        #expect(meta.topSetRPE == 9)                                 // the compound's heaviest set
        #expect(meta.isDeload == false)
    }
}
