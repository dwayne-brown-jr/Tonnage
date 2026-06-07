import SwiftUI
import SwiftData
import TonnageCore

/// Pick a training split. Selecting a different one rewrites the current program's
/// sessions to that preset (logged workouts are kept — only the future plan changes).
/// Used at first-run and re-openable from Settings.
struct SplitPickerSheet: View {
    /// Called after a split is applied/kept and the sheet dismisses.
    var onApply: () -> Void = {}

    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query private var workouts: [LoggedWorkout]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ProfileStore.Key.split) private var splitRaw = SplitPreset.upperLower.rawValue
    @AppStorage("hasChosenSplit") private var hasChosenSplit = false
    @AppStorage(ProfileStore.Key.daysPerWeek) private var daysPerWeek = 0

    @State private var selected: SplitPreset = .upperLower
    @State private var confirming = false

    private var program: Program? { programs.first }
    private var current: SplitPreset { SplitPreset(rawValue: splitRaw) ?? .upperLower }
    private var hasData: Bool { !workouts.isEmpty }
    /// The split that fits the athlete's days/week — pre-selected on first pick.
    private var recommended: SplitPreset? { SplitPreset.recommended(forDaysPerWeek: daysPerWeek) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            Text("Choose how your week is structured. Tonnage runs any of these as 5-week blocks with the same top-set progression — and the AI planner adapts to whichever you pick.")
                                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(SplitPreset.allCases) { presetCard($0) }
                        }
                        .padding(DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxl)
                    }
                    actionBar
                }
            }
            .navigationTitle("Training Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
            }
            .confirmationDialog("Switch to \(selected.label)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Switch Split", role: .destructive) { apply() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This rewrites your program's sessions to the \(selected.label) layout. Your logged workouts are kept, but the plan going forward changes.")
            }
        }
        .tint(.accent)
        .preferredColorScheme(.dark)
        .onAppear { selected = (hasChosenSplit ? nil : recommended) ?? current }
    }

    private func presetCard(_ preset: SplitPreset) -> some View {
        let isSelected = selected == preset
        return Button {
            Haptics.selection(); selected = preset
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(preset.label).font(.system(.headline, weight: .bold)).foregroundStyle(Color.textPrimary)
                    if preset == current {
                        Text("CURRENT").font(.system(.caption2, weight: .heavy)).kerning(0.5)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.surfaceElevated2))
                    }
                    if preset == recommended {
                        Text("RECOMMENDED").font(.system(.caption2, weight: .heavy)).kerning(0.5)
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accent))
                    }
                    Spacer(minLength: 0)
                    Text("\(preset.daysPerWeek) days/wk")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(isSelected ? Color.accent : Color.textTertiary)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accent : Color.textTertiary)
                }
                Text(preset.blurb).font(DSFont.caption).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(preset.sessionSpecs.map(\.name).joined(separator: " · "))
                    .font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(isSelected ? Color.accent : Color.hairline, lineWidth: isSelected ? 1.5 : DS.Stroke.hairline))
        }
        .buttonStyle(.plain)
    }

    /// Warn when the chosen split needs more days than the athlete said they can train.
    private var mismatchNote: String? {
        guard daysPerWeek > 0, selected.daysPerWeek > daysPerWeek + 1 else { return nil }
        return "\(selected.label) is \(selected.daysPerWeek) days/week — you said \(daysPerWeek). Make sure that fits your schedule."
    }

    private var actionBar: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let note = mismatchNote {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(DSFont.caption).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if selected != current && hasData {
                    confirming = true
                } else {
                    apply()
                }
            } label: {
                Text(selected == current ? "Keep \(selected.label)" : "Use \(selected.label)")
                    .font(.system(.headline, weight: .bold)).foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline) }
    }

    private func apply() {
        let changed = selected != current
        splitRaw = selected.rawValue
        hasChosenSplit = true
        if changed, let program {
            applySplit(selected, to: program, in: context)
        }
        Haptics.success()
        onApply()
        dismiss()
    }
}

#Preview("Split picker") {
    SplitPickerSheet()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
