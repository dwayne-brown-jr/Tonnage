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

/// Last night's sleep broken into stages (hours). Deep drives physical recovery, REM
/// supports learning/mood, core (light) is the bulk of the night.
struct SleepStages: Sendable, Equatable {
    var deep: Double = 0
    var rem: Double = 0
    var core: Double = 0
    var total: Double { deep + rem + core }
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

    /// Whether any recovery/body signal actually came back. Read auth is opaque, so this is
    /// how we tell "connected and working" from "connected but nothing here yet" (e.g. no
    /// Apple Watch, or reads were denied) — without ever claiming a false "Connected".
    var hasRecoveryData: Bool {
        latestHRV != nil || latestRestingHR != nil || lastNightSleepHours != nil || !bodyweight.isEmpty
    }

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
        latestRestingHR = mostRecentDayAverage(samples, unit: unit)
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

    /// Average of the most-recent day's samples (samples are sorted newest-first). A single
    /// transient reading — e.g. one low HRV measurement — shouldn't drive readiness, and
    /// this keeps the "today" value consistent with the daily-average trend charts.
    private func mostRecentDayAverage(_ samples: [HKQuantitySample], unit: HKUnit) -> Double? {
        guard let newest = samples.first?.startDate else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: newest)
        let values = samples
            .filter { cal.startOfDay(for: $0.startDate) == day }
            .map { $0.quantity.doubleValue(for: unit) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
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
        latestHRV = mostRecentDayAverage(samples, unit: unit)
        hrvBaseline = baseline(of: samples, unit: unit)
    }

    private func loadTrainedYesterday() async {
        // Yesterday ONLY (start-of-yesterday … start-of-today). The old 36h window caught
        // today's workout too, so logging today's session dropped today's readiness for
        // the work you just did. Readiness is an overnight-recovery read — today's
        // training shouldn't change it.
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let yesterdayStart = cal.date(byAdding: .day, value: -1, to: startOfToday) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: yesterdayStart, end: startOfToday)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 20
        )
        guard let workouts = try? await descriptor.result(for: store) else { return }
        trainedYesterday = workouts.contains { $0.duration >= 600 }   // any session ≥ 10 min yesterday
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

    /// Last night's sleep split into deep / REM / core, using the same +6h wake-day anchor
    /// and recency/min-duration guard as the readiness sleep input (so a nap or stale night
    /// doesn't masquerade as last night). Returns nil if there's no plausible recent night.
    func lastNightSleepStages() async -> SleepStages? {
#if DEBUG
        if isDemoRecovery { return SleepStages(deep: 1.4, rem: 1.8, core: 4.6) }   // ~7.8h, matches demo
#endif
        guard isAvailable, hasRequested else { return nil }
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -36, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        var byDay: [Date: SleepStages] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.endDate.addingTimeInterval(6 * 3600))
            let hours = s.endDate.timeIntervalSince(s.startDate) / 3600
            var stages = byDay[day] ?? SleepStages()
            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: stages.deep += hours
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  stages.rem += hours
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: stages.core += hours
            default: break
            }
            byDay[day] = stages
        }
        guard let day = byDay.keys.max(), let stages = byDay[day], stages.total >= 3,
              cal.isDateInToday(day) || cal.isDateInYesterday(day) else { return nil }
        return stages
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
        // Bucket the last 36h of sleep the SAME way the Recovery chart does
        // (`dailySleepHours`, +6h wake-day anchor) and take the most recent day, rather
        // than summing every asleep sample in the window. The old raw sum folded
        // yesterday's nap into last night, so the number driving readiness could diverge
        // from the one shown on the chart. Sharing the bucketing keeps them in lockstep.
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -36, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let byDay = await dailySleepHours(predicate: predicate, cal: cal)
        // Only trust the most-recent bucket if it plausibly IS last night: anchored to
        // today/yesterday and a real sleep, not a short afternoon nap or a stale partial.
        // Otherwise drop sleep from readiness rather than feeding it a wrong number.
        guard let latest = byDay.last, latest.value >= 3,
              cal.isDateInToday(latest.date) || cal.isDateInYesterday(latest.date) else {
            lastNightSleepHours = nil
            return
        }
        lastNightSleepHours = latest.value
    }

    // MARK: Writes

    func saveBodyMass(pounds: Double, date: Date = .now) async {
        guard isAvailable, pounds > 0 else { return }
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        let sample = HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date)
        try? await store.save(sample)
        await loadBodyweight()
    }

    /// True only if the workout actually reached Health — returns false when write access
    /// was denied or the write failed, so callers don't claim a save that didn't happen.
    @discardableResult
    func saveWorkout(activityType: HKWorkoutActivityType, start: Date, end: Date, energyKcal: Double?) async -> Bool {
        guard isAvailable, end > start else { return false }
        // Workout write status IS reliable (unlike reads) — don't claim success if denied.
        guard store.authorizationStatus(for: HKObjectType.workoutType()) != .sharingDenied else { return false }
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
            return true
        } catch {
            return false   // SwiftData still has it; Health just didn't get it.
        }
    }

    /// Convenience for a finished lifting session. Skips the write if the Watch already
    /// logged this session to Health (so the watch + phone don't double-write), reporting
    /// success either way since the workout IS in Health.
    @discardableResult
    func saveLiftingSession(start: Date, end: Date) async -> Bool {
        if await hasOwnWorkout(type: .traditionalStrengthTraining, from: start, to: end) { return true }
        let minutes = max(1, end.timeIntervalSince(start) / 60)
        return await saveWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                                 energyKcal: minutes * 5)   // rough estimate
    }

    /// Convenience for a logged MOVE activity.
    @discardableResult
    func saveActivity(_ activity: Activity) async -> Bool {
        let end = activity.date
        let start = end.addingTimeInterval(-Double(max(1, activity.durationMinutes)) * 60)
        return await saveWorkout(activityType: activity.kind.hkActivityType,
                                 start: start, end: end,
                                 energyKcal: Double(activity.durationMinutes) * activity.kind.kcalPerMinute)
    }

    /// Whether Tonnage (phone OR Watch) already wrote a workout of `type` overlapping this
    /// window — prevents the Watch's live session and the phone's "Save to Health" button
    /// from both logging the same strength session.
    private func hasOwnWorkout(type: HKWorkoutActivityType, from start: Date, to end: Date) async -> Bool {
        guard isAvailable else { return false }
        let pad: TimeInterval = 60 * 60
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-pad),
                                                    end: end.addingTimeInterval(pad))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [], limit: 50)
        guard let workouts = try? await descriptor.result(for: store) else { return false }
        return workouts.contains {
            $0.workoutActivityType == type &&
            $0.sourceRevision.source.bundleIdentifier.hasPrefix("com.dwayne.tonnage")
        }
    }

    // MARK: Import external workouts

    /// Pulls workouts logged by OTHER apps (Apple Workout app, etc.) from Health and
    /// records them as MOVE activities. Skips Tonnage's own workouts, strength work
    /// (that lives in TRAIN), anything already imported (by HK UUID), and anything that
    /// looks like a session the user already logged by hand (same kind, near the same
    /// time). Returns the number newly imported so callers can give feedback.
    @discardableResult
    func importExternalWorkouts(into context: ModelContext) async -> Int {
        guard isAvailable, hasRequested else { return 0 }
        // 90-day window (vs 30) so a fresh install backfills recent history, with a higher
        // cap for heavy users — paired with the save-gated "seen" set below so nothing is
        // silently dropped and never retried.
        let lookback = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: lookback, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        guard let workouts = try? await descriptor.result(for: store) else { return 0 }

        let key = "hk.importedWorkouts"
        let alreadySeen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])

        // Existing MOVE activities in range — used to skip a workout the user already
        // logged manually (the manual entry mirrors to Health under our own bundle ID and
        // is skipped, but the ORIGINAL third-party workout would otherwise re-add it).
        let existing = (try? context.fetch(
            FetchDescriptor<Activity>(predicate: #Predicate { $0.date >= lookback })
        )) ?? []
        let tolerance: TimeInterval = 30 * 60

        var newlySeen = Set<String>()          // only UUIDs we successfully resolve this run
        var inserted: [Activity] = []

        for workout in workouts {
            let id = workout.uuid.uuidString
            guard !alreadySeen.contains(id), !newlySeen.contains(id) else { continue }
            // Our own workouts + strength work are deterministic skips — safe to remember.
            if workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.dwayne.tonnage") {
                newlySeen.insert(id); continue
            }
            if Self.isStrengthWorkout(workout.workoutActivityType) {
                newlySeen.insert(id); continue
            }
            let (name, kind) = Self.mapped(workout.workoutActivityType)
            // Fuzzy de-dupe against manually-logged + already-inserted activities.
            let isDuplicate = (existing + inserted).contains { a in
                a.kind == kind && abs(a.date.timeIntervalSince(workout.startDate)) < tolerance
            }
            if isDuplicate { newlySeen.insert(id); continue }

            let minutes = max(1, Int((workout.duration / 60).rounded()))
            let activity = Activity(name: name, kind: kind, durationMinutes: minutes,
                                    detail: "Imported from Apple Health", date: workout.startDate)
            context.insert(activity)
            inserted.append(activity)
            newlySeen.insert(id)
        }

        // Only remember this batch once the save actually succeeds. A swallowed failure
        // used to mark workouts "seen" anyway, permanently suppressing them — instead we
        // roll back and persist nothing, so the next run retries cleanly.
        if !inserted.isEmpty {
            do {
                try context.save()
            } catch {
                context.rollback()
                return 0
            }
        }
        UserDefaults.standard.set(Array(alreadySeen.union(newlySeen)), forKey: key)
        return inserted.count
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
