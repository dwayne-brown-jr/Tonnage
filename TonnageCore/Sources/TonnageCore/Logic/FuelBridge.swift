import Foundation

/// Tonnage ⇄ Tonnage Fuel bridge over the shared App Group (`AppGroup.defaults`).
///
/// Every record is a JSON blob with ISO-8601 dates under a versioned `shared.v1.*` key,
/// so Fuel decodes them without linking this package — the key names and field names
/// below are the contract; change them only by adding a `v2`. Tonnage writes today's
/// session, readiness, and the athlete profile; Fuel writes `fuelStatus` back and the
/// coach reads it (as data, never as instructions).
public enum FuelBridge {

    public enum Key {
        public static let todaySession = "shared.v1.todaySession"
        public static let readiness    = "shared.v1.readiness"
        public static let profile      = "shared.v1.profile"
        /// Written by Tonnage Fuel, read here.
        public static let fuelStatus   = "shared.v1.fuelStatus"
    }

    // MARK: Records Tonnage writes

    /// What's on the TRAIN screen for today. Rest days carry `isLift: false` and an empty
    /// `sessionName`. `startedAt` / `completedAt` are set by the live-session hooks and
    /// carried across rewrites of the same day + session.
    public struct TodaySession: Codable, Equatable, Sendable {
        public var date: String          // "yyyy-MM-dd", local calendar
        public var sessionName: String
        public var focus: String
        public var isLift: Bool
        public var isDeload: Bool
        public var block: Int?
        public var week: Int?
        public var startedAt: Date?
        public var completedAt: Date?
        public var updatedAt: Date

        public init(date: String, sessionName: String, focus: String, isLift: Bool, isDeload: Bool,
                    block: Int?, week: Int?, startedAt: Date? = nil, completedAt: Date? = nil, updatedAt: Date) {
            self.date = date
            self.sessionName = sessionName
            self.focus = focus
            self.isLift = isLift
            self.isDeload = isDeload
            self.block = block
            self.week = week
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.updatedAt = updatedAt
        }
    }

    /// The day's readiness read. Only written when a score exists (band != unknown).
    public struct ReadinessRecord: Codable, Equatable, Sendable {
        public struct Driver: Codable, Equatable, Sendable {
            public var label: String
            public var points: Int
            public init(label: String, points: Int) { self.label = label; self.points = points }
        }
        public var date: String
        public var score: Int
        public var band: String          // Readiness.Band case name, lowercased
        public var drivers: [Driver]
        public var trainingNote: String
        public var updatedAt: Date

        /// nil when readiness has no score yet (no HealthKit signals).
        public init?(_ readiness: Readiness, now: Date = .now) {
            guard let score = readiness.score, readiness.band != .unknown else { return nil }
            date = FuelBridge.dayKey(now)
            self.score = score
            band = readiness.band.rawValue.lowercased()
            drivers = readiness.drivers.map { .init(label: $0.label, points: Int($0.points.rounded())) }
            trainingNote = readiness.trainingNote
            updatedAt = now
        }
    }

    /// The intake profile Fuel uses for macro defaults. Unset fields are omitted (nil).
    public struct ProfileRecord: Codable, Equatable, Sendable {
        public var age: Int?
        public var sex: String?
        public var heightIn: Double?
        public var bodyweightLb: Double?
        public var trainingGoal: String?
        public var experience: String?
        public var daysPerWeek: Int?
        public var startingPoint: String?
        public var recommendedGoal: String?
        public var updatedAt: Date

        public init(_ profile: CoachProfile, now: Date = .now) {
            age = profile.ageYears > 0 ? profile.ageYears : nil
            sex = profile.sex == .unspecified ? nil : profile.sex.rawValue
            heightIn = profile.heightInches > 0 ? Double(profile.heightInches) : nil
            bodyweightLb = profile.bodyweightLb > 0 ? Double(profile.bodyweightLb) : nil
            trainingGoal = profile.goal.rawValue
            experience = profile.experience.rawValue
            daysPerWeek = profile.daysPerWeek > 0 ? profile.daysPerWeek : nil
            startingPoint = profile.startingPoint == .unsure ? nil : profile.startingPoint.rawValue
            recommendedGoal = profile.startingPoint.fuelGoalRaw
            updatedAt = now
        }
    }

    // MARK: Record Fuel writes

    /// Fuel's day status. Decoded leniently — only `dayKey` is required, everything else
    /// is optional so a field Fuel adds or drops never breaks the coach.
    public struct FuelStatus: Decodable, Equatable, Sendable {
        public struct Amount: Decodable, Equatable, Sendable {
            public var target: Double?
            public var consumed: Double?
            public var remaining: Double? {
                guard let target, let consumed else { return nil }
                return target - consumed
            }
            public init(target: Double?, consumed: Double?) { self.target = target; self.consumed = consumed }
        }
        public var dayKey: String
        public var dayType: String?      // "lift" | "cardio" | "rest"
        public var calories: Amount?
        public var protein: Amount?
        public var carbs: Amount?
        public var fat: Amount?
        public var waterOz: Amount?
        public var lastMealAt: Date?
        public var adherence7d: Double?
        public var updatedAt: Date?

        public init(dayKey: String, dayType: String? = nil, calories: Amount? = nil, protein: Amount? = nil,
                    carbs: Amount? = nil, fat: Amount? = nil, waterOz: Amount? = nil,
                    lastMealAt: Date? = nil, adherence7d: Double? = nil, updatedAt: Date? = nil) {
            self.dayKey = dayKey
            self.dayType = dayType
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.waterOz = waterOz
            self.lastMealAt = lastMealAt
            self.adherence7d = adherence7d
            self.updatedAt = updatedAt
        }
    }

    // MARK: Codecs

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Accepts ISO-8601 with or without fractional seconds (Fuel may write either).
    /// Formatters are built inside the closure: `ISO8601DateFormatter` isn't `Sendable`,
    /// and the strategy closure is.
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parseISO8601(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognized ISO-8601 date: \(raw)"))
        }
        return d
    }()

    /// ISO-8601 with or without fractional seconds.
    public static func parseISO8601(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    /// "yyyy-MM-dd" in the local calendar — the day key both apps agree on.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func write<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults? = AppGroup.defaults) {
        guard let defaults, let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Reads a JSON record. Tolerates the value being stored as a JSON *string* as well as
    /// `Data`, so a differently-written Fuel build still decodes.
    public static func read<T: Decodable>(_ type: T.Type, key: String,
                                          from defaults: UserDefaults? = AppGroup.defaults) -> T? {
        guard let defaults else { return nil }
        let data = defaults.data(forKey: key) ?? defaults.string(forKey: key)?.data(using: .utf8)
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: Today's session

    /// Publish what the TRAIN screen shows for today. Rest days blank the session. The
    /// live-session timestamps survive as long as it's still the same day + session.
    @discardableResult
    public static func writeTodaySession(sessionName: String, focus: String, isLift: Bool, isDeload: Bool,
                                         block: Int?, week: Int?, now: Date = .now,
                                         defaults: UserDefaults? = AppGroup.defaults) -> TodaySession {
        let name = isLift ? sessionName : ""
        var record = TodaySession(date: dayKey(now), sessionName: name, focus: isLift ? focus : "",
                                  isLift: isLift, isDeload: isLift && isDeload,
                                  block: block, week: week, updatedAt: now)
        if let existing = read(TodaySession.self, key: Key.todaySession, from: defaults),
           existing.date == record.date, existing.isLift, isLift, existing.sessionName == name {
            record.startedAt = existing.startedAt
            record.completedAt = existing.completedAt
        }
        write(record, key: Key.todaySession, to: defaults)
        return record
    }

    /// A live lift session began (first logged set on the phone, or the watch's live
    /// workout). Idempotent — keeps the earliest start. If the session differs from the
    /// one on screen, the record follows the session actually trained.
    @discardableResult
    public static func markSessionStarted(sessionName: String, at date: Date = .now,
                                          defaults: UserDefaults? = AppGroup.defaults) -> TodaySession {
        var record = todayRecord(for: sessionName, now: date, defaults: defaults)
        guard record.startedAt == nil else { return record }
        record.startedAt = date
        record.updatedAt = date
        write(record, key: Key.todaySession, to: defaults)
        return record
    }

    /// The lift session finished (saved to Health on the phone, or Finish on the watch).
    @discardableResult
    public static func markSessionCompleted(sessionName: String, at date: Date = .now,
                                            defaults: UserDefaults? = AppGroup.defaults) -> TodaySession {
        var record = todayRecord(for: sessionName, now: date, defaults: defaults)
        record.startedAt = record.startedAt ?? date
        record.completedAt = date
        record.updatedAt = date
        write(record, key: Key.todaySession, to: defaults)
        return record
    }

    private static func todayRecord(for sessionName: String, now: Date, defaults: UserDefaults?) -> TodaySession {
        let today = dayKey(now)
        if var existing = read(TodaySession.self, key: Key.todaySession, from: defaults), existing.date == today {
            if !existing.isLift || existing.sessionName != sessionName {
                existing.isLift = true
                existing.sessionName = sessionName
                existing.focus = ""
                existing.startedAt = nil
                existing.completedAt = nil
            }
            return existing
        }
        return TodaySession(date: today, sessionName: sessionName, focus: "", isLift: true, isDeload: false,
                            block: nil, week: nil, updatedAt: now)
    }

    // MARK: Readiness + profile

    /// Publish the day's readiness. Returns false (and writes nothing) when there's no score.
    @discardableResult
    public static func writeReadiness(_ readiness: Readiness, now: Date = .now,
                                      defaults: UserDefaults? = AppGroup.defaults) -> Bool {
        guard let record = ReadinessRecord(readiness, now: now) else { return false }
        write(record, key: Key.readiness, to: defaults)
        return true
    }

    public static func writeProfile(_ profile: CoachProfile, now: Date = .now,
                                    defaults: UserDefaults? = AppGroup.defaults) {
        write(ProfileRecord(profile, now: now), key: Key.profile, to: defaults)
    }

    // MARK: Fuel → Tonnage

    /// Fuel's status for TODAY, or nil if absent, unreadable, or stale (a different `dayKey`).
    public static func readFuelStatus(now: Date = .now,
                                      defaults: UserDefaults? = AppGroup.defaults) -> FuelStatus? {
        guard let status = read(FuelStatus.self, key: Key.fuelStatus, from: defaults),
              status.dayKey == dayKey(now) else { return nil }
        return status
    }
}
