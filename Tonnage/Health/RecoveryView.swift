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
    @Query(sort: \LoggedWorkout.weekNumber) private var workouts: [LoggedWorkout]
    @AppStorage("currentBlock") private var currentBlock = 1
    @AppStorage("train.week") private var trainWeek = 1
    @State private var series = RecoverySeries()
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
            currentWeek: trainWeek))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {
                        header
                        if !health.hasRequested && readiness.band == .unknown { connectCard }
                        if !readiness.drivers.isEmpty { driversCard }
                        if loaded && !insights.isEmpty { insightsCard }
                        if loaded {
                            trendCard("Readiness", series: readinessTrend, unit: "", fixedDomain: 0...100)
                            trendCard("HRV", series: series.hrv, unit: "ms")
                            trendCard("Resting HR", series: series.restingHR, unit: "bpm")
                            trendCard("Sleep", series: series.sleepHours, unit: "h", decimals: 1)
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("What's driving it").dsLabel()
            ForEach(readiness.drivers) { driver in
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon(driver.sign))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(driverColor(driver.sign))
                        .frame(width: 16)
                    Text(driver.label).font(DSFont.numberSm).foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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

    // MARK: Trend cards

    @ViewBuilder
    private func trendCard(_ title: String, series data: [DatedValue], unit: String,
                           decimals: Int = 0, fixedDomain: ClosedRange<Double>? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).dsLabel()
                Spacer()
                if let latest = data.last {
                    Text(format(latest.value, decimals: decimals) + (unit.isEmpty ? "" : " \(unit)"))
                        .font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                }
            }
            if data.count >= 2 {
                trendChart(data, fixedDomain: fixedDomain)
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
}
