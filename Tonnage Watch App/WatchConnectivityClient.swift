import Foundation
import WatchConnectivity
import TonnageCore

/// Sends finished workouts from the watch to the phone (which persists them).
@MainActor
@Observable
final class WatchConnectivityClient: NSObject {
    static let shared = WatchConnectivityClient()
    /// Live "phone is currently reachable" — updates on activation AND when reachability
    /// changes mid-session (the WCSession delegate fires both).
    private(set) var reachable = false
    /// Timestamp of the most recent application-context delivery FROM the phone.
    /// `nil` means no fresh receive this session — cached state may still be present.
    private(set) var lastSyncedAt: Date?

    /// Sessions the phone has logged for the current block (so the watch can mirror
    /// what was done on the phone). Keyed by (week, sessionName) via `loggedWorkout`.
    private(set) var loggedWorkouts: [WorkoutPayload] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyRestDefaults(session.receivedApplicationContext)   // seed from any prior context
        applyWorkouts(session.receivedApplicationContext)
    }

    /// The logged workout the phone synced for a given week + session, if any.
    func loggedWorkout(week: Int, session: String) -> WorkoutPayload? {
        loggedWorkouts.first { $0.weekNumber == week && $0.sessionName == session }
    }

    private func applyWorkouts(_ context: [String: Any]) {
        setLoggedWorkouts(fromData: context["workouts"] as? Data)
    }

    private func setLoggedWorkouts(fromData data: Data?) {
        guard let data, let payloads = try? JSONDecoder().decode([WorkoutPayload].self, from: data) else { return }
        loggedWorkouts = payloads
    }

    /// Live, latest-state sync — pushed after every logged set so the phone reflects
    /// the in-progress session without a manual tap.
    func syncLive(_ payload: WorkoutPayload) {
        guard WCSession.isSupported(), let data = try? payload.encoded() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(["workout": data])
    }

    /// Final, guaranteed delivery on Finish.
    func send(_ payload: WorkoutPayload) {
        guard WCSession.isSupported(), let data = try? payload.encoded() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(["workout": data])
    }

    private func applyRestDefaults(_ context: [String: Any]) {
        if let c = context["rest.compound"] as? Int { UserDefaults.standard.set(c, forKey: "rest.compound") }
        if let i = context["rest.isolation"] as? Int { UserDefaults.standard.set(i, forKey: "rest.isolation") }
        if let b = context["currentBlock"] as? Int { UserDefaults.standard.set(b, forKey: "currentBlock") }
    }
}

extension WatchConnectivityClient: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }

    /// Keep `reachable` fresh while the watch app is running (the phone going in/out of
    /// range fires this — without it the green-dot indicator gets stuck on its initial value).
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }

    // Phone pushes the rest-timer defaults here.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let compound = applicationContext["rest.compound"] as? Int
        let isolation = applicationContext["rest.isolation"] as? Int
        let block = applicationContext["currentBlock"] as? Int
        let workoutsData = applicationContext["workouts"] as? Data
        Task { @MainActor in
            if let compound { UserDefaults.standard.set(compound, forKey: "rest.compound") }
            if let isolation { UserDefaults.standard.set(isolation, forKey: "rest.isolation") }
            if let block { UserDefaults.standard.set(block, forKey: "currentBlock") }
            self.setLoggedWorkouts(fromData: workoutsData)   // mirror phone-logged sessions
            self.lastSyncedAt = Date()                       // mark a fresh delivery
            WatchWidgetSync.refresh()   // keep the complication's block in step with the phone
        }
    }
}
