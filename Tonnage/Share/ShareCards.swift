import SwiftUI
import UIKit
import TonnageCore

/// Renders a SwiftUI card to a shareable image (Phase-1 "social": no backend — just a
/// polished card the user sends via the normal iOS share sheet instead of a screenshot).
enum ShareCardRenderer {
    @MainActor
    static func image<V: View>(_ card: V, width: CGFloat = 380) -> UIImage? {
        // Force dark — ImageRenderer renders without the app's .preferredColorScheme, so
        // any adaptive color would otherwise resolve to its light variant.
        let renderer = ImageRenderer(content: card.frame(width: width).environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Wraps `UIActivityViewController` so a rendered card image can be shared via `.sheet`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a rendered image can drive `.sheet(item:)`.
struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Cards

/// A single finished session — "here's my workout."
struct WorkoutShareCard: View {
    let workout: LoggedWorkout

    private var lifts: [LoggedExercise] {
        workout.orderedExercises.filter { !$0.isCardio && $0.topSet != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONNAGE")
                    .font(.system(.caption, weight: .heavy).width(.condensed)).kerning(2)
                    .foregroundStyle(Color.accent)
                Spacer()
                Text(workout.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.textTertiary)
            }
            .padding(.bottom, 18)

            Text(workout.sessionName.isEmpty ? "Workout" : workout.sessionName)
                .font(.system(size: 36, weight: .heavy).width(.condensed))
                .foregroundStyle(Color.textPrimary)
            Text("BLOCK \(String(format: "%02d", workout.blockNumber)) · WEEK \(workout.weekNumber)")
                .font(.system(.caption, weight: .bold)).kerning(1)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 20)

            VStack(spacing: 11) {
                ForEach(lifts) { ex in
                    HStack(alignment: .firstTextBaseline) {
                        Text(ex.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.textPrimary).lineLimit(1)
                        Spacer(minLength: 8)
                        if let t = ex.topSet {
                            Text("\(CoachEngine.fmt(t.weight)) × \(t.reps)")
                                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
            }
            .padding(.bottom, 18)

            Rectangle().fill(Color.hairline).frame(height: 1)

            HStack {
                ShareStat(value: Int(workout.totalVolume).formatted(), label: "VOLUME · LB")
                Spacer()
                ShareStat(value: "\(workout.completedSetCount)", label: "SETS")
                Spacer()
                ShareStat(value: "\(lifts.count)", label: "LIFTS")
            }
            .padding(.top, 16)
        }
        .padding(28)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
        .padding(16)
        .background(Color.surface)
    }
}

/// A block check-in — "here's where I'm at."
struct BlockShareCard: View {
    let block: Int
    let volume: Double
    let sets: Int
    let sessions: Int
    let prs: [PRMoment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONNAGE")
                    .font(.system(.caption, weight: .heavy).width(.condensed)).kerning(2)
                    .foregroundStyle(Color.accent)
                Spacer()
                Text("CHECK-IN")
                    .font(.system(.caption2, weight: .bold)).kerning(1).foregroundStyle(Color.textTertiary)
            }
            .padding(.bottom, 16)

            Text("BLOCK \(String(format: "%02d", block))")
                .font(.system(size: 40, weight: .heavy).width(.condensed))
                .foregroundStyle(Color.textPrimary)
                .padding(.bottom, 20)

            HStack {
                ShareStat(value: Int(volume).formatted(), label: "VOLUME · LB")
                Spacer()
                ShareStat(value: "\(sets)", label: "SETS")
                Spacer()
                ShareStat(value: "\(sessions)", label: "SESSIONS")
            }
            .padding(.bottom, prs.isEmpty ? 0 : 20)

            if !prs.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.bottom, 14)
                Text("RECENT PRs")
                    .font(.system(.caption2, weight: .bold)).kerning(1).foregroundStyle(Color.textTertiary)
                    .padding(.bottom, 8)
                VStack(spacing: 9) {
                    ForEach(Array(prs.prefix(3))) { pr in
                        HStack(alignment: .firstTextBaseline) {
                            Text(pr.exerciseName)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.textPrimary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("e1RM \(CoachEngine.fmt(pr.estimatedOneRM.rounded()))")
                                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
            }
        }
        .padding(28)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
        .padding(16)
        .background(Color.surface)
    }
}

/// A week recap — "here's my week."
struct WeekShareCard: View {
    let block: Int
    let summary: Analytics.WeekSummary
    let prs: [PRMoment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONNAGE")
                    .font(.system(.caption, weight: .heavy).width(.condensed)).kerning(2)
                    .foregroundStyle(Color.accent)
                Spacer()
                Text("WEEKLY RECAP")
                    .font(.system(.caption2, weight: .bold)).kerning(1).foregroundStyle(Color.textTertiary)
            }
            .padding(.bottom, 16)

            Text("WEEK \(String(format: "%02d", summary.week))")
                .font(.system(size: 40, weight: .heavy).width(.condensed))
                .foregroundStyle(Color.textPrimary)
            Text("BLOCK \(String(format: "%02d", block))")
                .font(.system(.caption, weight: .bold)).kerning(1)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 20)

            HStack {
                ShareStat(value: "\(summary.sessions)", label: "SESSIONS")
                Spacer()
                ShareStat(value: "\(summary.sets)", label: "HARD SETS")
                Spacer()
                ShareStat(value: Int(summary.volume).formatted(), label: "VOLUME · LB")
            }
            .padding(.bottom, prs.isEmpty ? 0 : 20)

            if !prs.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.bottom, 14)
                Text("PRs THIS WEEK")
                    .font(.system(.caption2, weight: .bold)).kerning(1).foregroundStyle(Color.textTertiary)
                    .padding(.bottom, 8)
                VStack(spacing: 9) {
                    ForEach(Array(prs.prefix(3))) { pr in
                        HStack(alignment: .firstTextBaseline) {
                            Text(pr.exerciseName)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.textPrimary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("e1RM \(CoachEngine.fmt(pr.estimatedOneRM.rounded()))")
                                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
            }
        }
        .padding(28)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
        .padding(16)
        .background(Color.surface)
    }
}

/// A single cardio / active-rest session — "here's my move." Mirrors WorkoutShareCard.
struct ActivityShareCard: View {
    let activity: Activity

    private var stats: [(value: String, label: String)] {
        var s: [(value: String, label: String)] = [(durationText, "DURATION")]
        if let d = activity.distanceMiles, d > 0 { s.append((CoachEngine.fmt(d), "DISTANCE · MI")) }
        if let c = activity.activeCalories, c > 0 { s.append(("\(c)", "ACTIVE CAL")) }
        if s.count < 3, let f = activity.flights, f > 0 { s.append(("\(f)", "FLIGHTS")) }
        if s.count < 3, let p = paceText { s.append((p, "PACE · /MI")) }
        return Array(s.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONNAGE")
                    .font(.system(.caption, weight: .heavy).width(.condensed)).kerning(2)
                    .foregroundStyle(Color.accent)
                Spacer()
                Text(activity.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.textTertiary)
            }
            .padding(.bottom, 18)

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accent.opacity(0.15))
                    Image(systemName: activity.kind.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accent)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.system(size: 30, weight: .heavy).width(.condensed))
                        .foregroundStyle(Color.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    Text(activity.kind.label.uppercased())
                        .font(.system(.caption, weight: .bold)).kerning(1)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.bottom, 20)

            Rectangle().fill(Color.hairline).frame(height: 1)

            HStack {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Spacer() }
                    ShareStat(value: s.value, label: s.label)
                }
            }
            .padding(.top, 16)
        }
        .padding(28)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
        .padding(16)
        .background(Color.surface)
    }

    private var durationText: String {
        let m = activity.durationMinutes
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    private var paceText: String? {
        guard let d = activity.distanceMiles, d > 0, activity.durationMinutes > 0 else { return nil }
        let secPerMile = (Double(activity.durationMinutes) * 60) / d
        return String(format: "%d'%02d\"", Int(secPerMile) / 60, Int(secPerMile) % 60)
    }
}

private struct ShareStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .bold)).kerning(0.5)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

#Preview("Share cards") {
    ScrollView {
        VStack {
            BlockShareCard(block: 2, volume: 84210, sets: 142, sessions: 11, prs: [])
        }
    }
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
