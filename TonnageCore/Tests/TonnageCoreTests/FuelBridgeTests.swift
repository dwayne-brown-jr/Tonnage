import Testing
import Foundation
@testable import TonnageCore

/// The App Group JSON is a cross-app contract with Tonnage Fuel: exact key names,
/// ISO-8601 dates, and a stable shape for rest days. These pin all three.
@Suite("Fuel bridge")
struct FuelBridgeTests {

    /// A private, throwaway defaults suite so tests never touch the real App Group.
    private func makeDefaults() -> UserDefaults {
        let name = "tonnage.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func json(_ defaults: UserDefaults, _ key: String) -> [String: Any] {
        guard let data = defaults.data(forKey: key),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// ISO-8601 encoding is whole-second, so compare round-tripped dates with tolerance.
    private func expectISO8601(_ raw: Any?, matches date: Date, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let string = raw as? String, let parsed = FuelBridge.parseISO8601(string) else {
            Issue.record("Not an ISO-8601 string: \(String(describing: raw))", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(parsed.timeIntervalSince(date)) < 1, sourceLocation: sourceLocation)
    }

    // MARK: Keys

    @Test("Shared keys are the versioned literals Fuel looks up")
    func keyNames() {
        #expect(FuelBridge.Key.todaySession == "shared.v1.todaySession")
        #expect(FuelBridge.Key.readiness == "shared.v1.readiness")
        #expect(FuelBridge.Key.profile == "shared.v1.profile")
        #expect(FuelBridge.Key.fuelStatus == "shared.v1.fuelStatus")
    }

    @Test("Day keys are local-calendar yyyy-MM-dd")
    func dayKeyFormat() {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 7; c.hour = 23; c.minute = 30
        let date = Calendar.current.date(from: c)!
        #expect(FuelBridge.dayKey(date) == "2026-03-07")
    }

    // MARK: todaySession

    @Test("todaySession encodes every contract key with ISO-8601 dates")
    func todaySessionShape() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_772_000_000)
        FuelBridge.writeTodaySession(sessionName: "Upper A", focus: "Push focus", isLift: true,
                                     isDeload: false, block: 2, week: 3, now: now, defaults: defaults)

        let obj = json(defaults, FuelBridge.Key.todaySession)
        #expect(obj["date"] as? String == FuelBridge.dayKey(now))
        #expect(obj["sessionName"] as? String == "Upper A")
        #expect(obj["focus"] as? String == "Push focus")
        #expect(obj["isLift"] as? Bool == true)
        #expect(obj["isDeload"] as? Bool == false)
        #expect(obj["block"] as? Int == 2)
        #expect(obj["week"] as? Int == 3)
        #expect(obj["startedAt"] == nil)      // not started yet — key omitted, not null
        #expect(obj["completedAt"] == nil)
        expectISO8601(obj["updatedAt"], matches: now)
    }

    @Test("Rest days publish isLift:false with an empty session name")
    func restDayShape() {
        let defaults = makeDefaults()
        let now = Date()
        FuelBridge.writeTodaySession(sessionName: "Upper A", focus: "Push focus", isLift: false,
                                     isDeload: true, block: 1, week: 5, now: now, defaults: defaults)

        let obj = json(defaults, FuelBridge.Key.todaySession)
        #expect(obj["isLift"] as? Bool == false)
        #expect(obj["sessionName"] as? String == "")
        #expect(obj["focus"] as? String == "")
        #expect(obj["isDeload"] as? Bool == false)   // deload is a lift-week concept
        #expect(obj["date"] as? String == FuelBridge.dayKey(now))
    }

    @Test("Start / complete timestamps land and survive a same-day rewrite of the plan")
    func liveSessionTimestamps() {
        let defaults = makeDefaults()
        // Anchored mid-morning so start + 1h can't roll past midnight into a new day key.
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        FuelBridge.writeTodaySession(sessionName: "Upper A", focus: "Push focus", isLift: true,
                                     isDeload: false, block: 1, week: 2, now: now, defaults: defaults)

        let started = now.addingTimeInterval(60)
        FuelBridge.markSessionStarted(sessionName: "Upper A", at: started, defaults: defaults)
        // Idempotent — a second start keeps the first one.
        FuelBridge.markSessionStarted(sessionName: "Upper A", at: started.addingTimeInterval(600), defaults: defaults)
        let finished = now.addingTimeInterval(3_600)
        FuelBridge.markSessionCompleted(sessionName: "Upper A", at: finished, defaults: defaults)

        // Re-publishing the same plan must not wipe the live timestamps.
        let after = FuelBridge.writeTodaySession(sessionName: "Upper A", focus: "Push focus", isLift: true,
                                                 isDeload: false, block: 1, week: 2,
                                                 now: finished, defaults: defaults)
        #expect(after.startedAt == started)
        #expect(after.completedAt == finished)

        let obj = json(defaults, FuelBridge.Key.todaySession)
        expectISO8601(obj["startedAt"], matches: started)
        expectISO8601(obj["completedAt"], matches: finished)
    }

    @Test("A different session started today replaces the record's timestamps")
    func switchingSessionResetsTimestamps() {
        let defaults = makeDefaults()
        FuelBridge.markSessionStarted(sessionName: "Upper A", defaults: defaults)
        let record = FuelBridge.markSessionStarted(sessionName: "Lower B", defaults: defaults)
        #expect(record.sessionName == "Lower B")
        #expect(record.startedAt != nil)
        #expect(record.completedAt == nil)
    }

    // MARK: readiness

    @Test("readiness encodes score, lowercased band, drivers, and note")
    func readinessShape() {
        let defaults = makeDefaults()
        let now = Date()
        let readiness = ReadinessEngine.evaluate(ReadinessInputs(
            hrvMs: 70, hrvBaselineMs: 60, restingHR: 50, restingHRBaseline: 54, sleepHours: 8.2
        ))
        #expect(FuelBridge.writeReadiness(readiness, now: now, defaults: defaults))

        let obj = json(defaults, FuelBridge.Key.readiness)
        #expect(obj["date"] as? String == FuelBridge.dayKey(now))
        #expect(obj["score"] as? Int == readiness.score)
        #expect(obj["band"] as? String == readiness.band.rawValue.lowercased())
        #expect(obj["trainingNote"] as? String == readiness.trainingNote)
        expectISO8601(obj["updatedAt"], matches: now)

        let drivers = obj["drivers"] as? [[String: Any]] ?? []
        #expect(drivers.count == readiness.drivers.count)
        #expect(drivers.first?["label"] as? String == readiness.drivers.first?.label)
        #expect(drivers.allSatisfy { $0["points"] is Int })
    }

    @Test("Readiness with no signals writes nothing")
    func readinessWithoutSignals() {
        let defaults = makeDefaults()
        let readiness = ReadinessEngine.evaluate(ReadinessInputs())
        #expect(FuelBridge.writeReadiness(readiness, defaults: defaults) == false)
        #expect(defaults.data(forKey: FuelBridge.Key.readiness) == nil)
    }

    // MARK: profile

    @Test("profile encodes the intake fields Fuel needs for macro defaults")
    func profileShape() {
        let defaults = makeDefaults()
        let now = Date()
        let profile = CoachProfile(name: "Dwayne", ageYears: 33, sex: .male, heightInches: 71,
                                   bodyweightLb: 182, goal: .recomp, experience: .experienced,
                                   startingPoint: .skinnyFat, daysPerWeek: 4)
        FuelBridge.writeProfile(profile, now: now, defaults: defaults)

        let obj = json(defaults, FuelBridge.Key.profile)
        #expect(obj["age"] as? Int == 33)
        #expect(obj["sex"] as? String == "male")
        #expect(obj["heightIn"] as? Double == 71)
        #expect(obj["bodyweightLb"] as? Double == 182)
        #expect(obj["trainingGoal"] as? String == "recomp")
        #expect(obj["experience"] as? String == "experienced")
        #expect(obj["daysPerWeek"] as? Int == 4)
        #expect(obj["startingPoint"] as? String == "skinnyFat")
        #expect(obj["recommendedGoal"] as? String == "recomp")
        expectISO8601(obj["updatedAt"], matches: now)
    }

    @Test("Unset profile fields are omitted rather than written as zeros")
    func emptyProfileOmitsFields() {
        let defaults = makeDefaults()
        FuelBridge.writeProfile(CoachProfile(), defaults: defaults)
        let obj = json(defaults, FuelBridge.Key.profile)
        #expect(obj["age"] == nil)
        #expect(obj["sex"] == nil)
        #expect(obj["heightIn"] == nil)
        #expect(obj["bodyweightLb"] == nil)
        #expect(obj["daysPerWeek"] == nil)
        #expect(obj["startingPoint"] == nil)          // .unsure → nothing to share
        #expect(obj["recommendedGoal"] == nil)
        #expect(obj["updatedAt"] != nil)
    }

    // MARK: fuelStatus (Fuel → Tonnage)

    private func writeFuelStatus(_ defaults: UserDefaults, dayKey: String, lastMeal: String = "2026-03-07T13:22:04Z") {
        let raw = """
        {"dayKey":"\(dayKey)","dayType":"lift",
         "calories":{"target":2750,"consumed":1980},
         "protein":{"target":190,"consumed":141},
         "carbs":{"target":300,"consumed":210},
         "fat":{"target":80,"consumed":55},
         "waterOz":{"target":120,"consumed":64},
         "lastMealAt":"\(lastMeal)","adherence7d":0.86,
         "updatedAt":"2026-03-07T13:25:00Z"}
        """
        defaults.set(Data(raw.utf8), forKey: FuelBridge.Key.fuelStatus)
    }

    @Test("Today's fuel status decodes leniently, including fractional-second dates")
    func readsTodaysStatus() {
        let defaults = makeDefaults()
        let now = Date()
        writeFuelStatus(defaults, dayKey: FuelBridge.dayKey(now), lastMeal: "2026-03-07T13:22:04.512Z")

        let status = FuelBridge.readFuelStatus(now: now, defaults: defaults)
        #expect(status?.dayType == "lift")
        #expect(status?.calories?.consumed == 1980)
        #expect(status?.calories?.remaining == 770)
        #expect(status?.protein?.target == 190)
        #expect(status?.waterOz?.consumed == 64)
        #expect(status?.adherence7d == 0.86)
        #expect(status?.lastMealAt != nil)
    }

    @Test("A status from another day is ignored")
    func ignoresStaleStatus() {
        let defaults = makeDefaults()
        // Midday, so yesterday's key can't be today's nutrition day.
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        writeFuelStatus(defaults, dayKey: FuelBridge.dayKey(now.addingTimeInterval(-86_400)))
        #expect(FuelBridge.readFuelStatus(now: now, defaults: defaults) == nil)
    }

    @Test("Between midnight and 4am, Fuel's status for the nutrition day still shows")
    func acceptsNutritionDayKeyBefore4am() {
        let defaults = makeDefaults()
        let cal = Calendar.current
        let oneThirty = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        // Fuel wrote the 7th's key (4am cutoff) — this is the day the athlete is still in.
        writeFuelStatus(defaults, dayKey: "2026-03-07")
        #expect(FuelBridge.readFuelStatus(now: oneThirty, defaults: defaults)?.dayType == "lift")
        // An older Fuel build writing the calendar key is still accepted.
        writeFuelStatus(defaults, dayKey: "2026-03-08")
        #expect(FuelBridge.readFuelStatus(now: oneThirty, defaults: defaults) != nil)
        // After 4am the 7th's status is yesterday's.
        writeFuelStatus(defaults, dayKey: "2026-03-07")
        let fourOhFive = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4, minute: 5))!
        #expect(FuelBridge.readFuelStatus(now: fourOhFive, defaults: defaults) == nil)
    }

    @Test("Nutrition-day key uses the 4am cutoff")
    func nutritionDayKey() {
        let cal = Calendar.current
        #expect(FuelBridge.nutritionDayKey(cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 59))!) == "2026-03-07")
        #expect(FuelBridge.nutritionDayKey(cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4))!) == "2026-03-08")
    }

    @Test("Missing or unreadable status reads as nil, never a crash")
    func toleratesGarbage() {
        let defaults = makeDefaults()
        #expect(FuelBridge.readFuelStatus(defaults: defaults) == nil)
        defaults.set(Data("not json".utf8), forKey: FuelBridge.Key.fuelStatus)
        #expect(FuelBridge.readFuelStatus(defaults: defaults) == nil)
    }

    @Test("Unknown extra fields don't break decoding")
    func toleratesUnknownFields() {
        let defaults = makeDefaults()
        let now = Date()
        let raw = """
        {"dayKey":"\(FuelBridge.dayKey(now))","somethingNew":42,"calories":{"consumed":900}}
        """
        defaults.set(Data(raw.utf8), forKey: FuelBridge.Key.fuelStatus)
        let status = FuelBridge.readFuelStatus(now: now, defaults: defaults)
        #expect(status?.calories?.consumed == 900)
        #expect(status?.calories?.remaining == nil)
        #expect(status?.protein == nil)
    }
}
