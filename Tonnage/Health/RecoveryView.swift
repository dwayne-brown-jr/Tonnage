import SwiftUI
import SwiftData
import Charts
import TonnageCore

/// The "Recovery" detail screen (tapped from the Readiness card on TRAIN): today's
/// readiness + its drivers, plain-language insights from the trends, then trend charts
/// for Readiness, HRV, resting HR, and sleep over the last two weeks. HealthKit-derived.
struct RecoveryView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \LoggedWorkout.weekNumber) private var workouts: [LoggedWorkout]
    @AppStorage("currentBlock") private var currentBlock = 1
    @AppStorage("train.week") private var trainWeek = 1
    @State private var series = RecoverySeries()
    @State private var sleepStages: SleepStages?
    @State private var loaded = false
    @State private var connecting = false

    private var readiness: Readiness { health.currentReadiness() }

    // MARK: Insights (trend storytelling + advisory deload)

    private var scopedWorkouts: [LoggedWorkout] { workouts.filter { $0.blockNumber == currentBlock } }

    private var insights: [TrainingInsight] {
        let lifts = Analytics.loggedExerciseNames(scopedWorkouts)
            .filter { ExerciseLibrary.isCompound($0) }
            .map { name in
                InsightEngine.Inputs.Lift(
                    name: name,
                    e1rm: Analytics.topSetSeries(for: name, in: scopedWorkouts).map(\.estimatedOneRepMax))
            }
        return InsightEngine.generate(.init(
            readiness: readinessTrend.map(\.value),
            hrv: series.hrv.map(\.value),
            lifts: lifts,
            currentWeek: trainWeek,
            trainingStreak: FatigueEngine.trainingStreak(workouts: workouts)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {
                        header
                        if !health.hasRequested && readiness.band == .unknown {
                            connectCard
                        } else if loaded && !health.hasRecoveryData {
                            noDataCard   // connected, but nothing came back (no Watch / reads denied)
                        }
                        if !readiness.drivers.isEmpty { driversCard }
                        if loaded && !insights.isEmpty { insightsCard }
                        if loaded && !health.hasRecoveryData {
                            // The noDataCard above already explains it — don't also stack four
                            // empty "needs Apple Watch data" trend cards for a Watch-less user.
                        } else if loaded {
                            trendCard("Readiness", series: readinessTrend, unit: "", fixedDomain: 0...100,
                                      info: "Your daily recovery read — HRV, resting heart rate, and sleep scored 0–100 against your own baselines. The trend is plotted against your current baseline.")
                            trendCard("HRV", series: series.hrv, unit: "ms",
                                      info: "Heart-rate variability — the beat-to-beat variation in your pulse. Higher vs your baseline usually means better recovery; a steady drift down can flag accumulating fatigue, illness, or stress.")
                            trendCard("Resting HR", series: series.restingHR, unit: "bpm",
                                      info: "Your heart rate at rest. Lower vs your baseline generally means better-recovered; an elevated resting HR often shows up a day or two before you feel run-down.")
                            trendCard("Sleep", series: series.sleepHours, unit: "h", decimals: 1,
                                      info: "Total time asleep, anchored to each wake-up day. Sleep is when you adapt to training — a consistent 7–9 hours supports recovery and performance.")
                            sleepStagesCard
                        } else {
                            ProgressView().tint(.accent).frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(.accent)
                }
            }
        }
        .tint(.accent)
        .task {
            series = await health.recoverySeries()
            sleepStages = await health.lastNightSleepStages()
            loaded = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            ZStack {
                Circle().stroke(bandColor.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(readiness.score ?? 0) / 100)
                    .stroke(bandColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(readiness.score.map(String.init) ?? "—")
                    .font(DSFont.numberXL)
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(readiness.headline)
                    .font(DSFont.title)
                    .foregroundStyle(bandColor)
                Text(readiness.trainingNote)
                    .font(DSFont.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var driversCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("What's driving it").dsLabel()
            ForEach(readiness.drivers) { driver in
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon(driver.sign))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(driverColor(driver.sign))
                        .frame(width: 16)
                    Text(driver.label)
                        .font(DSFont.numberSm).foregroundStyle(Color.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: DS.Spacing.sm)
                    contributionBar(driver).frame(width: 84, height: 8)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(driver.label)
                .accessibilityValue(signWord(driver.sign))
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    /// A diverging bar centered on baseline: grows right (green) for a positive
    /// contribution, left (orange) for a negative one — Oura-style "how much it helped/hurt."
    private func contributionBar(_ d: Readiness.Driver) -> some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let frac = CGFloat(d.fraction)
            let barW = max(d.points == 0 ? 0 : 3, half * abs(frac))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceElevated2)
                Rectangle().fill(Color.textTertiary.opacity(0.6))
                    .frame(width: 1).frame(maxHeight: .infinity)
                    .offset(x: half - 0.5)
                Capsule().fill(driverColor(d.sign))
                    .frame(width: barW)
                    .offset(x: frac >= 0 ? half : half - barW)
            }
        }
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Insights").dsLabel()
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    Image(systemName: insight.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(insightColor(insight.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(insight.message)
                            .font(DSFont.callout)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func insightColor(_ s: TrainingInsight.Severity) -> Color {
        switch s {
        case .positive: Color.success
        case .info:     Color.accent
        case .caution:  Color.accent
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Connect Apple Health").dsLabel()
            Text("Readiness reads your HRV, resting heart rate, and sleep (from Apple Watch) against your own baselines. Connect to get a daily read.")
                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                connecting = true
                Task {
                    await health.requestAuthorization()
                    series = await health.recoverySeries()
                    sleepStages = await health.lastNightSleepStages()
                    loaded = true
                    connecting = false
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if connecting { ProgressView().tint(Color.onAccent) }
                    Text("Connect Apple Health").font(.system(.subheadline, weight: .bold))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(connecting)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var noDataCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Label("No recovery data yet", systemImage: "applewatch.slash")
                .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("Readiness needs an Apple Watch — it reads HRV, resting heart rate, and sleep. If you have one, open the Health app → Sharing → Apps → Tonnage and allow those.")
                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Label("Open Health", systemImage: "heart.fill")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: Sleep stages

    @ViewBuilder private var sleepStagesCard: some View {
        if let s = sleepStages, s.total > 0 {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sleep Stages").dsLabel()
                    InfoPopoverButton(title: "Sleep Stages",
                        message: "Deep sleep drives physical recovery and muscle repair; REM supports memory and mood; core (light) sleep makes up most of the night. More deep + REM generally means a more restorative night.")
                    Spacer()
                    Text(String(format: "%.1f h", s.total))
                        .font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let total = max(s.total, 0.0001)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.accent).frame(width: w * CGFloat(s.deep / total))
                        Rectangle().fill(Color.success).frame(width: w * CGFloat(s.rem / total))
                        Rectangle().fill(Color.textSecondary).frame(width: w * CGFloat(s.core / total))
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                HStack(spacing: DS.Spacing.lg) {
                    stageLegend("Deep", s.deep, Color.accent)
                    stageLegend("REM", s.rem, Color.success)
                    stageLegend("Core", s.core, Color.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private func stageLegend(_ name: String, _ hours: Double, _ color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.textTertiary)
            Text(String(format: "%.1fh", hours)).font(DSFont.numberSm).monospacedDigit().foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: Trend cards

    @ViewBuilder
    private func trendCard(_ title: String, series data: [DatedValue], unit: String,
                           decimals: Int = 0, fixedDomain: ClosedRange<Double>? = nil,
                           info: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).dsLabel()
                if let info { InfoPopoverButton(title: title, message: info) }
                Spacer()
                if let latest = data.last {
                    Text(format(latest.value, decimals: decimals) + (unit.isEmpty ? "" : " \(unit)"))
                        .font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                }
            }
            if data.count >= 2 {
                trendChart(data, fixedDomain: fixedDomain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title) trend")
                    .accessibilityValue(data.suffix(7).map { format($0.value, decimals: decimals) }.joined(separator: ", "))
            } else {
                Text("Needs a few days of Apple Watch data to chart.")
                    .font(DSFont.caption).foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func trendChart(_ data: [DatedValue], fixedDomain: ClosedRange<Double>?) -> some View {
        let chart = Chart(data) { p in
            AreaMark(x: .value("Date", p.date), y: .value("v", p.value))
                .foregroundStyle(.linearGradient(colors: [Color.accent.opacity(0.28), Color.accent.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Date", p.date), y: .value("v", p.value))
                .foregroundStyle(Color.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", p.date), y: .value("v", p.value))
                .foregroundStyle(Color.accent).symbolSize(36)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel()
            }
        }
        .frame(height: 150)

        if let domain = fixedDomain {
            chart.chartYScale(domain: domain)
        } else {
            chart.chartYScale(domain: .automatic(includesZero: false))
        }
    }

    private func format(_ v: Double, decimals: Int) -> String { String(format: "%.\(decimals)f", v) }

    // MARK: Derived

    /// Per-day readiness computed from each day's signals vs current baselines.
    private var readinessTrend: [DatedValue] {
        let hrv = Dictionary(series.hrv.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        let rhr = Dictionary(series.restingHR.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        let slp = Dictionary(series.sleepHours.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        let dates = Set(hrv.keys).union(rhr.keys).union(slp.keys).sorted()
        return dates.compactMap { d in
            let r = ReadinessEngine.evaluate(ReadinessInputs(
                hrvMs: hrv[d], hrvBaselineMs: health.hrvBaseline,
                restingHR: rhr[d], restingHRBaseline: health.restingHRBaseline,
                sleepHours: slp[d]))
            guard let s = r.score else { return nil }
            return DatedValue(date: d, value: Double(s))
        }
    }

    // MARK: Styling

    private var bandColor: Color {
        switch readiness.band {
        case .primed, .ready: Color.success
        case .compromised:    Color.accent
        case .drained:        Color.danger
        case .unknown:        Color.textTertiary
        }
    }
    private func icon(_ s: Readiness.Driver.Sign) -> String {
        switch s { case .positive: "arrow.up"; case .negative: "arrow.down"; case .neutral: "minus" }
    }
    private func driverColor(_ s: Readiness.Driver.Sign) -> Color {
        switch s { case .positive: Color.success; case .negative: Color.accent; case .neutral: Color.textTertiary }
    }
    private func signWord(_ s: Readiness.Driver.Sign) -> String {
        switch s { case .positive: "helping recovery"; case .negative: "hurting recovery"; case .neutral: "neutral" }
    }
}
