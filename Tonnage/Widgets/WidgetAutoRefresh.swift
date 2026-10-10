import Foundation
import CoreData
import SwiftData
import TonnageCore

/// Keeps the home-screen widget current after ANY save — not just ones made on TRAIN.
/// Watches SwiftData saves (watch syncs, restores, deletes, MOVE) and CloudKit imports
/// from other devices, coalescing bursts into one refresh.
@MainActor
final class WidgetAutoRefresh {
    static let shared = WidgetAutoRefresh()
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    func start(container: ModelContainer) {
        guard observers.isEmpty else { return }
        self.container = container
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, .NSPersistentStoreRemoteChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetAutoRefresh.shared.schedule() }
            })
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let context = container?.mainContext else { return }
            WidgetSync.refreshFromStore(context: context)
        }
    }
}
