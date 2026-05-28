import SwiftUI
import TonnageCore

// MARK: - Week selector

/// Slim 5-segment week progress + the phase intent line. The current week is the
/// only highlighted segment (past = filled, future = faint); tap a segment to jump.
/// Replaces the old row of chunky filled buttons so it reads as "where in the block."
struct WeekSelector: View {
    @Binding var week: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { w in
                    Capsule()
                        .fill(color(for: w))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(DS.snappySpring) { week = w }
                            Haptics.selection()
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Week \(w)")
                        .accessibilityAddTraits(w == week ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(height: 22)

            let phase = WeekPhase.forWeek(week)
            HStack(spacing: DS.Spacing.xs) {
                Text("WEEK \(week)")
                    .font(.system(.caption, weight: .heavy).width(.condensed))
                    .foregroundStyle(Color.accent)
                Text("·").font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                Text(phase.title)
                    .font(.system(.caption, weight: .bold).width(.condensed))
                    .foregroundStyle(Color.textSecondary)
                Text(phase.detail)
                    .font(.system(.caption2))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .animation(.none, value: week)
        }
    }

    private func color(for w: Int) -> Color {
        if w == week { return .accent }
        if w < week { return Color.textSecondary.opacity(0.45) }
        return Color.surfaceElevated2
    }
}

// MARK: - Session selector

struct SessionSelector: View {
    let sessions: [SessionTemplate]
    @Binding var index: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { i, session in
                    let selected = i == index
                    Button {
                        withAnimation(DS.snappySpring) { index = i }
                        Haptics.selection()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.name)
                                .font(.system(.subheadline, weight: .bold))
                                .foregroundStyle(selected ? Color.onAccent : Color.textPrimary)
                            Text(session.subtitle)
                                .font(.system(.caption2))
                                .foregroundStyle(selected ? Color.onAccent.opacity(0.85) : Color.textTertiary)
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(selected ? Color.accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: DS.Stroke.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Day-type toggle

struct DayTypeToggle: View {
    @Binding var dayType: DayType

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DayType.allCases) { type in
                let selected = type == dayType
                Button {
                    withAnimation(DS.snappySpring) { dayType = type }
                    Haptics.selection()
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: type.systemImage)
                            .font(.system(size: 11, weight: .bold))
                        Text(type.title)
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Color.accent : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(selected ? Color.surfaceElevated2 : Color.clear)
                            .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 4, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

// MARK: - Live session stats

struct SessionStatsBar: View {
    let workout: LoggedWorkout?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            stat(value: "\(workout?.completedSetCount ?? 0)", label: "Sets", accent: false)
            divider
            stat(value: "\(workout?.totalReps ?? 0)", label: "Reps", accent: false)
            divider
            stat(value: formattedVolume, label: "Volume · lb", accent: true)
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
        )
    }

    private var formattedVolume: String {
        let v = workout?.totalVolume ?? 0
        return v.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    private func stat(value: String, label: String, accent: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DSFont.numberXL)
                .monospacedDigit()
                .foregroundStyle(accent ? Color.accent : Color.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.hairline).frame(width: DS.Stroke.hairline, height: 32)
    }
}
