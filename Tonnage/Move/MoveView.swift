import SwiftUI
import SwiftData
import TonnageCore

/// MOVE: quick-add active-rest / cardio logging + recent history.
struct MoveView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]

    @State private var entryKind: ActivityKind?

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
        .preferredColorScheme(.dark)
}
