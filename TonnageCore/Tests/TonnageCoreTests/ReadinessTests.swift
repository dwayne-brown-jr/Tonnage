import Testing
@testable import TonnageCore

@Suite("Readiness")
struct ReadinessTests {

    @Test("Strong recovery signals → high score, no progression hold")
    func primed() {
        let r = ReadinessEngine.evaluate(ReadinessInputs(
            hrvMs: 80, hrvBaselineMs: 62, restingHR: 50, restingHRBaseline: 56,
            sleepHours: 8.0, trainedYesterday: false))
        #expect(r.score != nil)
        #expect(r.score! >= 80)
        #expect(r.band == .primed)
        #expect(r.holdsProgression == false)
        #expect(!r.drivers.isEmpty)
    }

    @Test("Poor recovery → low score and progression hold")
    func drained() {
        let r = ReadinessEngine.evaluate(ReadinessInputs(
            hrvMs: 38, hrvBaselineMs: 62, restingHR: 66, restingHRBaseline: 56,
            sleepHours: 5.0, trainedYesterday: true))
        #expect(r.score! < 65)
        #expect(r.band == .compromised || r.band == .drained)
        #expect(r.holdsProgression == true)
    }

    @Test("No signals → unknown, no score")
    func unknown() {
        let r = ReadinessEngine.evaluate(ReadinessInputs())
        #expect(r.score == nil)
        #expect(r.band == .unknown)
        #expect(r.holdsProgression == false)
    }

    @Test("Sleep-only still produces a banded score")
    func partial() {
        let r = ReadinessEngine.evaluate(ReadinessInputs(sleepHours: 8.5))
        #expect(r.score != nil)
        #expect(r.band != .unknown)
    }
}
