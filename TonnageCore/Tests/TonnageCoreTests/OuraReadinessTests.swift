import Testing
import Foundation
@testable import TonnageCore

@Suite("Oura readiness")
struct OuraReadinessTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private var oct11: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 19))! }

    private let readinessJSON = """
    {"data": [
      {"id": "a", "day": "2026-10-10", "score": 81, "temperature_deviation": 0.1,
       "contributors": {"hrv_balance": 80, "resting_heart_rate": 90}},
      {"id": "b", "day": "2026-10-11", "score": 60, "temperature_deviation": 0.6,
       "temperature_trend_deviation": 0.2,
       "contributors": {"activity_balance": 72, "body_temperature": 58, "hrv_balance": 54,
                        "previous_day_activity": null, "previous_night": 66, "recovery_index": 85,
                        "resting_heart_rate": 61, "sleep_balance": 70}},
      {"id": "bad", "score": "not a number"}
    ], "next_token": null}
    """

    private let sleepJSON = """
    {"data": [
      {"day": "2026-10-11", "type": "rest", "average_hrv": 20},
      {"day": "2026-10-11", "type": "long_sleep", "average_hrv": 38.4, "lowest_heart_rate": 54,
       "average_breath": 14.9, "total_sleep_duration": 23400}
    ]}
    """

    @Test("Decodes Oura pages leniently, skipping a malformed item and null contributors")
    func decoding() throws {
        let page = try JSONDecoder().decode(OuraPage<OuraDailyReadiness>.self, from: Data(readinessJSON.utf8))
        #expect(page.data.count == 2)
        #expect(page.data[1].score == 60)
        #expect(page.data[1].contributors["previous_day_activity"] == nil)
        #expect(page.data[1].contributors["hrv_balance"] == 54)
        let sleep = try JSONDecoder().decode(OuraPage<OuraSleepPeriod>.self, from: Data(sleepJSON.utf8))
        #expect(sleep.data.last?.lowestHeartRate == 54)
    }

    @Test("Today's Oura score becomes the readiness, with Tonnage's bands and Oura's contributors")
    func mapping() throws {
        let items = try JSONDecoder().decode(OuraPage<OuraDailyReadiness>.self, from: Data(readinessJSON.utf8)).data
        let sleep = try JSONDecoder().decode(OuraPage<OuraSleepPeriod>.self, from: Data(sleepJSON.utf8)).data
        let r = try #require(OuraReadiness.today(from: items, sleep: sleep, now: oct11, calendar: calendar))
        #expect(r.score == 60)
        #expect(r.source == .oura)
        #expect(r.band == .compromised)        // 60 → hold loads, like Oura's "pay attention"
        #expect(r.holdsProgression)
        let labels = r.drivers.map(\.label)
        #expect(labels.first == "Previous night 66")
        #expect(labels.contains("HRV balance 54"))
        #expect(r.drivers.first { $0.label == "HRV balance 54" }?.sign == .negative)
        #expect(r.drivers.first { $0.label == "Recovery index 85" }?.sign == .positive)
        #expect(labels.contains("Last night: HRV 38 ms · lowest HR 54 bpm · slept 6.5h"))
        #expect(labels.contains("Temperature +0.6°C vs baseline"))
    }

    @Test("No score for today (ring not synced) means no Oura readiness")
    func noScoreToday() {
        let yesterdayOnly = [OuraDailyReadiness(day: "2026-10-10", score: 81)]
        #expect(OuraReadiness.today(from: yesterdayOnly, now: oct11, calendar: calendar) == nil)
        let pending = [OuraDailyReadiness(day: "2026-10-11", score: nil)]
        #expect(OuraReadiness.today(from: pending, now: oct11, calendar: calendar) == nil)
    }

    @Test("Bands match Tonnage's legend")
    func bands() {
        func band(_ s: Int) -> Readiness.Band? {
            OuraReadiness.today(from: [OuraDailyReadiness(day: "2026-10-11", score: s)], now: oct11, calendar: calendar)?.band
        }
        #expect(band(85) == .primed && band(70) == .ready && band(50) == .compromised && band(30) == .drained)
    }

    @Test("Health-based readiness reports its source as Health")
    func healthSource() {
        let r = ReadinessEngine.evaluate(ReadinessInputs(sleepHours: 7.5))
        #expect(r.source == .health)
    }
}
