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

    @Test("Warm-up flag, cardio metrics, and notes survive the round-trip")
    func fullFidelityRoundTrip() throws {
        let payload = WorkoutPayload(
            blockNumber: 3, weekNumber: 4, sessionName: "Lower B", dayType: .lift,
            date: Date(timeIntervalSince1970: 2_000_000),
            exercises: [
                .init(name: "Back Squat", isCompound: true, isCardio: false, prescribedSets: 3,
                      repRange: "5-7", rpeTarget: "8", prescriptionNotes: "",
                      sets: [
                        .init(weight: 135, reps: 5, rpe: nil, completed: true, isWarmup: true),
                        .init(weight: 225, reps: 5, rpe: 8, completed: true, note: "belt on, felt strong"),
                      ],
                      supersetWithNext: true),
                .init(name: "Stair Master", isCompound: false, isCardio: true, prescribedSets: 1,
                      repRange: "15 min", rpeTarget: "easy", prescriptionNotes: "",
                      sets: [.init(weight: 0, reps: 0, rpe: nil, completed: true,
                                   durationSeconds: 900, distanceMiles: nil, flights: 45)]),
            ],
            notes: "slept 8h, great session"
        )
        let decoded = try #require(WorkoutPayload.decoded(from: payload.encoded()))
        #expect(decoded == payload)
        #expect(decoded.exercises[0].sets[0].isWarmup == true)
        #expect(decoded.exercises[0].sets[1].note == "belt on, felt strong")
        #expect(decoded.exercises[1].sets[0].durationSeconds == 900)
        #expect(decoded.exercises[1].sets[0].flights == 45)
        #expect(decoded.exercises[0].supersetWithNext == true)
        #expect(decoded.exercises[1].supersetWithNext == nil)
        #expect(decoded.notes == "slept 8h, great session")
    }

    @Test("Older payloads without the new fields still decode (nil defaults)")
    func backwardCompatibleDecode() throws {
        let legacyJSON = """
        {"weekNumber":1,"sessionName":"Upper A","dayType":"lift","date":0,
         "exercises":[{"name":"Bench","isCompound":true,"isCardio":false,"prescribedSets":3,
         "repRange":"5-7","rpeTarget":"8","prescriptionNotes":"",
         "sets":[{"weight":145,"reps":5,"completed":true}]}]}
        """
        let decoded = try #require(WorkoutPayload.decoded(from: Data(legacyJSON.utf8)))
        #expect(decoded.exercises[0].sets[0].isWarmup == nil)
        #expect(decoded.exercises[0].sets[0].note == nil)
        #expect(decoded.notes == nil)
    }
}
