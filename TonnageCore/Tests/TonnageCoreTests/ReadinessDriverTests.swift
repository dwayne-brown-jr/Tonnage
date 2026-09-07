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

    // MARK: Ring-derived signals (body temperature + respiratory rate)

    @Test("Elevated body temp is a negative driver that lowers the score")
    func bodyTempElevated() {
        let warm = ReadinessEngine.evaluate(.init(bodyTempC: 37.0, bodyTempBaselineC: 36.5))
        let driver = warm.drivers.first { $0.label.hasPrefix("Body temp") }
        #expect(driver != nil)
        #expect(driver!.points < 0)
        #expect(driver!.sign == .negative)
        // Same inputs minus the temp signal → temp must have pulled the score down.
        let neutral = ReadinessEngine.evaluate(.init(bodyTempC: 36.5, bodyTempBaselineC: 36.5))
        #expect(warm.score! < neutral.score!)
    }

    @Test("Body temp within the 0.3°C deadband is neutral, not a penalty (wrist temp is noisy)")
    func bodyTempDeadband() {
        // +0.2°C — normal night-to-night wrist-temp wobble — must not penalize.
        let r = ReadinessEngine.evaluate(.init(bodyTempC: 36.7, bodyTempBaselineC: 36.5))
        let driver = r.drivers.first { $0.label.hasPrefix("Body temp") }!
        #expect(driver.points == 0)
        #expect(driver.sign == .neutral)
    }

    @Test("Elevated respiratory rate is a negative driver")
    func respiratoryElevated() {
        let r = ReadinessEngine.evaluate(.init(respiratoryRate: 17, respiratoryRateBaseline: 14))
        let driver = r.drivers.first { $0.label.hasPrefix("Resp rate") }!
        #expect(driver.points < 0)
        #expect(driver.sign == .negative)
    }

    @Test("Zero baselines exclude temp + respiratory but others still score")
    func ringSignalsZeroBaselineExcluded() {
        let r = ReadinessEngine.evaluate(.init(sleepHours: 8,
                                               bodyTempC: 37, bodyTempBaselineC: 0,
                                               respiratoryRate: 18, respiratoryRateBaseline: 0))
        #expect(!r.drivers.contains { $0.label.hasPrefix("Body temp") })
        #expect(!r.drivers.contains { $0.label.hasPrefix("Resp rate") })
        #expect(r.score != nil)
    }

    @Test("A sick-day profile (fever + high breathing on top of poor autonomics) bands to drained")
    func sickDayDrained() {
        let r = ReadinessEngine.evaluate(.init(
            hrvMs: 38, hrvBaselineMs: 62, restingHR: 66, restingHRBaseline: 56, sleepHours: 5,
            bodyTempC: 37.3, bodyTempBaselineC: 36.5, respiratoryRate: 18, respiratoryRateBaseline: 14))
        #expect(r.band == .drained)
        #expect(r.holdsProgression == true)
    }
}
