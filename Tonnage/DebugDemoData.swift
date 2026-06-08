#if DEBUG
import Foundation
import SwiftData
import TonnageCore

/// Simulator/dev-only sample data. Seeds three weeks of realistic training against the
/// current program so DATA, the Today card, per-muscle volume, PRs, progression, and the
/// share cards all populate without needing a device + Apple Watch. Compiled out of release.
enum DemoData {

    /// Wipes existing logged data, then seeds 3 weeks of workouts + a few cardio sessions
    /// into Block 01. Returns silently if there's no program yet.
    @MainActor
    static func seedTrainingData(in context: ModelContext) {
        resetLoggedData(in: context)
        guard let program = try? context.fetch(FetchDescriptor<Program>()).first else { return }
        let sessions = program.orderedSessions
        guard !sessions.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let block = 1
        let weeks = 3

        for week in 1...weeks {
            for (si, session) in sessions.enumerated() {
                // Spread sessions through the week; week 3 lands in the last 7 days.
                let daysAgo = (weeks - week) * 7 + (sessions.count - 1 - si) * 2 + 1
                guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }

                let workout = LoggedWorkout(date: date, blockNumber: block, weekNumber: week,
                                            dayType: .lift, sessionName: session.name,
                                            sessionTemplate: session)
                context.insert(workout)     // insert BEFORE wiring relationships so children cascade-save
                workout.exercises = session.orderedExercises.enumerated().map { ei, t in
                    let ex = LoggedExercise(name: t.name, isCompound: t.isCompound, isCardio: t.isCardio,
                                            sortOrder: ei, prescribedSets: t.prescribedSets,
                                            repRange: t.repRange, rpeTarget: t.rpeTarget,
                                            prescriptionNotes: t.notes, exerciseTemplate: t)
                    ex.sets = demoSets(for: t, week: week)
                    return ex
                }
            }
            // A standalone full-rest day mid-week, to populate rest history too.
            if let restDate = cal.date(byAdding: .day, value: -((weeks - week) * 7 + 3), to: today) {
                context.insert(LoggedWorkout(date: restDate, blockNumber: block, weekNumber: week,
                                             dayType: .fullRest, sessionName: TrainStore.restSlotName))
            }
        }

        seedActivities(in: context, today: today, cal: cal)
        try? context.save()
    }

    /// Completed sets that progress ~5 lb/week (so e1RM climbs and PRs fire), with a
    /// warm-up set on compounds to show the "W" badge.
    private static func demoSets(for t: ExerciseTemplate, week: Int) -> [LoggedSet] {
        if t.isCardio {
            return [LoggedSet(durationSeconds: 20 * 60, completed: true, sortOrder: 0)]
        }
        let weight = (t.isCompound ? 135.0 : 50.0) + Double(week - 1) * 5
        let reps = max(1, CoachEngine.lowRep(of: t.repRange))
        var sets: [LoggedSet] = []
        var order = 0
        if t.isCompound {
            sets.append(LoggedSet(weight: (weight * 0.5).rounded(), reps: 8,
                                  completed: true, isWarmup: true, sortOrder: order))
            order += 1
        }
        for _ in 0..<max(1, t.prescribedSets) {
            sets.append(LoggedSet(weight: weight, reps: reps, rpe: 8, completed: true, sortOrder: order))
            order += 1
        }
        return sets
    }

    private static func seedActivities(in context: ModelContext, today: Date, cal: Calendar) {
        let specs: [(String, ActivityKind, Int, Int, Double?)] = [
            ("Bike", .bike, 35, 2, 8.4),
            ("Walk", .walk, 30, 4, 1.6),
            ("Bike", .bike, 42, 9, 10.2),
            ("Stair Master", .stairMaster, 20, 12, nil)
        ]
        for (name, kind, minutes, daysAgo, miles) in specs {
            guard let d = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            context.insert(Activity(name: name, kind: kind, durationMinutes: minutes,
                                    distanceMiles: miles,
                                    activeCalories: Int((kind.kcalPerMinute * Double(minutes)).rounded()),
                                    detail: "Demo", date: d))
        }
    }
}
#endif
