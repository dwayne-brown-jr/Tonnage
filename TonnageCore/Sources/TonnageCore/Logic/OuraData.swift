import Foundation

// Oura API v2 responses (https://cloud.ouraring.com/v2/docs), decoded leniently: every field
// is optional and one bad item doesn't empty the page, so a schema tweak on Oura's side
// degrades to "no Oura data today" instead of an error.

/// One page of an Oura usercollection endpoint.
public struct OuraPage<Item: Decodable>: Decodable {
    public let data: [Item]
    private enum Keys: String, CodingKey { case data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        data = (try? c.decode(Lossy<Item>.self, forKey: .data))?.elements ?? []
    }
}

/// `GET /v2/usercollection/daily_readiness` item.
public struct OuraDailyReadiness: Decodable, Equatable, Sendable {
    public let day: String                    // "2026-10-11"
    public let score: Int?
    public let temperatureDeviation: Double?  // °C vs the ring's baseline
    public let contributors: [String: Int]

    private enum Keys: String, CodingKey { case day, score, temperature_deviation, contributors }

    public init(day: String, score: Int?, temperatureDeviation: Double? = nil, contributors: [String: Int] = [:]) {
        self.day = day; self.score = score
        self.temperatureDeviation = temperatureDeviation; self.contributors = contributors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        day = try c.decode(String.self, forKey: .day)
        score = try? c.decodeIfPresent(Int.self, forKey: .score)
        temperatureDeviation = try? c.decodeIfPresent(Double.self, forKey: .temperature_deviation)
        // Contributors are 1–100 or null; keep the ones with a value.
        let raw = (try? c.decodeIfPresent([String: Int?].self, forKey: .contributors)) ?? nil
        contributors = (raw ?? [:]).compactMapValues { $0 }
    }
}

/// `GET /v2/usercollection/sleep` item — one sleep period (the main night is `long_sleep`).
public struct OuraSleepPeriod: Decodable, Equatable, Sendable {
    public let day: String
    public let type: String?
    public let averageHRV: Double?
    public let lowestHeartRate: Double?
    public let averageBreath: Double?
    public let totalSleepSeconds: Double?

    private enum Keys: String, CodingKey {
        case day, type, average_hrv, lowest_heart_rate, average_breath, total_sleep_duration
    }

    public init(day: String, type: String? = "long_sleep", averageHRV: Double? = nil, lowestHeartRate: Double? = nil,
                averageBreath: Double? = nil, totalSleepSeconds: Double? = nil) {
        self.day = day; self.type = type; self.averageHRV = averageHRV
        self.lowestHeartRate = lowestHeartRate; self.averageBreath = averageBreath
        self.totalSleepSeconds = totalSleepSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        day = try c.decode(String.self, forKey: .day)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        averageHRV = try? c.decodeIfPresent(Double.self, forKey: .average_hrv)
        lowestHeartRate = try? c.decodeIfPresent(Double.self, forKey: .lowest_heart_rate)
        averageBreath = try? c.decodeIfPresent(Double.self, forKey: .average_breath)
        totalSleepSeconds = try? c.decodeIfPresent(Double.self, forKey: .total_sleep_duration)
    }
}

/// Turns Oura's day into Tonnage's `Readiness`: Oura's own score (so it matches the Oura
/// app), banded with Tonnage's thresholds so the training advice stays consistent, and
/// Oura's contributors as the drivers behind it.
public enum OuraReadiness {

    /// Oura's contributor keys, in the order the Oura app lists them, with readable names.
    static let contributorNames: [(key: String, label: String)] = [
        ("previous_night", "Previous night"),
        ("sleep_balance", "Sleep balance"),
        ("previous_day_activity", "Previous day activity"),
        ("activity_balance", "Activity balance"),
        ("body_temperature", "Body temperature"),
        ("resting_heart_rate", "Resting heart rate"),
        ("hrv_balance", "HRV balance"),
        ("recovery_index", "Recovery index"),
    ]

    /// `day` as Oura writes it: yyyy-MM-dd in the user's local calendar.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today's readiness from Oura, or nil when Oura has no score for today yet (the ring
    /// hasn't synced) — the caller then falls back to Tonnage's own Health-based read.
    public static func today(from items: [OuraDailyReadiness], sleep: [OuraSleepPeriod] = [],
                             now: Date = .now, calendar: Calendar = .current) -> Readiness? {
        let day = dayString(now, calendar: calendar)
        guard let item = items.last(where: { $0.day == day }), let score = item.score else { return nil }
        let clamped = max(0, min(100, score))
        let band = ReadinessEngine.band(for: clamped)

        var drivers: [Readiness.Driver] = contributorNames.compactMap { key, label in
            guard let value = item.contributors[key] else { return nil }
            // Oura rates each contributor 1–100; 70 is roughly "fine". Center the bar there.
            let points = Double(max(-30, min(30, value - 70)))
            let sign: Readiness.Driver.Sign = value >= 80 ? .positive : (value < 60 ? .negative : .neutral)
            return Readiness.Driver("\(label) \(value)", sign, points: points, magnitude: 30)
        }
        if let night = sleep.last(where: { $0.day == day && ($0.type ?? "long_sleep") == "long_sleep" }) {
            var parts: [String] = []
            if let hrv = night.averageHRV { parts.append("HRV \(Int(hrv.rounded())) ms") }
            if let hr = night.lowestHeartRate { parts.append("lowest HR \(Int(hr.rounded())) bpm") }
            if let secs = night.totalSleepSeconds { parts.append(String(format: "slept %.1fh", secs / 3600)) }
            if !parts.isEmpty {
                drivers.append(.init("Last night: " + parts.joined(separator: " · "), .neutral, points: 0, magnitude: 1))
            }
        }
        if let t = item.temperatureDeviation {
            let sign: Readiness.Driver.Sign = t > 0.5 ? .negative : .neutral
            drivers.append(.init(String(format: "Temperature %@%.1f°C vs baseline", t >= 0 ? "+" : "−", abs(t)),
                                 sign, points: 0, magnitude: 1))
        }

        var r = Readiness(score: clamped, band: band, drivers: drivers,
                          headline: ReadinessEngine.headline(band), trainingNote: ReadinessEngine.note(band))
        r.source = .oura
        return r
    }
}
