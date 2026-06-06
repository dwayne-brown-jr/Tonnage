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
                Task {
                    let n = await health.importExternalWorkouts(into: context)
                    importMessage = n > 0
                        ? "Imported \(n) workout\(n == 1 ? "" : "s") from Apple Health."
                        : "No new workouts to import."
                    importing = false
                    Haptics.success()
                }
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

            Text(importMessage ?? "Pulls cardio (walks, runs, rides, stairs) from Apple Fitness and other apps. Strength workouts stay in TRAIN.")
                .font(.system(.caption2))
                .foregroundStyle(Color.textTertiary)
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
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(activity)
                                try? context.save()
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
