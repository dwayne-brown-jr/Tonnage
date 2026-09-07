import SwiftUI
import SwiftData
import TonnageCore

/// MOVE: quick-add active-rest / cardio logging + recent history.
struct MoveView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]

    @State private var entryKind: ActivityKind?
    @State private var importing = false
    @State private var importMessage: String?
    /// Set when an import came back empty, revealing the force-re-import escape hatch.
    @State private var importCameBackEmpty = false
    /// Set when Health returned no workouts at all — read access is almost certainly off.
    @State private var importBlocked = false
    @State private var pendingDelete: Activity?
    @State private var selectedActivity: Activity?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let quickKinds: [ActivityKind] = [
        .walk, .weightedVestWalk, .stadiumStairs, .stairMaster, .bike, .sport, .mobility, .recovery, .custom
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        quickAdd
                        if health.hasRequested { healthImport }
                        recent
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $entryKind) { kind in
                ActivityEntrySheet(kind: kind)
            }
            .sheet(item: $selectedActivity) { activity in
                ActivityDetailSheet(activity: activity)
            }
            .confirmationDialog("Delete this activity?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                presenting: pendingDelete) { activity in
                Button("Delete", role: .destructive) {
                    context.delete(activity); context.saveOrReport(); Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(.accent)
    }

    private var header: some View { TonnageHeader("MOVE") }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Quick Add").dsLabel()
            LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                ForEach(quickKinds) { kind in
                    Button {
                        Haptics.selection()
                        entryKind = kind
                    } label: {
                        VStack(spacing: DS.Spacing.sm) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.textSecondary)
                                .frame(height: 26)
                            Text(kind.label)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var healthImport: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                guard !importing else { return }
                importing = true
                importMessage = nil
                Task { await runImport() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if importing {
                        ProgressView().controlSize(.small).tint(Color.textSecondary)
                    } else {
                        Image(systemName: "arrow.down.heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                    Text("Import from Apple Health")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
                )
            }
            .buttonStyle(.plain)
            .disabled(importing)

            if let importMessage {
                // A result has to look different from the helper text it replaces — the old
                // version swapped one dim caption for another, so a finished import was
                // indistinguishable from nothing having happened.
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Image(systemName: importBlocked ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(importBlocked ? Color.danger : Color.success)
                    Text(importMessage)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .transition(.opacity)
            } else {
                Text("Pulls cardio (walks, runs, rides, stairs) from Apple Fitness and other apps. Strength workouts stay in TRAIN.")
                    .font(.system(.caption2))
                    .foregroundStyle(Color.textTertiary)
            }

            if importCameBackEmpty && !importing {
                Button {
                    Task { await runImport(forgettingSeen: true) }
                } label: {
                    Text("Nothing showing up? Re-import everything")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    /// Runs the import and reports what actually happened. `forgettingSeen` clears the
    /// imported-UUID memory first, which is the recovery path for anyone whose list was
    /// poisoned by the older build that marked failed saves as seen.
    private func runImport(forgettingSeen: Bool = false) async {
        let outcome = await health.importExternalWorkouts(into: context, forgettingSeen: forgettingSeen)
        withAnimation(DS.spring) {
            switch outcome {
            case .imported(let n):
                importMessage = "Imported \(n) workout\(n == 1 ? "" : "s") from Apple Health."
                importCameBackEmpty = false
                importBlocked = false
                Haptics.success()
            case .nothingNew:
                importMessage = forgettingSeen
                    ? "Still nothing new — Apple Health has no cardio Tonnage can add."
                    : "No new cardio found in Apple Health."
                importCameBackEmpty = true
                importBlocked = false
                Haptics.warning()
            case .noWorkoutsVisible:
                importMessage = "Tonnage can't read workouts from Apple Health. Turn on Workouts in Settings › Health › Data Access & Devices › Tonnage."
                importCameBackEmpty = false
                importBlocked = true
                Haptics.warning()
            case .unavailable:
                importMessage = "Couldn't reach Apple Health. Try again in a moment."
                importCameBackEmpty = false
                importBlocked = true
                Haptics.warning()
            }
            importing = false
        }
    }

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Recent").dsLabel()
            if activities.isEmpty {
                EmptyStateView(systemImage: "figure.walk.motion",
                               title: "Nothing Logged Yet",
                               message: "Tap a card above to log a walk, stairs, or recovery work.")
                    .frame(minHeight: 220)
            } else {
                ForEach(activities) { activity in
                    ActivityRow(activity: activity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.selection()
                            selectedActivity = activity
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens activity details")
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = activity
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: activity.kind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(activity.date.formatted(.dateTime.weekday().month().day().hour().minute()))
                    .font(.system(.caption2))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
            Text(metricsSummary)
                .font(DSFont.numberSm)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var metricsSummary: String {
        var parts: [String] = []
        if let d = activity.distanceMiles, d > 0 { parts.append("\(CoachEngine.fmt(d)) mi") }
        if let f = activity.flights, f > 0 { parts.append("\(f) fl") }
        if activity.durationMinutes > 0 { parts.append("\(activity.durationMinutes) min") }
        return parts.joined(separator: " · ")
    }
}

#Preview("Move") {
    MoveView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
