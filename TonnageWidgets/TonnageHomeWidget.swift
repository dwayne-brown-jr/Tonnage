//
//  TonnageHomeWidget.swift
//  TonnageWidgets
//
//  Home-screen widget: current block / week / session + this week's tonnage. Reads
//  the shared `WidgetSnapshot` the app writes into the App Group; the app calls
//  `WidgetCenter.reloadAllTimelines()` whenever that snapshot changes.
//

import WidgetKit
import SwiftUI
import TonnageCore

// MARK: - Timeline

struct TonnageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TonnageProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonnageEntry {
        TonnageEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonnageEntry) -> Void) {
        completion(TonnageEntry(date: .now, snapshot: WidgetSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonnageEntry>) -> Void) {
        let entry = TonnageEntry(date: .now, snapshot: WidgetSnapshot.read() ?? .placeholder)
        // The app drives refreshes via WidgetCenter on every change, so a single
        // entry with `.never` avoids redundant system reloads.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Widget

struct TonnageHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonnageHomeWidget", provider: TonnageProvider()) { entry in
            TonnageWidgetView(snapshot: entry.snapshot)
                .containerBackground(Color.surface, for: .widget)
        }
        .configurationDisplayName("Next Session")
        .description("Your current block, session, and this week's tonnage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct TonnageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .systemMedium: medium
        default:            small
        }
    }

    private var blockWeek: String {
        "BLOCK \(String(format: "%02d", snapshot.block)) · W\(snapshot.week)"
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(blockWeek)
                .font(DSFont.mono)
                .foregroundStyle(Color.accent)

            Spacer(minLength: 6)

            Text(snapshot.sessionName)
                .font(DSFont.display)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(snapshot.sessionFocus)
                .font(DSFont.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WidgetFormat.volume(snapshot.weekVolume))
                    .font(DSFont.numberXL)
                    .foregroundStyle(Color.accent)
                Text("LB")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("THIS WEEK")
                .font(.system(.caption2, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text(blockWeek)
                    .font(DSFont.mono)
                    .foregroundStyle(Color.accent)
                Spacer(minLength: 8)
                Text(snapshot.sessionName)
                    .font(DSFont.displayXL)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(snapshot.sessionFocus)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: DS.Spacing.sm) {
                stat(WidgetFormat.int(snapshot.weekSets), "SETS", accent: false)
                stat(WidgetFormat.int(snapshot.weekReps), "REPS", accent: false)
                stat(WidgetFormat.volume(snapshot.weekVolume), "LB", accent: true)
            }
            .frame(width: 96)
        }
    }

    private func stat(_ value: String, _ label: String, accent: Bool) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(DSFont.number)
                .foregroundStyle(accent ? Color.accent : Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Formatting

private enum WidgetFormat {
    static func int(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
    static func volume(_ value: Double) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TonnageHomeWidget()
} timeline: {
    TonnageEntry(date: .now, snapshot: .init(block: 2, week: 1, sessionName: "Upper A",
        sessionFocus: "Push focus", weekSets: 14, weekReps: 96, weekVolume: 12480))
}

#Preview("Medium", as: .systemMedium) {
    TonnageHomeWidget()
} timeline: {
    TonnageEntry(date: .now, snapshot: .init(block: 2, week: 1, sessionName: "Lower A",
        sessionFocus: "Squat focus", weekSets: 14, weekReps: 96, weekVolume: 12480))
}
