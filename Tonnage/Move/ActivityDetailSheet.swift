import SwiftUI
import TonnageCore

/// Read-only detail for a logged MOVE activity — tap a row to open it. Shows what Tonnage
/// actually stores (duration, distance, derived pace, flights, notes). Rich Apple-only stats
/// (heart rate, elevation, per-mile splits) live in the Fitness app and aren't duplicated here.
struct ActivityDetailSheet: View {
    let activity: Activity
    @Environment(\.dismiss) private var dismiss

    /// The import path stamps this exact string into `detail`; treat it as provenance, not notes.
    private var isImported: Bool { activity.detail == "Imported from Apple Health" }
    private var hasNotes: Bool {
        !activity.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isImported
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        hero
                        metricsGrid
                        if isImported { importedBadge }
                        if hasNotes { notesCard }
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).tint(.accent)
                }
            }
        }
        .tint(.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle().fill(Color.accent.opacity(0.15))
                Image(systemName: activity.kind.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(DSFont.title)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(dateLine)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                Text(timeRange)
                    .font(DSFont.numberSm)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
            stat("Duration", durationText, "")
            if let d = activity.distanceMiles, d > 0 {
                stat("Distance", CoachEngine.fmt(d), "mi")
                if let pace = paceText { stat("Avg Pace", pace, "/mi") }
            }
            if let f = activity.flights, f > 0 {
                stat("Flights", "\(f)", "")
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label.uppercased())
                .font(.system(.caption2, weight: .semibold).width(.condensed))
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DSFont.numberXL)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(DSFont.numberSm)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }

    private var importedBadge: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text("Imported from Apple Health. Open the Fitness app for heart rate, elevation, and splits.")
                .font(.system(.caption2))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Notes").dsLabel()
            Text(activity.detail)
                .font(DSFont.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: Derived

    private var dateLine: String {
        activity.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// Apple-style "1:44 PM – 2:55 PM", treating the stored date as the start.
    private var timeRange: String {
        let start = activity.date.formatted(.dateTime.hour().minute())
        guard activity.durationMinutes > 0 else { return start }
        let end = activity.date.addingTimeInterval(Double(activity.durationMinutes) * 60)
        return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
    }

    private var durationText: String {
        let m = activity.durationMinutes
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Min/mile in Apple's mm'ss"/mi form. Nil when there's no distance to divide by.
    private var paceText: String? {
        guard let d = activity.distanceMiles, d > 0, activity.durationMinutes > 0 else { return nil }
        let secPerMile = (Double(activity.durationMinutes) * 60) / d
        return String(format: "%d'%02d\"", Int(secPerMile) / 60, Int(secPerMile) % 60)
    }
}

#Preview("Activity detail") {
    ActivityDetailSheet(activity: Activity(
        name: "Outdoor Walk", kind: .walk, durationMinutes: 69,
        distanceMiles: 3.69, detail: "Imported from Apple Health",
        date: .now.addingTimeInterval(-4200)))
        .preferredColorScheme(.dark)
}
