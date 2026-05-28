import Testing
import Foundation
@testable import TonnageCore

@Suite("Backup")
struct BackupTests {

    @Test("Backup encodes and decodes round-trip (incl. nested workout + activity)")
    func roundTrip() throws {
        let backup = BackupData(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            workouts: [
                WorkoutPayload(weekNumber: 3, sessionName: "Lower A", dayType: .lift,
                               date: Date(timeIntervalSince1970: 1_699_000_000),
                               exercises: [
                                .init(name: "Squat", isCompound: true, isCardio: false, prescribedSets: 3,
                                      repRange: "5-7", rpeTarget: "8", prescriptionNotes: "",
                                      sets: [.init(weight: 225, reps: 5, rpe: 8, completed: true)])
                               ])
            ],
            activities: [
                ActivityPayload(name: "Walk", kind: .walk, durationMinutes: 40,
                                distanceMiles: 2.2, flights: nil, detail: "vest", date: .now)
            ]
        )
        let data = try backup.encoded()
        let decoded = try #require(BackupData.decoded(from: data))
        #expect(decoded.workouts.first?.exercises.first?.sets.first?.weight == 225)
        #expect(decoded.activities.first?.kind == .walk)
        #expect(decoded.activities.first?.distanceMiles == 2.2)
    }
}
