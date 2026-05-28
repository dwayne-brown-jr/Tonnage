//
//  TonnageWatchComplication.swift
//  TonnageWatchWidgets
//
//  Watch-face complication: shows the current block + week and acts as a quick
//  launch into the app. Reads the shared `WidgetSnapshot` the watch app writes into
//  the App Group; totals aren't tracked on the wrist, so it stays block/week.
//

import WidgetKit
import SwiftUI
import TonnageCore

// MARK: - Timeline

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(WatchComplicationEntry(date: .now, snapshot: WidgetSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let entry = WatchComplicationEntry(date: .now, snapshot: WidgetSnapshot.read() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Widget

struct TonnageWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonnageWatchComplication", provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Tonnage")
        .description("Your current block and week — tap to train.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Views

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var blockStr: String { String(format: "%02d", snapshot.block) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Block \(snapshot.block) · Wk \(snapshot.week)", systemImage: "dumbbell.fill")

        case .accessoryCorner:
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .widgetLabel("B\(snapshot.block) · W\(snapshot.week)")

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("TONNAGE")
                        .font(.system(size: 11, weight: .heavy))
                        .widgetAccentable()
                    Text("Block \(blockStr) · Week \(snapshot.week)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Tap to train")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

        default: // .accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 13, weight: .bold))
                        .widgetAccentable()
                    Text("W\(snapshot.week)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }
}
