import Foundation
import SwiftData
import os

private let saveLog = Logger(subsystem: "com.dwayne.tonnage", category: "persistence")

public extension Notification.Name {
    /// Posted on the main actor when a SwiftData save fails. `userInfo["message"]` is a
    /// short description; the app shows it so a failed save is never silent.
    static let tonnageSaveFailed = Notification.Name("tonnage.saveFailed")
}

public extension ModelContext {
    /// `save()` that never silently loses data: failures are logged (visible in Console /
    /// sysdiagnose), posted as `.tonnageSaveFailed` so the app can tell the user, and trap
    /// in debug builds so they can't slip through testing unnoticed. Returns whether the
    /// save worked.
    @discardableResult
    func saveOrReport(_ site: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            saveLog.error("SwiftData save failed at \(site, privacy: .public):\(line) — \(error, privacy: .public)")
            NotificationCenter.default.post(name: .tonnageSaveFailed, object: nil,
                                            userInfo: ["message": error.localizedDescription])
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                assertionFailure("SwiftData save failed at \(site):\(line) — \(error)")
            }
#endif
            return false
        }
    }
}
