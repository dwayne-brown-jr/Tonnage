import SwiftUI
import TonnageCore

/// How-to directions for a movement, presented from the exercise card's info button.
struct ExerciseDirectionsSheet: View {
    let name: String
    let isCardio: Bool
    let coachNote: String

    @Environment(\.dismiss) private var dismiss

    private var directions: ExerciseDirections? { ExerciseLibrary.directions(for: name) }
    private var targets: MuscleTargets? { ExerciseLibrary.muscleTargets(for: name) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        if let directions {
                            header(directions)
                            if let targets { musclesPanel(targets) }
                            steps(directions.steps)
                        } else {
                            EmptyStateView(
                                systemImage: "book.closed",
                                title: "No Directions Yet",
                                message: "This movement doesn't have a write-up — go by your coaching note and good form."
                            )
                        }
                        if !coachNote.isEmpty { coachNoteBlock }
                    }
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("How To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func header(_ d: ExerciseDirections) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                if isCardio { tag("CARDIO") }
                Text(d.targets)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            Text(name)
                .font(DSFont.display)
                .foregroundStyle(Color.textPrimary)
            Text(d.summary)
                .font(DSFont.callout)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// Front/back body map with the movement's prime movers lit, plus a two-row legend.
    private func musclesPanel(_ t: MuscleTargets) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Muscles Worked").dsLabel()
            VStack(spacing: DS.Spacing.md) {
                MuscleMapView(.targets(t))
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(precisionGrid)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    legendRow("Primary", muscles: t.primary, swatch: Color.accent)
                    if !t.secondary.isEmpty {
                        legendRow("Secondary", muscles: t.secondary, swatch: Color.accent.opacity(0.57))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
            )
        }
    }

    private func legendRow(_ title: String, muscles: [Muscle], swatch: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            RoundedRectangle(cornerRadius: 1.5).fill(swatch)
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(title)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .textCase(.uppercase).kerning(0.9)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 78, alignment: .leading)
            Text(muscles.map(\.label).joined(separator: " · "))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Faint dot grid behind the figures — the "precision instrument" backdrop.
    private var precisionGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 12
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                             with: .color(.white.opacity(0.06)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Directions").dsLabel()
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Text("\(i + 1)")
                            .font(DSFont.numberSm)
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 26, height: 26)
                            .background(Color.accent, in: Circle())
                        Text(step)
                            .font(DSFont.body)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline)
            )
        }
    }

    private var coachNoteBlock: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Coaching Note").dsLabel()
                Text(coachNote)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .kerning(0.8)
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

#Preview("Directions") {
    ExerciseDirectionsSheet(name: "Barbell Bench Press", isCardio: false,
                            coachNote: "Ramp up, last set is your top set")
        .preferredColorScheme(.dark)
}
