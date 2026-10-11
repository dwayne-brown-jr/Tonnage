import SwiftUI
import TonnageCore

/// A full-width light band that scrolls the block's wins past ("BENCH PRESS +10 LB ·
/// BACK SQUAT +20 LB · 4 PRS"). Poster energy for the DATA tab: dark condensed type on
/// the light band, loops seamlessly, and holds still when Reduce Motion is on.
struct TickerBand: View {
    let items: [String]
    /// Points per second.
    var speed: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runWidth: CGFloat = 0

    var body: some View {
        // The band is a fixed-height strip; the scrolling text is laid over it, so its
        // (very wide) natural width never reaches the page's layout.
        Color.textPrimary
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .overlay(alignment: .leading) {
                if reduceMotion {
                    run.padding(.leading, DS.Spacing.screen)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let offset = runWidth > 0
                            ? -CGFloat(t).truncatingRemainder(dividingBy: runWidth / speed) * speed : 0
                        HStack(spacing: 0) { run; run }
                            .offset(x: offset)
                    }
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(items.joined(separator: ", ").lowercased())
    }

    /// One copy of the items, each followed by a separator, measured so the loop wraps
    /// exactly where the second copy starts.
    private var run: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: 15, weight: .heavy).width(.condensed))
                    .kerning(0.8)
                    .foregroundStyle(Color.surface)
                Text("  ·  ")
                    .font(.system(size: 15, weight: .heavy).width(.condensed))
                    .foregroundStyle(Color.accent)
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { runWidth = $0 }
    }
}

#Preview("Ticker") {
    TickerBand(items: ["BACK SQUAT +20 LB", "BENCH PRESS +10 LB", "ROMANIAN DEADLIFT +10 LB", "4 PRS", "12/20 SESSIONS"])
        .padding(.vertical)
        .background(Color.surface)
        .preferredColorScheme(.dark)
}
