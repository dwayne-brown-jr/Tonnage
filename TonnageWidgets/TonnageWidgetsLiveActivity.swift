//
//  TonnageWidgetsLiveActivity.swift
//  TonnageWidgets
//
//  Rest-timer Live Activity — Lock Screen banner + Dynamic Island.
//  Renders the shared `RestTimerAttributes` payload the app pushes. The countdown
//  is driven by `Text(timerInterval:)` / `ProgressView(timerInterval:)`, so the OS
//  ticks it live without the app updating every second.
//

import ActivityKit
import WidgetKit
import SwiftUI
import TonnageCore

struct TonnageWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenRestView(state: context.state)
                .activityBackgroundTint(Color.surface)
                .activitySystemActionForegroundColor(Color.accent)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RESTING")
                            .font(DSFont.caption)
                            .textCase(.uppercase)
                            .kerning(0.9)
                            .foregroundStyle(Color.accent)
                        Text(context.state.exerciseName)
                            .font(DSFont.title)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.range, countsDown: true, showsHours: false)
                        .font(DSFont.numberXL)
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: 86, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(Color.accent)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accent)
            } compactTrailing: {
                Text(timerInterval: context.state.range, countsDown: true, showsHours: false)
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accent)
            }
            .keylineTint(Color.accent)
        }
    }
}

// MARK: - Lock Screen / banner

private struct LockScreenRestView: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accent.opacity(0.16))
                    Image(systemName: "timer")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RESTING")
                        .font(DSFont.caption)
                        .textCase(.uppercase)
                        .kerning(0.9)
                        .foregroundStyle(Color.accent)
                    Text(state.exerciseName)
                        .font(DSFont.title)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(timerInterval: state.range, countsDown: true, showsHours: false)
                    .font(DSFont.numberXL)
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
                    .frame(minWidth: 84, alignment: .trailing)
            }

            ProgressView(timerInterval: state.range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Color.accent)
        }
        .padding(16)
    }
}

// MARK: - Timer range helper

private extension RestTimerAttributes.ContentState {
    /// Full rest window `[start, end]` so the OS-driven countdown + progress bar
    /// span the whole interval rather than just "now → end".
    var range: ClosedRange<Date> {
        let start = endDate.addingTimeInterval(-Double(totalSeconds))
        // Guard against a zero/negative window if totalSeconds is ever 0.
        return start < endDate ? start...endDate : endDate.addingTimeInterval(-1)...endDate
    }
}
