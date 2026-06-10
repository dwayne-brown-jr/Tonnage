import Foundation
import SwiftData

/// Codable snapshot of a logged activity (for JSON backup/restore).
public struct ActivityPayload: Codable, Sendable, Equatable {
    public var name: String
    public var kind: ActivityKind
    public var durationMinutes: Int
    public var distanceMiles: Double?
    public var flights: Int?
    public var activeCalories: Int?
    public var detail: String
    public var date: Date

    public init(name: String, kind: ActivityKind, durationMinutes: Int,
                distanceMiles: Double?, flights: Int?, activeCalories: Int? = nil,
                detail: String, date: Date) {
        self.name = name; self.kind = kind; self.durationMinutes = durationMinutes
        self.distanceMiles = distanceMiles; self.flights = flights; self.activeCalories = activeCalories
        self.detail = detail; self.date = date
    }
}

/// Full export of the user's logged data (program seed is recreated on launch, so
/// it isn't included).
public struct BackupData: Codable, Sendable, Equatable {
    /// Bump when the backup schema changes shape. Imports from a NEWER version are
    /// rejected (decoded → nil) rather than half-read into the store.
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var workouts: [WorkoutPayload]
    public var activities: [ActivityPayload]

    public init(version: Int = BackupData.currentVersion, exportedAt: Date = .now,
                workouts: [WorkoutPayload], activities: [ActivityPayload]) {
        self.version = version; self.exportedAt = exportedAt
        self.workouts = workouts; self.activities = activities
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    public func encoded() throws -> Data { try Self.coder().0.encode(self) }
    public static func decoded(from data: Data) -> BackupData? {
        guard let backup = try? coder().1.decode(BackupData.self, from: data),
              backup.version <= currentVersion else { return nil }
        return backup
    }
}

@MainActor
public func makeBackup(workouts: [LoggedWorkout], activities: [Activity]) -> BackupData {
    BackupData(
        // Full-fidelity snapshot (warm-up flags, cardio metrics, notes) — the same
        // mapping the watch sync uses, so backup and sync can never drift apart.
        workouts: workouts.map { WorkoutPayload(from: $0) },
        activities: activities.map {
            ActivityPayload(name: $0.name, kind: $0.kind, durationMinutes: $0.durationMinutes,
                            distanceMiles: $0.distanceMiles, flights: $0.flights, activeCalories: $0.activeCalories,
                            detail: $0.detail, date: $0.date)
        }
    )
}

/// Restores a backup: workouts replace any existing (week, session); activities are added
/// but de-duped (same kind + minute) so re-importing the same backup doesn't double them.
@MainActor
public func applyBackup(_ backup: BackupData, to context: ModelContext) {
    for workout in backup.workouts { applyWorkoutPayload(workout, to: context) }

    let existing = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
    let cal = Calendar.current
    func isDuplicate(_ a: ActivityPayload) -> Bool {
        existing.contains { $0.kind == a.kind && $0.name == a.name
            && cal.isDate($0.date, equalTo: a.date, toGranularity: .minute) }
    }
    for a in backup.activities where !isDuplicate(a) {
        context.insert(Activity(name: a.name, kind: a.kind, durationMinutes: a.durationMinutes,
                                distanceMiles: a.distanceMiles, flights: a.flights,
                                activeCalories: a.activeCalories, detail: a.detail, date: a.date))
    }
    context.saveOrReport()
}

/// Wipes all logged data (keeps the program). Used by Settings → Reset.
@MainActor
public func resetLoggedData(in context: ModelContext) {
    if let workouts = try? context.fetch(FetchDescriptor<LoggedWorkout>()) {
        for w in workouts { context.delete(w) }
    }
    if let activities = try? context.fetch(FetchDescriptor<Activity>()) {
        for a in activities { context.delete(a) }
    }
    context.saveOrReport()
}
