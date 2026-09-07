import SwiftData
import os

private let saveLog = Logger(subsystem: "com.dwayne.tonnage", category: "persistence")

public extension ModelContext {
    /// `save()` that never silently loses data: failures are logged (visible in Console /
    /// sysdiagnose) and trap in debug builds so they can't slip through testing unnoticed.
    func saveOrReport(_ site: StaticString = #fileID, line: UInt = #line) {
        do {
            try save()
        } catch {
            saveLog.error("SwiftData save failed at \(site, privacy: .public):\(line) — \(error, privacy: .public)")
            assertionFailure("SwiftData save failed at \(site):\(line) — \(error)")
        }
    }
}
