import Testing
@testable import TonnageCore

@Suite("Trend engine")
struct TrendEngineTests {

    @Test("Direction classifies rising / falling / flat with a deadband")
    func direction() {
        #expect(TrendEngine.direction([1, 2, 3, 4, 5, 6]) == .rising)
        #expect(TrendEngine.direction([6, 5, 4, 3, 2, 1]) == .falling)
        #expect(TrendEngine.direction([50, 50.1, 49.9, 50, 50.2, 49.8]) == .flat)
        #expect(TrendEngine.direction([1, 2, 3]) == .flat)   // too few points
    }

    @Test("Stall detection needs history and compares recent best to prior best")
    func stall() {
        #expect(TrendEngine.isStalled([100, 110, 108, 109, 110]))        // plateaued at 110
        #expect(!TrendEngine.isStalled([100, 105, 110, 115, 120]))       // still climbing
        #expect(!TrendEngine.isStalled([100, 110]))                       // not enough data
    }

    @Test("countBelow counts the recent window under a threshold")
    func countBelow() {
        #expect(TrendEngine.countBelow([70, 60, 80, 55, 50], threshold: 65, window: 5) == 3)
        #expect(TrendEngine.countBelow([90, 88, 60], threshold: 65, window: 2) == 1)   // last two: 88, 60
        #expect(TrendEngine.countBelow([90, 88, 70], threshold: 65, window: 2) == 0)   // last two: 88, 70
    }
}

@Suite("Insight engine")
struct InsightEngineTests {
    private let falling = [80.0, 78, 75, 72, 70, 66, 62]
    private let rising = [60.0, 64, 68, 72, 76, 80]
    private let stalledBench = InsightEngine.Inputs.Lift(name: "Bench", e1rm: [100, 110, 108, 109, 110])

    @Test("Advisory deload fires when recovery slips AND a lift stalls, off the deload week")
    func deloadFires() {
        let out = InsightEngine.generate(.init(readiness: falling, hrv: [], lifts: [stalledBench],
                                               currentWeek: 3, deloadWeek: 5))
        #expect(out.first?.id == "deload")
    }

    @Test("Deload is suppressed during the planned deload week")
    func deloadSuppressed() {
        let out = InsightEngine.generate(.init(readiness: falling, hrv: [], lifts: [stalledBench],
                                               currentWeek: 5, deloadWeek: 5))
        #expect(!out.contains { $0.id == "deload" })
        #expect(out.contains { $0.id == "readiness-down" })
    }

    @Test("Falling readiness without a stall tells the readiness story, not a deload")
    func readinessStory() {
        let out = InsightEngine.generate(.init(readiness: falling, hrv: [], lifts: [],
                                               currentWeek: 3, deloadWeek: 5))
        #expect(out.contains { $0.id == "readiness-down" })
        #expect(!out.contains { $0.id == "deload" })
    }

    @Test("Rising readiness with nothing wrong gives positive reinforcement")
    func positive() {
        let out = InsightEngine.generate(.init(readiness: rising, hrv: [], lifts: [],
                                               currentWeek: 3, deloadWeek: 5))
        #expect(out.contains { $0.id == "readiness-up" })
    }
}
