import Foundation
import WatchConnectivity
import SwiftData
import TonnageCore

/// Receives finished workouts from the watch and writes them into the phone's
/// SwiftData store (the source of truth).
final class PhoneConnectivity: NSObject, @unchecked Sendable {
    static let shared = PhoneConnectivity()
    @MainActor private var container: ModelContainer?

    @MainActor
    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push the rest-timer defaults, active block and week, the program's sessions and the
    /// current block's logged workouts to the watch (latest-state channel), so the watch
    /// runs the phone's real program and mirrors what was logged on the phone.
    @MainActor
    func pushContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var dict = Self.contextDict()
        if let program = programData() { dict["program"] = program }
        if let workouts = currentBlockWorkoutsData() { dict["workouts"] = workouts }
        try? session.updateApplicationContext(dict)
    }

    static func contextDict() -> [String: Any] {
        let d = UserDefaults.standard
        return [
            "rest.compound": d.object(forKey: "rest.compound") as? Int ?? 180,
            "rest.isolation": d.object(forKey: "rest.isolation") as? Int ?? 75,
            "currentBlock": d.object(forKey: "currentBlock") as? Int ?? 1,
            "currentWeek": d.object(forKey: "train.week") as? Int ?? 1
        ]
    }

    /// The program's session templates, encoded as a `ProgramPayload`.
    @MainActor
    private func programData() -> Data? {
        guard let context = container?.mainContext,
              let program = try? context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt)])).first
        else { return nil }
        return try? ProgramPayload(from: program).encoded()
    }

    /// Encodes the current block's lift workouts as `[WorkoutPayload]` for the watch.
    @MainActor
    private func currentBlockWorkoutsData() -> Data? {
        guard let context = container?.mainContext else { return nil }
        let block = UserDefaults.standard.object(forKey: "currentBlock") as? Int ?? 1
        let descriptor = FetchDescriptor<LoggedWorkout>(predicate: #Predicate { $0.blockNumber == block })
        guard let workouts = try? context.fetch(descriptor) else { return nil }
        let payloads = workouts.filter { $0.dayType == .lift }.map { WorkoutPayload(from: $0) }
        // Exporting gives new sets their sync IDs — keep them, so the watch's copy matches.
        if context.hasChanges { context.saveOrReport() }
        return try? JSONEncoder().encode(payloads)
    }

    private func apply(_ data: Data) {
        guard let payload = WorkoutPayload.decoded(from: data) else { return }
        Task { @MainActor in
            // Merge, then echo the merged state back so the watch (and its complication)
            // shows the combined session. The widget refreshes from the save itself.
            if let context = self.container?.mainContext, applyWorkoutPayload(payload, to: context) {
                self.pushContext()
            }
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.pushContext() }   // seed settings + active block + logged workouts
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    // Final, guaranteed delivery on Finish.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo["workout"] as? Data { apply(data) }
    }

    // Live, latest-state updates as the watch logs each set.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["workout"] as? Data { apply(data) }
    }
}
