import SwiftUI
import TonnageCore

/// Plate calculator: enter a target weight + bar, see what to load per side.
struct PlateCalculatorSheet: View {
    let initialTarget: Double

    @Environment(\.dismiss) private var dismiss
    @State private var target: Double = 135
    @State private var bar: Double = PlateMath.defaultBar

    private var loadout: PlateMath.Loadout {
        PlateMath.loadout(target: target, bar: bar)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        inputs
                        plateVisual
                        breakdown
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear { target = initialTarget }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            field(label: "Target", value: $target, step: 5, unit: "lb")
            field(label: "Bar", value: $bar, step: 5, unit: "lb")
        }
    }

    private func field(label: String, value: Binding<Double>, step: Double, unit: String) -> some View {
        HStack {
            Text(label).dsLabel()
            Spacer()
            StepperField(value: value, step: step, range: 0...2000, unit: unit)
        }
    }

    private var plateVisual: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(CoachEngine.fmt(loadout.achievable))
                .font(DSFont.numberXL)
                .foregroundStyle(loadout.isExact ? Color.accent : Color.textPrimary)
            Text(loadout.isExact ? "loaded · per bar" : "closest below \(CoachEngine.fmt(target))")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)

            if loadout.perSide.isEmpty {
                Text("Just the bar").font(DSFont.callout).foregroundStyle(Color.textSecondary)
            } else {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(loadout.perSide) { pair in
                        ForEach(0..<pair.perSide, id: \.self) { _ in
                            plateChip(pair.plate)
                        }
                    }
                }
                Text("per side")
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    /// A plate rendered as a vertical bar — taller/wider for heavier plates.
    private func plateChip(_ plate: Double) -> some View {
        let height = 40 + (plate / 45) * 56
        return VStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accent)
                .frame(width: 16, height: height)
            Text(CoachEngine.fmt(plate))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Per Side").dsLabel()
            if loadout.perSide.isEmpty {
                Text("No plates needed.").font(DSFont.callout).foregroundStyle(Color.textSecondary)
            } else {
                ForEach(loadout.perSide) { pair in
                    HStack {
                        Text("\(CoachEngine.fmt(pair.plate)) lb")
                            .font(DSFont.number)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("× \(pair.perSide)")
                            .font(DSFont.number)
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
            if !loadout.isExact {
                Text("\(CoachEngine.fmt(loadout.remainderPerSide * 2)) lb short of target with standard plates.")
                    .font(.system(.caption))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Plates") {
    PlateCalculatorSheet(initialTarget: 225).preferredColorScheme(.dark)
}
