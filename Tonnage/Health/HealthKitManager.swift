import Foundation
import HealthKit
import SwiftData
import TonnageCore

/// A single dated value for the recovery trend charts.
struct DatedValue: Identifiable, Sendable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Daily recovery series (HRV / resting HR / sleep) for the Recovery screen.
struct RecoverySeries: Sendable {
    var hrv: [DatedValue] = []
    var restingHR: [DatedValue] = []
    var sleepHours: [DatedValue] = []
}

/// Central HealthKit gateway: authorization, reads (bodyweight / resting HR / sleep),
/// and writes (workouts + bodyweight). The app works fully with Health off — every
/// path guards `isAvailable` and tolerates denied access by simply showing no data.
@MainActor
@Observable
final class HealthKitManager {
    struct BodyweightSample: Identifiable, Sendable, Equatable {
        let date: Date
        let pounds: Double
        var id: Date { date }
    }

    private let store = HKHealthStore()

    private(set) var bodyweight: [BodyweightSample] = []     // ascending by date
    private(set) var latestRestingHR: Double?
    private(set) var restingHRBaseline: Double?              // ~14-day mean
    private(set) var latestHRV: Double?                      // SDNN, ms
    private(set) var hrvBaseline: Double?                    // ~14-day mean
    private(set) var lastNightSleepHours: Double?
    private(set) var trainedYesterday: Bool = false

    /// Whether the user has been through the auth prompt (HealthKit hides read status).
    var hasRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "hk.requested") }
        set { UserDefaults.standard.set(newValue, forKey: "hk.requested") }
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Types
    private let bodyMass = HKQuantityType(.bodyMass)
    private let restingHR = HKQuantityType(.restingHeartRate)
    private let heartRate = HKQuantityType(.heartRate)
    private let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let sleep = HKCategoryType(.sleepAnalysis)

    private var readTypes: Set<HKObjectType> { [bodyMass, restingHR, heartRate, hrv, activeEnergy, sleep, HKObjectType.workoutType()] }
    private var shareTypes: Set<HKSampleType> { [HKQuantityType.workoutType(), bodyMass, activeEnergy] }

    // MARK: Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            hasRequested = true
            await refresh()
        } catch {
            // Leave data empty; UI shows the connect affordance.
        }
    }

    func refresh() async {
        guard isAvailable else { return }
        await loadBodyweight()
        await loadResting()
        await loadHRV()
        await loadSleep()
        await loadTrainedYesterday()
    }

    /// Today's training-readiness read, built from the latest HealthKit signals.
    func currentReadiness() -> Readiness {
        ReadinessEngine.evaluate(ReadinessInputs(
            hrvMs: latestHRV, hrvBaselineMs: hrvBaseline,
            restingHR: latestRestingHR, restingHRBaseline: restingHRBaseline,
            sleepHours: lastNightSleepHours, trainedYesterday: trainedYesterday
        ))
    }

#if DEBUG
    // MARK: Demo data (DEBUG only)
    //
    // The iOS Simulator has no Apple Watch, so it never has HRV / resting HR / sleep —
    // which means the Readiness card and Recovery charts can't be exercised there. This
    // path serves realistic synthetic signals so the whole Tier-1/Tier-2 surface can be
    // seen and demoed. It is compiled OUT of release builds entirely.

    /// Whether the synthetic recovery feed is active. Persisted so it survives relaunch.
    var isDemoRecovery: Bool {
        get { UserDefaults.standard.bool(forKey: "hk.demoRecovery") }
        set { UserDefaults.standard.set(newValue, forKey: "hk.demoRecovery") }
    }

    /// Flip the demo feed on/off and update the in-memory signals accordingly.
    func setDemoRecovery(_ on: Bool) async {
        isDemoRecovery = on
        if on {
            loadDemoSignals()
        } else if hasRequested {
            await refresh()              // fall back to real Health (likely still empty on Sim)
        } else {
            clearSignals()               // back to the "Connect Apple Health" empty state
        }
    }

    /// Re-apply the demo feed at launch if it was left on.
    func applyDemoRecoveryIfEnabled() {
        if isDemoRecovery { loadDemoSignals() }
    }

    private func clearSignals() {
        latestHRV = nil; hrvBaseline = nil
        latestRestingHR = nil; restingHRBaseline = nil
        lastNightSleepHours = nil; trainedYesterday = false
    }

    /// "Today" numbers that band to a clearly-recovered read (~primed/ready), plus a
    /// bodyweight trend so the DATA tab has something to draw too.
    private func loadDemoSignals() {
        latestHRV = 72;        hrvBaseline = 61
        latestRestingHR = 53;  restingHRBaseline = 57
        lastNightSleepHours = 7.8
        trainedYesterday = false
        if bodyweight.isEmpty { bodyweight = Self.demoBodyweight() }
    }

    private static func demoBodyweight() -> [BodyweightSample] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0...28).reversed().compactMap { k in
            guard let d = cal.date(byAdding: .day, value: -k, to: today) else { return nil }
            let t = Double(28 - k)
            let lb = 181.5 - t * 0.06 + sin(t / 4) * 0.5   // slow recomp drift, small daily wiggle
            return BodyweightSample(date: d, pounds: (lb * 10).rounded() / 10)
        }
    }

    /// 14-ish days of believable HRV / resting-HR / sleep for the Recovery trend charts.
    private static func demoSeries(days: Int) -> RecoverySeries {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var hrv: [DatedValue] = [], rhr: [DatedValue] = [], slp: [DatedValue] = []
        for k in (0...days).reversed() {
            guard let d = cal.date(byAdding: .day, value: -k, to: today) else { continue }
            let t = Double(days - k)
            hrv.append(.init(date: d, value: (60 + 9 * sin(t / 2.3) + t * 0.5).rounded()))
            rhr.append(.init(date: d, value: (56 - 1.5 * sin(t / 2.0) - t * 0.08).rounded()))
            let s = 7.1 + 0.7 * sin(t / 1.7 + 1)
            slp.append(.init(date: d, value: (s * 10).rounded() / 10))
        }
        return RecoverySeries(hrv: hrv, restingHR: rhr, sleepHours: slp)
    }
#endif

    // MARK: Reads

    private func loadBodyweight() async {
        let start = Calendar.current.date(byAdding: .day, value: -180, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 400
        )
        guard let samples = try? await descriptor.result(for: store) else { return }
        bodyweight = samples.map {
            BodyweightSample(date: $0.startDate, pounds: $0.quantity.doubleValue(for: .pound()))
        }
    }

    private func loadResting() async {
        let start = Calendar.current.date(byAdding: .day, value: -14, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: restingHR, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 60
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        latestRestingHR = samples.first?.quantity.doubleValue(for: unit)
        restingHRBaseline = baseline(of: samples, unit: unit)
    }

    /// Mean over the prior days (today excluded) so "today vs baseline" compares
    /// against your norm, not against itself. Falls back to the overall mean.
    private func baseline(of samples: [HKQuantitySample], unit: HKUnit) -> Double? {
        let cal = Calendar.current
        let prior = samples.filter { !cal.isDateInToday($0.startDate) }.map { $0.quantity.doubleValue(for: unit) }
        let pool = prior.isEmpty ? samples.map { $0.quantity.doubleValue(for: unit) } : prior
        return pool.isEmpty ? nil : pool.reduce(0, +) / Double(pool.count)
    }

    private func loadHRV() async {
        let start = Calendar.current.date(byAdding: .day, value: -14, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrv, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return }
        let unit = HKUnit.secondUnit(with: .milli)
        latestHRV = samples.first?.quantity.doubleValue(for: unit)
        hrvBaseline = baseline(of: samples, unit: unit)
    }

    private func loadTrainedYesterday() async {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 20
        )
        guard let workouts = try? await descriptor.result(for: store) else { return }
        trainedYesterday = workouts.contains { $0.duration >= 600 }   // any session ≥ 10 min in the last 36h
    }

    // MARK: Recovery trend series (for the Recovery screen)

    /// Daily HRV / resting-HR / sleep over the last `days`, bucketed by calendar day.
    func recoverySeries(days: Int = 14) async -> RecoverySeries {
#if DEBUG
        if isDemoRecovery { return Self.demoSeries(days: days) }
#endif
        guard isAvailable else { return RecoverySeries() }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        return RecoverySeries(
            hrv: await dailyAverage(of: hrv, unit: .secondUnit(with: .milli), predicate: predicate, cal: cal),
            restingHR: await dailyAverage(of: restingHR, unit: .count().unitDivided(by: .minute()), predicate: predicate, cal: cal),
            sleepHours: await dailySleepHours(predicate: predicate, cal: cal)
        )
    }

    private func dailyAverage(of type: HKQuantityType, unit: HKUnit, predicate: NSPredicate, cal: Calendar) async -> [DatedValue] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 4000
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        var sums: [Date: (total: Double, count: Int)] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.startDate)
            let v = s.quantity.doubleValue(for: unit)
            let cur = sums[day] ?? (0, 0)
            sums[day] = (cur.total + v, cur.count + 1)
        }
        return sums.keys.sorted().map { DatedValue(date: $0, value: sums[$0]!.total / Double(sums[$0]!.count)) }
    }

    private func dailySleepHours(predicate: NSPredicate, cal: Calendar) async -> [DatedValue] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        var secs: [Date: Double] = [:]
        for s in samples where asleep.contains(s.value) {
            // Attribute to the wake-up day. Apple Watch records a single night as many
            // stage samples — some end before midnight, some after. Bucketing by raw
            // `startOfDay(endDate)` splits one night across two calendar days. Shifting
            // by +6h re-anchors the "day" at 18:00 so the whole night lands on the day
            // it ended, and afternoon naps still attribute to the same day.
            let day = cal.startOfDay(for: s.endDate.addingTimeInterval(6 * 3600))
            secs[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        return secs.keys.sorted().map { DatedValue(date: $0, value: secs[$0]! / 3600) }
    }

    private func loadSleep() async {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        guard let samples = try? await descriptor.result(for: store) else { return }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        lastNightSleepHours = seconds > 0 ? seconds / 3600 : nil
    }

    // MARK: Writes

    func saveBodyMass(pounds: Double, date: Date = .now) async {
        guard isAvailable, pounds > 0 else { return }
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        let sample = HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date)
        try? await store.save(sample)
        await loadBodyweight()
    }

    func saveWorkout(activityType: HKWorkoutActivityType, start: Date, end: Date, energyKcal: Double?) async {
        guard isAvailable, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let energyKcal, energyKcal > 0 {
                let energy = HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal)
                let sample = HKQuantitySample(type: activeEnergy, quantity: energy, start: start, end: end)
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Non-fatal: the workout is still in SwiftData; Health just didn't get it.
        }
    }

    /// Convenience for a finished lifting session.
    func saveLiftingSession(start: Date, end: Date) async {
        let minutes = max(1, end.timeIntervalSince(start) / 60)
        await saveWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                          energyKcal: minutes * 5)   // rough estimate
    }

    /// Convenience for a logged MOVE activity.
    func saveActivity(_ activity: Activity) async {
        let end = activity.date
        let start = end.addingTimeInterval(-Double(max(1, activity.durationMinutes)) * 60)
        await saveWorkout(activityType: activity.kind.hkActivityType,
                          start: start, end: end,
                          energyKcal: Double(activity.durationMinutes) * activity.kind.kcalPerMinute)
    }

    // MARK: Import external workouts

    /// Pulls workouts logged by OTHER apps (Apple Workout app, etc.) from Health and
    /// records them as MOVE activities. Skips Tonnage's own workouts and de-dupes by UUID.
    func importExternalWorkouts(into context: ModelContext) async {
        guard isAvailable, hasRequested else { return }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 50
        )
        guard let workouts = try? await descriptor.result(for: store) else { return }

        let key = "hk.importedWorkouts"
        var imported = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        var didInsert = false

        for workout in workouts {
            let id = workout.uuid.uuidString
            guard !imported.contains(id) else { continue }
            imported.insert(id)
            // Skip our own (already logged as sessions/activities).
            if workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.dwayne.tonnage") { continue }
            // Skip strength workouts (e.g. a lift tracked in Apple's Workout app) — those
            // are logged set-by-set in TRAIN, not conditioning entries in MOVE.
            if Self.isStrengthWorkout(workout.workoutActivityType) { continue }

            let (name, kind) = Self.mapped(workout.workoutActivityType)
            let minutes = max(1, Int((workout.duration / 60).rounded()))
            let activity = Activity(name: name, kind: kind, durationMinutes: minutes,
                                    detail: "Imported from Apple Health", date: workout.startDate)
            context.insert(activity)
            didInsert = true
        }
        if didInsert { try? context.save() }
        UserDefaults.standard.set(Array(imported), forKey: key)
    }

    /// Lifting workouts belong in TRAIN (logged with sets), never imported into MOVE.
    private static func isStrengthWorkout(_ type: HKWorkoutActivityType) -> Bool {
        type == .traditionalStrengthTraining || type == .functionalStrengthTraining
    }

    private static func mapped(_ type: HKWorkoutActivityType) -> (name: String, kind: ActivityKind) {
        switch type {
        case .walking:                                                  ("Walk", .walk)
        case .hiking:                                                   ("Hike", .walk)
        case .running:                                                  ("Run", .sport)
        case .cycling:                                                  ("Bike", .bike)
        case .stairClimbing, .stairs, .stepTraining:                    ("Stairs", .stairMaster)
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining: ("Strength", .sport)
        case .highIntensityIntervalTraining:                            ("HIIT", .sport)
        case .coreTraining:                                             ("Core", .sport)
        case .flexibility, .cooldown, .preparationAndRecovery:          ("Mobility", .mobility)
        case .yoga, .mindAndBody:                                       ("Yoga", .mobility)
        case .pilates:                                                  ("Pilates", .mobility)
        case .swimming:                                                 ("Swim", .sport)
        case .rowing:                                                   ("Row", .sport)
        case .elliptical:                                               ("Elliptical", .sport)
        case .golf:                                                     ("Golf", .sport)
        case .tennis:                                                   ("Tennis", .sport)
        case .pickleball:                                               ("Pickleball", .sport)
        case .basketball:                                               ("Basketball", .sport)
        case .soccer:                                                   ("Soccer", .sport)
        case .americanFootball:                                         ("Football", .sport)
        case .baseball:                                                 ("Baseball", .sport)
        case .boxing, .kickboxing:                                      ("Boxing", .sport)
        case .dance, .cardioDance:                                      ("Dance", .sport)
        default:                                                        ("Workout", .custom)
        }
    }
}

// MARK: - ActivityKind → HealthKit

extension ActivityKind {
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .walk, .weightedVestWalk: .walking
        case .stadiumStairs, .stairMaster: .stairClimbing
        case .bike: .cycling
        case .sport: .other
        case .mobility: .flexibility
        case .recovery: .preparationAndRecovery
        case .custom: .other
        }
    }

    var kcalPerMinute: Double {
        switch self {
        case .walk: 4
        case .weightedVestWalk: 6
        case .stadiumStairs, .stairMaster: 9
        case .bike: 8
        case .sport: 7
        case .mobility, .recovery: 3
        case .custom: 5
        }
    }
}
