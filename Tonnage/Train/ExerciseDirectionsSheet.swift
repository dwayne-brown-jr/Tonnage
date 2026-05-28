import SwiftUI
import TonnageCore

/// How-to directions for a movement, presented from the exercise card's info button.
struct ExerciseDirectionsSheet: View {
    let name: String
    let isCardio: Bool
    let coachNote: String

    @Environment(\.dismiss) private var dismiss

    private var directions: ExerciseDirections? { ExerciseLibrary.directions(for: name) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        if let directions {
                            header(directions)
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
