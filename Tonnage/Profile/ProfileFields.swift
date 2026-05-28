import SwiftUI
import TonnageCore

/// The editable athlete-profile fields, bound directly to `@AppStorage` so edits
/// persist immediately. Reused by first-run setup and Settings. Everything past the
/// name is optional — the more that's filled in, the better the coach tailors.
struct ProfileFields: View {
    @AppStorage(ProfileStore.Key.name) private var name = ""
    @AppStorage(ProfileStore.Key.age) private var age = 0
    @AppStorage(ProfileStore.Key.sex) private var sexRaw = BiologicalSex.unspecified.rawValue
    @AppStorage(ProfileStore.Key.height) private var heightInches = 0
    @AppStorage(ProfileStore.Key.weight) private var weightLb = 0
    @AppStorage(ProfileStore.Key.goal) private var goalRaw = TrainingGoal.recomp.rawValue
    @AppStorage(ProfileStore.Key.experience) private var experienceRaw = ExperienceLevel.returning.rawValue
    @AppStorage(ProfileStore.Key.limitations) private var limitations = ""

    private var sex: BiologicalSex { BiologicalSex(rawValue: sexRaw) ?? .unspecified }
    private var goal: TrainingGoal { TrainingGoal(rawValue: goalRaw) ?? .recomp }
    private var experience: ExperienceLevel { ExperienceLevel(rawValue: experienceRaw) ?? .returning }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            field("YOUR NAME") {
                TextField("First name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .modifier(InputStyle())
            }

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                field("AGE") {
                    TextField("32", text: digits($age))
                        .keyboardType(.numberPad)
                        .modifier(InputStyle())
                }
                field("WEIGHT (LB)") {
                    TextField("180", text: digits($weightLb))
                        .keyboardType(.numberPad)
                        .modifier(InputStyle())
                }
            }

            field("HEIGHT") {
                HStack(spacing: DS.Spacing.md) {
                    TextField("5", text: feetText)
                        .keyboardType(.numberPad)
                        .modifier(InputStyle())
                    Text("ft").font(DSFont.caption).foregroundStyle(Color.textTertiary)
                    TextField("11", text: inchesText)
                        .keyboardType(.numberPad)
                        .modifier(InputStyle())
                    Text("in").font(DSFont.caption).foregroundStyle(Color.textTertiary)
                }
            }

            field("SEX") {
                chips(BiologicalSex.allCases, selected: sex, label: \.label) { sexRaw = $0.rawValue }
            }

            field("GOAL") {
                chips(TrainingGoal.allCases, selected: goal, label: \.label) { goalRaw = $0.rawValue }
            }

            field("EXPERIENCE") {
                chips(ExperienceLevel.allCases, selected: experience, label: \.label) { experienceRaw = $0.rawValue }
            }

            field("ANYTHING TO TRAIN AROUND?") {
                TextField("Injuries, limitations, things to avoid…", text: $limitations, axis: .vertical)
                    .lineLimit(2...4)
                    .modifier(InputStyle())
            }
        }
    }

    // MARK: Pieces

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).dsLabel()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chips<T: Identifiable & Hashable>(
        _ options: [T], selected: T, label: KeyPath<T, String>, pick: @escaping (T) -> Void
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    pick(option)
                    Haptics.selection()
                } label: {
                    Text(option[keyPath: label])
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm + 2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(isSelected ? Color.accent : Color.surfaceElevated2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Numeric bindings (Int 0 == unset → blank field with placeholder)

    private func digits(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue > 0 ? String(value.wrappedValue) : "" },
            set: { value.wrappedValue = Int($0.filter(\.isNumber)) ?? 0 }
        )
    }

    private var feetText: Binding<String> {
        Binding(
            get: { heightInches > 0 ? String(heightInches / 12) : "" },
            set: { heightInches = (Int($0.filter(\.isNumber)) ?? 0) * 12 + (heightInches % 12) }
        )
    }

    private var inchesText: Binding<String> {
        Binding(
            get: { heightInches > 0 ? String(heightInches % 12) : "" },
            set: { heightInches = (heightInches / 12) * 12 + min(11, Int($0.filter(\.isNumber)) ?? 0) }
        )
    }
}

/// Shared text-field chrome for the profile inputs.
private struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DSFont.body)
            .foregroundStyle(Color.textPrimary)
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}
