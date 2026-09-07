import SwiftUI
import TonnageCore

/// What actually happened on one calendar day — reached by tapping a day in the DATA
/// "Last 7 Days" strip. Sessions are otherwise only reachable by rebuilding their program
/// slot (block → week → day chip), which is no help when the question is "what did I lift
/// on Tuesday?".
struct DayDetailSheet: View {
    let day: Date
    let workouts: [LoggedWorkout]
    let activities: [Activity]

    @Environment(\.dismiss) private var dismiss

    private var cal: Calendar { .current }
    private var dayWorkouts: [LoggedWorkout] {
        workouts.filter { cal.isDate($0.date, inSameDayAs: day) && $0.hasContent }
    }
    private var dayActivities: [Activity] {
        activities.filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }
    private var isEmpty: Bool { dayWorkouts.isEmpty && dayActivities.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        if isEmpty { emptyState }
                        ForEach(dayWorkouts) { workout in workoutCard(workout) }
                        ForEach(dayActivities) { activity in activityCard(activity) }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "calendar")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("Nothing Logged").font(DSFont.title).foregroundStyle(Color.textPrimary)
            Text("No lift, rest day, or cardio recorded for this day.")
                .font(.system(.subheadline))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }

    @ViewBuilder private func workoutCard(_ workout: LoggedWorkout) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.dayType == .lift
                     ? (workout.sessionName.isEmpty ? "Workout" : workout.sessionName)
                     : (workout.dayType == .activeRest ? "Active Recovery" : "Full Rest"))
                    .font(DSFont.title).foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("BLOCK \(String(format: "%02d", workout.blockNumber)) · WEEK \(workout.weekNumber)")
                    .dsLabel()
            }

            if workout.dayType == .lift && workout.completedSetCount > 0 {
                HStack(spacing: DS.Spacing.sm) {
                    totals("\(workout.completedSetCount)", "Sets")
                    totals("\(workout.totalReps)", "Reps")
                    totals(workout.totalVolume.formatted(.number.precision(.fractionLength(0))), "Volume · lb")
                }
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(workout.orderedExercises.filter { $0.completedSetCount > 0 }) { ex in
                        exerciseRow(ex)
                    }
                }
            }

            if !workout.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").dsLabel()
                    Text(workout.notes)
                        .font(.system(.subheadline))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func totals(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DSFont.number).monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).dsLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func exerciseRow(_ ex: LoggedExercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ex.name)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ex.orderedSets.filter { $0.completed && !$0.isWarmup }
                    .map { "\(CoachEngine.fmt($0.weight)) × \($0.reps)" }
                    .joined(separator: "   "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityCard(_ activity: Activity) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: activity.kind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name.isEmpty ? activity.kind.label : activity.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(activity.date.formatted(date: .omitted, time: .shortened))
                    .dsLabel()
            }
            Spacer(minLength: DS.Spacing.sm)
            Text("\(activity.durationMinutes) min")
                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }
}
