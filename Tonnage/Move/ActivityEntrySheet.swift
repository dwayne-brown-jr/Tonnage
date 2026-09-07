import SwiftUI
import SwiftData
import TonnageCore

/// Logs an active-rest / cardio activity. Shows the metrics that fit the kind
/// (distance for walks/bikes, flights for stairs) plus duration.
struct ActivityEntrySheet: View {
    let kind: ActivityKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    @State private var name: String
    @State private var minutes: Double = 30
    @State private var distance: Double = 0
    @State private var flightsCount: Double = 0
    @State private var detail = ""
    /// When the activity happened. Defaults to now; backdate it to log a session
    /// for a day the app didn't auto-import (e.g. a bike ride from Apple Fitness).
    @State private var date: Date = .now

    init(kind: ActivityKind) {
        self.kind = kind
        _name = State(initialValue: kind == .custom ? "" : kind.label)
    }

    private var metrics: [SetMetric] {
        ExerciseLibrary.metrics(for: kind == .custom ? (name.isEmpty ? "activity" : name) : kind.label, isCardio: true)
    }
    private var showsDistance: Bool { metrics.contains(.distance) }
    private var showsFlights: Bool { metrics.contains(.flights) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        headerIcon
                        if kind == .custom {
                            textField("Activity", text: $name, placeholder: "e.g. Hike")
                        }
                        dateRow
                        metricRow("Duration", value: $minutes, step: 5, range: 0...600, unit: "min")
                        if showsDistance {
                            metricRow("Distance", value: $distance, step: 0.1, range: 0...200, unit: "mi", decimal: true)
                        }
                        if showsFlights {
                            metricRow("Flights", value: $flightsCount, step: 1, range: 0...999, unit: "fl")
                        }
                        textField("Notes", text: $detail, placeholder: "Optional")
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .foregroundStyle(canSave ? Color.accent : Color.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var headerIcon: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
            Text(kind == .custom ? "Custom Activity" : kind.label)
                .font(DSFont.title)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private var dateRow: some View {
        HStack {
            Text("Date").dsLabel()
            Spacer()
            DatePicker("", selection: $date, in: ...Date.now,
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.accent)
        }
    }

    private func metricRow(_ label: String, value: Binding<Double>, step: Double,
                           range: ClosedRange<Double>, unit: String, decimal: Bool = false) -> some View {
        HStack {
            Text(label).dsLabel()
            Spacer()
            StepperField(value: value, step: step, range: range, unit: unit, isDecimal: decimal)
        }
    }

    private func textField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label).dsLabel()
            TextField(placeholder, text: text)
                .font(DSFont.body)
                .foregroundStyle(Color.textPrimary)
                .padding(DS.Spacing.md)
                .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
    }

    private func save() {
        let activity = Activity(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            durationMinutes: Int(minutes),
            distanceMiles: showsDistance && distance > 0 ? distance : nil,
            flights: showsFlights && flightsCount > 0 ? Int(flightsCount) : nil,
            // Estimate from the kind's kcal/min — the same value we mirror to Apple Health below.
            activeCalories: minutes > 0 ? Int((kind.kcalPerMinute * minutes).rounded()) : nil,
            detail: detail,
            date: date
        )
        context.insert(activity)
        context.saveOrReport()
        Task { await health.saveActivity(activity) }   // mirror to Apple Health (no-op if off)
        Haptics.success()
        dismiss()
    }
}

#Preview("Activity entry") {
    ActivityEntrySheet(kind: .weightedVestWalk)
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
