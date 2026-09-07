import SwiftUI
import SwiftData
import TonnageCore

@main
struct TonnageApp: App {
    /// Shared SwiftData container (schema + Block 01 seed live in TonnageCore).
    let container: ModelContainer

    init() {
        // SwiftUI's `App` is @MainActor-isolated, so building the seeded container
        // (which touches `mainContext`) is safe here.
        // Under XCTest, use a throwaway in-memory store: the test host runs on a fresh
        // simulator clone with no iCloud, where CloudKit mirroring setup would trap.
        let underTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        container = TonnageStore.makeContainer(inMemory: underTests, cloudKit: !underTests)
        if !underTests {
            PhoneConnectivity.shared.activate(container: container)   // receive watch syncs
#if canImport(MetricKit)
            MetricKitReporter.shared.start()                         // Apple-native crash/hang telemetry
#endif
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
