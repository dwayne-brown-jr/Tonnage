import Foundation

/// Spreadsheet-friendly export: one row per logged set, so the data opens cleanly in
/// Numbers/Excel/Sheets or lands with a remote coach without needing the app.
public enum CSVExport {

    public static let header = [
        "date", "block", "week", "session", "day_type", "exercise", "muscle_group",
        "set", "is_warmup", "is_dropset", "is_amrap", "weight_lb", "reps", "reps_left", "completed",
        "duration_sec", "distance_mi", "flights", "set_note", "session_note",
    ].joined(separator: ",")

    /// All workouts (chronological) flattened to set-level CSV rows.
    @MainActor
    public static func workoutsCSV(_ workouts: [LoggedWorkout]) -> String {
        var lines = [header]
        let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        for w in workouts.sorted(by: { $0.date < $1.date }) {
            let date: String = w.date.formatted(dateFormat)
            let sessionNote: String = escape(w.notes)
            for ex in w.orderedExercises {
                let muscle: String = ExerciseLibrary.muscleGroup(for: ex.name)?.label ?? ""
                var workingIndex = 0
                for set in ex.orderedSets {
                    if !set.isWarmup && !set.isDropSet { workingIndex += 1 }   // "1, D, 2" — a drop belongs to its parent
                    var fields: [String] = []
                    fields.append(date)
                    fields.append(String(w.blockNumber))
                    fields.append(String(w.weekNumber))
                    fields.append(escape(w.sessionName))
                    fields.append(w.dayType.rawValue)
                    fields.append(escape(ex.name))
                    fields.append(escape(muscle))
                    fields.append(set.isWarmup ? "W" : (set.isDropSet ? "D" : String(workingIndex)))
                    fields.append(set.isWarmup ? "true" : "false")
                    fields.append(set.isDropSet ? "true" : "false")
                    fields.append(set.isAMRAP ? "true" : "false")
                    fields.append(trimmedNumber(set.weight))
                    fields.append(String(set.reps))
                    fields.append(set.rpe.map { repsLeft(fromRPE: $0) } ?? "")
                    fields.append(set.completed ? "true" : "false")
                    fields.append(set.durationSeconds.map(String.init) ?? "")
                    fields.append(set.distanceMiles.map(trimmedNumber) ?? "")
                    fields.append(set.flights.map(String.init) ?? "")
                    fields.append(escape(set.note ?? ""))
                    fields.append(sessionNote)
                    lines.append(fields.joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC-4180 field escaping: quote anything containing a comma, quote, or newline.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "225" not "225.0", but "187.5" stays exact.
    private static func trimmedNumber(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(x)
    }

    /// Reps left in reserve (the scale the user logs) from the stored RPE.
    private static func repsLeft(fromRPE rpe: Double) -> String {
        trimmedNumber(max(0, 10 - rpe))
    }
}
