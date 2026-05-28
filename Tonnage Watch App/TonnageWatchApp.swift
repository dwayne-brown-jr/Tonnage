import SwiftUI
import SwiftData
import TonnageCore

@main
struct TonnageWatchApp: App {
    let container: ModelContainer

    init() {
        container = TonnageStore.makeContainer()
        WatchConnectivityClient.shared.activate()   // sync finished workouts to the phone
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(WatchConnectivityClient.shared)
        }
        .modelContainer(container)
    }
}
