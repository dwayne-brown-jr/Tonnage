import Testing
@testable import TonnageCore

@Suite("Readiness drivers")
struct ReadinessDriverTests {

    @Test("Sleep driver sign never contradicts its points (7.3h isn't a positive driver)")
    func sleepSignConsistent() {
        let r = ReadinessEngine.evaluate(.init(sleepHours: 7.3))
        let sleep = r.drivers.first { $0.label.contains("Slept") }
        #expect(sleep != nil)
        // 7.3h subtracts points → it must NOT render as a positive (green) contribution.
        #expect(sleep!.points < 0)
        #expect(sleep!.sign != .positive)
    }

    @Test("Good sleep is a positive driver with positive points")
    func sleepPositive() {
        let sleep = ReadinessEngine.evaluate(.init(sleepHours: 9)).drivers.first { $0.label.contains("Slept") }!
        #expect(sleep.points > 0)
        #expect(sleep.sign == .positive)
    }

    @Test("Band boundaries: +10 lands at 80 (primed), neutral 70 (ready)")
    func bands() {
        #expect(ReadinessEngine.evaluate(.init(sleepHours: 10)).band == .primed)   // +10 → 80
        #expect(ReadinessEngine.evaluate(.init(sleepHours: 7.5)).band == .ready)    // +0  → 70
    }

    @Test("HRV contribution clamps to +22")
    func hrvClamp() {
        let hrv = ReadinessEngine.evaluate(.init(hrvMs: 200, hrvBaselineMs: 50)).drivers.first { $0.label.hasPrefix("HRV") }!
        #expect(hrv.points == 22)
    }

    @Test("A zero baseline excludes that signal but others still score")
    func zeroBaselineExcluded() {
        let r = ReadinessEngine.evaluate(.init(hrvMs: 80, hrvBaselineMs: 0, sleepHours: 8))
        #expect(!r.drivers.contains { $0.label.hasPrefix("HRV") })
        #expect(r.score != nil)
    }

    @Test("No signals → unknown, nil score")
    func noSignals() {
        let r = ReadinessEngine.evaluate(.init(trainedYesterday: true))
        #expect(r.band == .unknown)
        #expect(r.score == nil)
    }
}
