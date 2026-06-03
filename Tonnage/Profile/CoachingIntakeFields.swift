import SwiftUI
import TonnageCore

/// The coaching-intake questions — starting point, priority muscles, days/week, equipment.
/// Shared by first-run profile setup, the Settings profile editor, AND the one-time
/// "what's new" update flow, so the questions, options, and explanations are byte-for-byte
/// identical everywhere. Bound to the same `ProfileStore` keys, so answers persist
/// immediately regardless of where they're edited.
struct CoachingIntakeFields: View {
    /// Lead with the short "why we ask" note (on in onboarding / the update flow).
    var showsWhy: Bool = true

    @AppStorage(ProfileStore.Key.startingPoint) private var startingPointRaw = StartingPoint.unsure.rawValue
    @AppStorage(ProfileStore.Key.priorityFocuses) private var priorityFocusesRaw = ""
    @AppStorage(ProfileStore.Key.daysPerWeek) private var daysPerWeek = 0
    @AppStorage(ProfileStore.Key.environment) private var environmentRaw = TrainingEnvironment.fullGym.rawValue

    private var startingPoint: StartingPoint { StartingPoint(rawValue: startingPointRaw) ?? .unsure }
    private var environment: TrainingEnvironment { TrainingEnvironment(rawValue: environmentRaw) ?? .fullGym }
    private var focuses: Set<BodyFocus> {
        Set(priorityFocusesRaw.split(separator: ",").compactMap { BodyFocus(rawValue: String($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            if showsWhy {
                Text("Your coach uses these to pick your split, add volume to the muscles you want to grow, and choose exercises you can actually do — so your plan fits you from day one.")
                    .font(DSFont.caption).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("STARTING POINT", hint: "Where you're starting shapes the whole plan — pick the closest.") {
                startingPointPicker
            }
            field("WHAT DO YOU WANT TO BRING UP?", hint: "Your coach adds extra volume here. Pick any that apply.") {
                focusChips
            }
            field("TRAINING DAYS / WEEK", hint: "Helps pick the right split.") {
                daysChips
            }
            field("EQUIPMENT", hint: "Keeps exercise picks realistic for where you train.") {
                envChips
            }
        }
    }

    // MARK: Field scaffold

    private func field(_ title: String, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).dsLabel()
            if let hint {
                Text(hint).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pickers

    /// Starting-point cards with plain-language definitions (single select).
    private var startingPointPicker: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(StartingPoint.allCases) { sp in
                let isSelected = startingPoint == sp
                Button {
                    startingPointRaw = sp.rawValue
                    SharedProfile.write(sp)   // share with Tonnage Fuel
                    Haptics.selection()
                } label: {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accent : Color.textTertiary)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sp.label).font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.textPrimary)
                            Text(sp.definition).font(.system(.caption2)).foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.accent.opacity(0.12) : Color.surfaceElevated2))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(isSelected ? Color.accent : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Training days/week (2–6, single select).
    private var daysChips: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(2...6, id: \.self) { n in
                let isSelected = daysPerWeek == n
                Button {
                    daysPerWeek = n
                    Haptics.selection()
                } label: {
                    Text("\(n)")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(isSelected ? Color.accent : Color.surfaceElevated2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Muscles to bring up (multi-select).
    private var focusChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
            ForEach(BodyFocus.allCases) { f in
                let isOn = focuses.contains(f)
                Button {
                    toggleFocus(f)
                    Haptics.selection()
                } label: {
                    Text(f.label)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isOn ? Color.onAccent : Color.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm + 2)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(isOn ? Color.accent : Color.surfaceElevated2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Equipment / environment (single select).
    private var envChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
            ForEach(TrainingEnvironment.allCases) { env in
                let isSelected = environment == env
                Button {
                    environmentRaw = env.rawValue
                    Haptics.selection()
                } label: {
                    Text(env.label)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm + 2)
                        .multilineTextAlignment(.center)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(isSelected ? Color.accent : Color.surfaceElevated2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleFocus(_ f: BodyFocus) {
        var set = focuses
        if set.contains(f) { set.remove(f) } else { set.insert(f) }
        priorityFocusesRaw = BodyFocus.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}
