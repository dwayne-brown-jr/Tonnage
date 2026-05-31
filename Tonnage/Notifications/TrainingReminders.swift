import Foundation
import UserNotifications

/// Schedules weekly local notifications nudging the athlete to train on their chosen
/// days/time. Settings persist in UserDefaults; the OS keeps the repeating triggers
/// alive across launches, so we only (re)schedule when something changes or when the
/// Settings screen reappears (to recover from a permission flip in iOS Settings).
///
/// Local notifications need no entitlement or Info.plist key — only a runtime
/// authorization prompt, requested the first time the user turns reminders on.
@MainActor
@Observable
final class TrainingReminders {

    /// Master on/off. Mutating any setting re-persists and re-schedules.
    var isEnabled: Bool { didSet { persistAndReschedule() } }
    var hour: Int       { didSet { persistAndReschedule() } }
    var minute: Int     { didSet { persistAndReschedule() } }
    /// Calendar weekdays to fire on (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> { didSet { persistAndReschedule() } }

    /// True when the user has denied notifications at the system level — the UI uses
    /// this to point them at iOS Settings instead of silently failing to fire.
    private(set) var authDenied = false

    private let center = UNUserNotificationCenter.current()

    private enum Key {
        static let enabled  = "reminders.enabled"
        static let hour     = "reminders.hour"
        static let minute   = "reminders.minute"
        static let weekdays = "reminders.weekdays"
    }

    init() {
        let d = UserDefaults.standard
        isEnabled = d.bool(forKey: Key.enabled)
        hour   = d.object(forKey: Key.hour) as? Int ?? 18      // 6:00 PM default
        minute = d.object(forKey: Key.minute) as? Int ?? 0
        if let raw = d.string(forKey: Key.weekdays), !raw.isEmpty {
            weekdays = Set(raw.split(separator: ",").compactMap { Int($0) })
        } else {
            weekdays = [2, 3, 5, 6]   // Mon/Tue/Thu/Fri — matches the default 4-day split
        }
        // Note: didSet does NOT fire during init, so this doesn't schedule anything yet.
    }

    // MARK: Public API

    /// Toggle reminders, requesting authorization the first time. Returns nothing —
    /// `isEnabled` / `authDenied` reflect the outcome for the UI.
    func setEnabled(_ on: Bool) async {
        guard on else { isEnabled = false; return }
        if await authorize() {
            authDenied = false
            isEnabled = true            // didSet schedules
        } else {
            authDenied = true
            isEnabled = false
        }
    }

    /// Re-check system permission (e.g. when Settings reappears) and keep the OS
    /// schedule in sync if we believe reminders are on.
    func refreshAuthStatus() async {
        let status = await center.notificationSettings().authorizationStatus
        authDenied = (status == .denied)
        if isEnabled && status != .denied { scheduleNow() }
    }

    // MARK: Scheduling

    private func persistAndReschedule() {
        let d = UserDefaults.standard
        d.set(isEnabled, forKey: Key.enabled)
        d.set(hour, forKey: Key.hour)
        d.set(minute, forKey: Key.minute)
        d.set(weekdays.sorted().map(String.init).joined(separator: ","), forKey: Key.weekdays)
        scheduleNow()
    }

    private func scheduleNow() {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
        guard isEnabled, !weekdays.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to train"
        content.body = "Today's a training day — log your session in Tonnage."
        content.sound = .default

        for wd in weekdays {
            var comps = DateComponents()
            comps.weekday = wd
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "training-reminder-\(wd)",
                                                content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func authorize() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied:                               return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:                           return false
        }
    }

    private static var allIdentifiers: [String] { (1...7).map { "training-reminder-\($0)" } }
}
