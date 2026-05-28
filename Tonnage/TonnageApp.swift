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
        container = TonnageStore.makeContainer(cloudKit: true)   // mirror to private iCloud
        PhoneConnectivity.shared.activate(container: container)   // receive watch syncs
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
