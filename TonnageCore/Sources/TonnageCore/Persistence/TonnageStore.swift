import Foundation
import SwiftData

/// Central SwiftData setup. Both the iOS and watchOS apps build their container
/// from here so they share one schema definition.
public enum TonnageStore {

    /// Every persisted model in the app. Keep in sync when adding `@Model` types.
    public static let schema = Schema([
        Program.self,
        SessionTemplate.self,
        ExerciseTemplate.self,
        LoggedWorkout.self,
        LoggedExercise.self,
        LoggedSet.self,
        Activity.self,
        CoachChatMessage.self,
        BodyMeasurement.self,
        ProgressPhoto.self
    ])

    /// CloudKit container that mirrors the private database when sync is enabled.
    public static let cloudKitContainerID = "iCloud.com.dwayne.tonnage"

    /// Builds the shared container and seeds Block 01 on first launch.
    /// - Parameters:
    ///   - inMemory: use a throwaway store (previews / tests). Never uses CloudKit.
    ///   - cloudKit: mirror to the private CloudKit database. Enabled on iPhone (which
    ///     has the iCloud entitlement); the watch + previews stay local for now.
    @MainActor
    public static func makeContainer(inMemory: Bool = false, cloudKit: Bool = false) -> ModelContainer {
        func build(cloudKit: Bool) throws -> ModelContainer {
            let db: ModelConfiguration.CloudKitDatabase =
                (inMemory || !cloudKit) ? .none : .private(cloudKitContainerID)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: db)
            return try ModelContainer(for: schema, configurations: configuration)
        }
        do {
            let container = try build(cloudKit: cloudKit)
            seedIfNeeded(container.mainContext)
            return container
        } catch {
            // A CloudKit/iCloud init failure must never brick launch — fall back to a
            // purely local store so the app still works (just without cloud sync).
            if cloudKit, let local = try? build(cloudKit: false) {
                seedIfNeeded(local.mainContext)
                return local
            }
            // Local store failed too — e.g. a schema change the lightweight migrator can't
            // handle. Rather than crash on launch (which would silently take the watch app
            // and its sync down), drop to a throwaway in-memory store so the app still runs.
            // On the watch that's fine — the phone is the source of truth and re-pushes state.
            if let memory = try? ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ) {
                seedIfNeeded(memory.mainContext)
                return memory
            }
            fatalError("Failed to create Tonnage ModelContainer: \(error)")
        }
    }
}
