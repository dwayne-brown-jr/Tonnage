import SwiftUI
import SwiftData
import Charts
import UIKit
import TonnageCore

/// DATA: block summary, adherence + PR feed, weekly volume, and per-exercise top-set
/// progression. PRs span all blocks (lifetime); everything else is block-scoped.
struct DataView: View {
    @Query(sort: \LoggedWorkout.weekNumber) private var workouts: [LoggedWorkout]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Environment(HealthKitManager.self) private var health
    @AppStorage("currentBlock") private var currentBlock = 1

    @State private var selectedExercise: String?
    @State private var scrubWeek: Int?
    @State private var showWeightEntry = false
    @State private var shareItem: ShareImageItem?

    /// DATA is scoped to the active block so volume/progression don't mix mesocycles.
    private var scoped: [LoggedWorkout] { workouts.filter { $0.blockNumber == currentBlock } }
    private var names: [String] { Analytics.loggedExerciseNames(scoped) }
    private var volume: [Analytics.WeekVolume] { Analytics.weeklyVolume(scoped) }
    private var hasData: Bool { Analytics.totalSets(scoped) > 0 }

    private var sessionsPerWeek: Int { programs.first?.orderedSessions.count ?? 0 }
    private var adherence: BlockAdherence {
        AdherenceEngine.computeBlock(workouts: workouts, blockNumber: currentBlock,
                                     sessionsPerWeek: sessionsPerWeek)
    }
    /// PRs are tracked across the whole training history, not just the current block.
    private var recentPRs: [PRMoment] { PersonalRecords.recentPRs(in: workouts, limit: 5) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {
                        if hasData {
                            summary
                            if sessionsPerWeek > 0 { adherenceCard }
                            if !recentPRs.isEmpty { prsCard }
                            volumeCard
                            progressionCard
                            bodyweightCard
                        } else {
                            EmptyStateView(systemImage: "chart.line.uptrend.xyaxis",
                                           title: "No Data Yet",
                                           message: "Log a few sets in TRAIN and your progression shows up here.")
                                .frame(minHeight: 360)
                        }
                        bodyNavCard
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.accent)
        .onAppear { syncSelection() }
        .onChange(of: names) { _, _ in syncSelection() }
        .task { if health.hasRequested { await health.refresh() } }
        .sheet(isPresented: $showWeightEntry) {
            WeightEntrySheet { pounds in Task { await health.saveBodyMass(pounds: pounds) } }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.image]) }
    }

    // MARK: Sharing

    private var latestLiftWorkout: LoggedWorkout? {
        workouts.filter { $0.dayType == .lift && $0.completedSetCount > 0 }
            .max(by: { $0.date < $1.date })
    }

    private var shareMenu: some View {
        Menu {
            if latestLiftWorkout != nil {
                Button { shareLatestWorkout() } label: { Label("Share Latest Workout", systemImage: "dumbbell.fill") }
            }
            if hasData {
                Button { shareBlockSummary() } label: { Label("Share Block Check-In", systemImage: "chart.bar.fill") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.surfaceElevated2))
        }
        .disabled(latestLiftWorkout == nil && !hasData)
    }

    @MainActor private func shareLatestWorkout() {
        guard let w = latestLiftWorkout,
              let img = ShareCardRenderer.image(WorkoutShareCard(workout: w)) else { return }
        Haptics.impact(.light)
        shareItem = ShareImageItem(image: img)
    }

    @MainActor private func shareBlockSummary() {
        let card = BlockShareCard(block: currentBlock,
                                  volume: Analytics.totalVolume(scoped),
                                  sets: Analytics.totalSets(scoped),
                                  sessions: Analytics.sessionsLogged(scoped),
                                  prs: recentPRs)
        guard let img = ShareCardRenderer.image(card) else { return }
        Haptics.impact(.light)
        shareItem = ShareImageItem(image: img)
    }

    private func syncSelection() {
        if selectedExercise == nil || !(names.contains(selectedExercise ?? "")) {
            selectedExercise = names.first
        }
    }

    // MARK: Header

    private var header: some View { TonnageHeader("DATA") { shareMenu } }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: DS.Spacing.sm) {
            stat(value: Analytics.totalVolume(scoped).formatted(.number.precision(.fractionLength(0))),
                 label: "Block \(String(format: "%02d", currentBlock)) · lb", accent: true)
            divider
            stat(value: "\(Analytics.totalSets(scoped))", label: "Sets", accent: false)
            divider
            stat(value: "\(Analytics.sessionsLogged(scoped))", label: "Sessions", accent: false)
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func stat(value: String, label: String, accent: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DSFont.numberXL).monospacedDigit()
                .foregroundStyle(accent ? Color.accent : Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.system(.caption2, weight: .semibold)).textCase(.uppercase).kerning(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(Color.hairline).frame(width: DS.Stroke.hairline, height: 32) }

    // MARK: Adherence

    private var adherenceCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Adherence").dsLabel()
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(adherence.sessionsCompleted)")
                        .font(DSFont.number).monospacedDigit().foregroundStyle(Color.accent)
                    Text("/ \(adherence.sessionsPlanned)")
                        .font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.textTertiary)
                }
            }
            progressBar(pct: adherence.completionPct)
            HStack(spacing: DS.Spacing.xs) {
                Text("\(adherence.trainingDays)")
                    .font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.textSecondary)
                Text("days lifted this block")
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                Spacer(minLength: 0)
                Text("\(Int((adherence.completionPct * 100).rounded()))%")
                    .font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.textPrimary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func progressBar(pct: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceElevated2)
                Capsule().fill(Color.accent)
                    .frame(width: max(0, geo.size.width * min(1, max(0, pct))))
            }
        }
        .frame(height: 6)
    }

    // MARK: PR moments

    private var prsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("PR Moments").dsLabel()
                Spacer()
                Text("lifetime").font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(recentPRs.enumerated()), id: \.element.id) { i, pr in
                    prRow(pr)
                    if i < recentPRs.count - 1 {
                        Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline)
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func prRow(_ pr: PRMoment) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.exerciseName)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: DS.Spacing.xs) {
                    Text("\(CoachEngine.fmt(pr.weight)) × \(pr.reps)")
                        .font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.textSecondary)
                    Text("·").font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                    Text("e1RM \(CoachEngine.fmt(pr.estimatedOneRM.rounded()))")
                        .font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.accent)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("W\(pr.weekNumber)")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(pr.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: Weekly volume

    private var volumeCard: some View {
        chartCard(title: "Weekly Volume", subtitle: "Total tonnage per week") {
            Chart(volume) { item in
                // Categorical x ("W1"…"W5") gives BarMark a band to size against.
                BarMark(
                    x: .value("Week", "W\(item.week)"),
                    y: .value("Volume", item.volume),
                    width: .ratio(0.6)
                )
                .foregroundStyle(Color.accent.gradient)
                .cornerRadius(DS.Radius.sm)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .chartYAxis { volumeAxis }
            .frame(height: 180)
        }
    }

    // MARK: Progression

    private var progressionCard: some View {
        let series = selectedExercise.map { Analytics.topSetSeries(for: $0, in: scoped) } ?? []
        let highlight = series.first { $0.week == scrubWeek } ?? series.last

        return chartCard(title: "Top-Set Progression", subtitle: nil) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                exercisePicker
                if let highlight {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text("W\(highlight.week)").font(DSFont.numberSm).foregroundStyle(Color.textTertiary)
                        Text("\(CoachEngine.fmt(highlight.weight)) × \(highlight.reps)")
                            .font(DSFont.number).foregroundStyle(Color.textPrimary)
                        Text("e1RM \(CoachEngine.fmt(highlight.estimatedOneRepMax.rounded()))")
                            .font(DSFont.numberSm).foregroundStyle(Color.accent)
                    }
                }
                Chart(series) { point in
                    AreaMark(x: .value("Week", point.week), y: .value("Top set", point.weight))
                        .foregroundStyle(.linearGradient(colors: [Color.accent.opacity(0.35), Color.accent.opacity(0.02)],
                                                          startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Week", point.week), y: .value("Top set", point.weight))
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", point.week), y: .value("Top set", point.weight))
                        .foregroundStyle(Color.accent)
                        .symbolSize(scrubWeek == point.week ? 160 : 70)
                    if let highlight, scrubWeek == highlight.week {
                        RuleMark(x: .value("Week", highlight.week))
                            .foregroundStyle(Color.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: 0.5...5.5)
                .chartXSelection(value: $scrubWeek)
                .chartXAxis { weekAxis }
                .chartYAxis { weightAxis }
                .frame(height: 180)
            }
        }
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(names, id: \.self) { name in
                Button(name) { selectedExercise = name; scrubWeek = nil }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(selectedExercise ?? "Select exercise")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bodyweight (HealthKit lands in M5)

    @ViewBuilder private var bodyweightCard: some View {
        chartCard(title: "Bodyweight", subtitle: "Recomp trend") {
            if !health.isAvailable {
                placeholder(icon: "heart.slash", text: "Apple Health isn't available on this device.")
            } else if !health.bodyweight.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    bodyweightChart
                    logWeightButton
                }
            } else if health.hasRequested {
                VStack(spacing: DS.Spacing.md) {
                    placeholder(icon: "scalemass", text: "No bodyweight in Health yet — log one to start the trend.")
                    logWeightButton
                }
            } else {
                VStack(spacing: DS.Spacing.md) {
                    placeholder(icon: "heart.text.square.fill",
                                text: "Connect Apple Health to track your recomp — strength up, weight steady.")
                    Button { Task { await health.requestAuthorization() } } label: {
                        Text("Connect Apple Health")
                            .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                            .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bodyweightChart: some View {
        Chart(health.bodyweight) { sample in
            AreaMark(x: .value("Date", sample.date), y: .value("lb", sample.pounds))
                .foregroundStyle(.linearGradient(colors: [Color.accent.opacity(0.3), Color.accent.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Date", sample.date), y: .value("lb", sample.pounds))
                .foregroundStyle(Color.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", sample.date), y: .value("lb", sample.pounds))
                .foregroundStyle(Color.accent).symbolSize(50)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
        .chartYAxis { weightAxis }
        .frame(height: 160)
    }

    private var logWeightButton: some View {
        Button { showWeightEntry = true } label: {
            Label("Log Weight", systemImage: "plus")
                .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.textTertiary)
            Text(text).font(DSFont.caption).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: Body measurements entry

    private var bodyNavCard: some View {
        NavigationLink {
            BodyView()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Measurements")
                        .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Text("Waist, arms, body fat & progress photos")
                        .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: Chart chrome

    private func chartCard<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsLabel()
                if let subtitle {
                    Text(subtitle).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                }
            }
            content()
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private var weekAxis: some AxisContent {
        AxisMarks(values: Array(1...5)) { value in
            AxisGridLine().foregroundStyle(Color.hairline)
            AxisValueLabel {
                if let w = value.as(Int.self) {
                    Text("W\(w)").font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private var volumeAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color.hairline)
            AxisValueLabel().foregroundStyle(Color.textTertiary)
        }
    }

    private var weightAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color.hairline)
            AxisValueLabel().foregroundStyle(Color.textTertiary)
        }
    }
}

/// Quick bodyweight entry → writes to Apple Health.
private struct WeightEntrySheet: View {
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pounds: Double = 180

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                VStack(spacing: DS.Spacing.lg) {
                    Text("Today's Weight").dsLabel()
                    StepperField(value: $pounds, step: 0.5, range: 50...600, unit: "lb", isDecimal: true)
                        .scaleEffect(1.2)
                    Spacer()
                }
                .padding(DS.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(pounds); dismiss() }
                        .fontWeight(.bold).foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.height(260)])
        .preferredColorScheme(.dark)
    }
}

#Preview("Data") {
    DataView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
