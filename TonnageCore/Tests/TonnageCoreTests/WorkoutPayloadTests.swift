import Testing
import Foundation
@testable import TonnageCore

@Suite("Workout payload")
struct WorkoutPayloadTests {

    @Test("Encodes and decodes round-trip")
    func roundTrip() throws {
        let payload = WorkoutPayload(
            weekNumber: 2, sessionName: "Upper A", dayType: .lift, date: Date(timeIntervalSince1970: 1_000_000),
            exercises: [
                .init(name: "Bench", isCompound: true, isCardio: false, prescribedSets: 3,
                      repRange: "5-7", rpeTarget: "8", prescriptionNotes: "top set",
                      sets: [.init(weight: 145, reps: 5, rpe: 8, completed: true)])
            ]
        )
        let data = try payload.encoded()
        let decoded = try #require(WorkoutPayload.decoded(from: data))
        #expect(decoded == payload)
        #expect(decoded.exercises.first?.sets.first?.weight == 145)
    }
}
