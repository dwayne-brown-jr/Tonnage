import SwiftUI
import UserNotifications
import AudioToolbox

/// Drives the rest timer. Counts down in-app via a ticker; schedules a local
/// notification so it still fires when the app is backgrounded or the phone is
/// locked. Fires a haptic + sound on completion in the foreground.
@MainActor
@Observable
final class RestTimer {
    enum Phase { case idle, running, done }

    private(set) var phase: Phase = .idle
    private(set) var remainingSeconds = 0
    private(set) var totalSeconds = 0
    private(set) var label = ""

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var firedPreWarning = false

    /// Pre-warning fires this many seconds before rest completes (long rests only).
    private static let preWarningSeconds = 30

    private static let notifID = "tonnage.resttimer"

    // Defaults (seconds) — overridable later from Settings via UserDefaults.
    static var compoundDefault: Int { UserDefaults.standard.object(forKey: "rest.compound") as? Int ?? 180 }
    static var isolationDefault: Int { UserDefaults.standard.object(forKey: "rest.isolation") as? Int ?? 75 }

    var isVisible: Bool { phase != .idle }
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    // MARK: Control

    func startRest(forCompound isCompound: Bool, label: String) {
        start(seconds: isCompound ? Self.compoundDefault : Self.isolationDefault, label: label)
    }

    func start(seconds: Int, label: String) {
        self.label = label
        self.totalSeconds = seconds
        self.remainingSeconds = seconds
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        self.endDate = end
        self.phase = .running
        self.firedPreWarning = seconds <= Self.preWarningSeconds * 2   // short rests skip the warning
        requestAuthorizationIfNeeded()
        scheduleNotification(in: seconds)
        RestLiveActivity.start(endDate: end, exerciseName: label, totalSeconds: seconds)
        startTicker()
        Haptics.impact(.medium)
    }

    func addTime(_ seconds: Int) {
        guard phase == .running, let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        endDate = newEnd
        totalSeconds = max(totalSeconds, totalSeconds + seconds)
        remainingSeconds = computeRemaining()
        if remainingSeconds > Self.preWarningSeconds * 2 { firedPreWarning = false }   // re-arm after extend
        scheduleNotification(in: remainingSeconds)
        RestLiveActivity.update(endDate: newEnd, exerciseName: label, totalSeconds: totalSeconds)
        Haptics.impact(.light)
    }

    /// User skipped/dismissed — silent.
    func skip() { clear(silent: true) }

    // MARK: Ticking

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let r = computeRemaining()
        // Only publish when the displayed second actually changes — the 0.2s tick (for prompt
        // completion) would otherwise re-render the bar 5×/sec on the same value.
        if r != remainingSeconds { remainingSeconds = r }
        if !firedPreWarning && r > 0 && r <= Self.preWarningSeconds {
            firedPreWarning = true
            Haptics.impact(.medium)        // heads-up: ~30s left, start setting up
        }
        if r <= 0 { fireComplete() }
    }

    private func computeRemaining() -> Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    private func fireComplete() {
        ticker?.invalidate(); ticker = nil
        phase = .done
        remainingSeconds = 0
        Haptics.success()
        AudioServicesPlaySystemSound(1322)
        cancelNotification()                       // foreground handled it
        autoDismiss()
    }

    private func autoDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if phase == .done { clear(silent: true) }
        }
    }

    private func clear(silent: Bool) {
        ticker?.invalidate(); ticker = nil
        endDate = nil
        phase = .idle
        cancelNotification()
        RestLiveActivity.end()
    }

    // MARK: Scene phase (keeps the in-app ring honest across background)

    func handleScenePhase(_ scenePhase: ScenePhase) {
        guard phase == .running else { return }
        switch scenePhase {
        case .active:
            remainingSeconds = computeRemaining()
            if remainingSeconds <= 0 {
                clear(silent: true)                // completed while backgrounded; the notification alerted
            } else {
                startTicker()
            }
        case .background, .inactive:
            ticker?.invalidate(); ticker = nil
        @unknown default:
            break
        }
    }

    // MARK: Notifications

    private func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(in seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notifID])
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = label.isEmpty ? "Time for your next set." : "\(label) — time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notifID, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifID])
    }
}
