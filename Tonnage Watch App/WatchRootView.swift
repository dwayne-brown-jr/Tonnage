import SwiftUI
import SwiftData
import TonnageCore

/// Watch home: pick the week + today's session, then run the workout from the wrist.
struct WatchRootView: View {
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @AppStorage("watch.week") private var week = 1
    @Environment(WatchConnectivityClient.self) private var conn

    var body: some View {
        NavigationStack {
            List {
                syncRow
                if let program = programs.first {
                    Picker("Week", selection: $week) {
                        ForEach(1...5, id: \.self) { w in Text("Week \(w)").tag(w) }
                    }
                    Section("Sessions") {
                        ForEach(program.orderedSessions) { session in
                            let logged = conn.loggedWorkout(week: week, session: session.name)
                            NavigationLink {
                                WatchSessionView(session: session, week: week, existing: logged)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session.name).font(.headline)
                                        Text(session.subtitle).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    sessionBadge(logged)
                                }
                            }
                        }
                    }
                } else {
                    Text("No program synced").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Tonnage")
        }
        .tint(.accent)
        .onAppear { WatchWidgetSync.refresh() }
        .onChange(of: week) { WatchWidgetSync.refresh() }
    }

    /// Tiny "phone sync at a glance" indicator — a dot for live reachability + the time
    /// since the last application-context arrived from the phone. Diagnoses why a
    /// session badge might look stale without guessing.
    private var syncRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(conn.reachable ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(syncStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phone sync: \(syncStatus), \(conn.reachable ? "reachable" : "not reachable")")
    }

    private var syncStatus: String {
        if let last = conn.lastSyncedAt { return "Synced \(Self.relative(last))" }
        return conn.loggedWorkouts.isEmpty ? "Awaiting sync from phone" : "Synced earlier"
    }

    /// Short relative string — kept compact for the watch screen ("just now", "2m ago").
    private static func relative(_ date: Date) -> String {
        let delta = max(0, Date().timeIntervalSince(date))
        if delta < 5    { return "just now" }
        if delta < 60   { return "\(Int(delta))s ago" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86_400))d ago"
    }

    @ViewBuilder private func sessionBadge(_ logged: WorkoutPayload?) -> some View {
        if let logged {
            if logged.isFullyLogged {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if logged.anyCompleted {
                Image(systemName: "circle.bottomhalf.filled").foregroundStyle(Color.accent)
            }
        }
    }
}

#Preview {
    WatchRootView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(WatchConnectivityClient.shared)
}
