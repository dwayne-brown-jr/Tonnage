import SwiftUI
import TonnageCore

enum ExerciseFormMode: Identifiable {
    case edit       // change this week's prescription, keep logged sets
    case swap       // replace with a different movement, reset sets
    case addCustom  // add a new exercise to this week

    var id: Int { switch self { case .edit: 0; case .swap: 1; case .addCustom: 2 } }
    var title: String {
        switch self {
        case .edit: "Edit Prescription"
        case .swap: "Swap Exercise"
        case .addCustom: "Add Exercise"
        }
    }
    var actionTitle: String { self == .addCustom ? "Add" : "Save" }
    var resetsSets: Bool { self != .edit }
}

/// Per-week exercise form. Edits apply to this week's workout only — the base
/// program template is never touched.
struct EditExerciseSheet: View {
    let store: TrainStore
    var exercise: LoggedExercise?
    let mode: ExerciseFormMode

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isCompound: Bool
    @State private var isCardio: Bool
    @State private var sets: Double
    @State private var repRange: String
    @State private var rpeTarget: String
    @State private var notes: String

    init(store: TrainStore, exercise: LoggedExercise?, mode: ExerciseFormMode) {
        self.store = store
        self.exercise = exercise
        self.mode = mode
        _name = State(initialValue: mode == .swap ? "" : (exercise?.name ?? ""))
        _isCompound = State(initialValue: exercise?.isCompound ?? false)
        _isCardio = State(initialValue: exercise?.isCardio ?? false)
        _sets = State(initialValue: Double(exercise?.prescribedSets ?? 3))
        _repRange = State(initialValue: exercise?.repRange ?? "")
        _rpeTarget = State(initialValue: mode == .swap ? "" : (exercise?.rpeTarget ?? ""))
        _notes = State(initialValue: mode == .swap ? "" : (exercise?.prescriptionNotes ?? ""))
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var week: Int { store.workout?.weekNumber ?? 1 }
    private var block: Int { store.workout?.blockNumber ?? 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        if mode != .edit { revertNote }
                        textField("Exercise", text: $name, placeholder: "e.g. Incline DB Press")
                        typeToggles
                        if !isCardio {
                            HStack {
                                Text("Sets").dsLabel()
                                Spacer()
                                StepperField(value: $sets, step: 1, range: 1...12, unit: "sets")
                            }
                        }
                        textField(isCardio ? "Prescription" : "Rep Range", text: $repRange,
                                  placeholder: isCardio ? "e.g. 10 min" : "e.g. 8-10")
                        textField(isCardio ? "Effort" : "RPE Target", text: $rpeTarget,
                                  placeholder: isCardio ? "e.g. easy" : "e.g. 8")
                        textField("Notes", text: $notes, placeholder: "Optional cue")
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode.actionTitle, action: save)
                        .fontWeight(.bold)
                        .foregroundStyle(canSave ? Color.accent : Color.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var revertNote: some View {
        Label("Applies to Week \(week) only — reverts next week.", systemImage: "calendar.badge.clock")
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(Color.textTertiary)
    }

    private var typeToggles: some View {
        HStack(spacing: DS.Spacing.md) {
            chipToggle("Compound", isOn: $isCompound, systemImage: "scalemass.fill")
            chipToggle("Cardio", isOn: $isCardio, systemImage: "figure.run")
        }
    }

    private func chipToggle(_ title: String, isOn: Binding<Bool>, systemImage: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            Haptics.selection()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.onAccent : Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(isOn.wrappedValue ? Color.accent : Color.surfaceElevated2)
                )
        }
        .buttonStyle(.plain)
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .addCustom:
            store.addCustomExercise(name: trimmed, isCompound: isCompound, isCardio: isCardio,
                                    sets: Int(sets), repRange: repRange, rpeTarget: rpeTarget,
                                    notes: notes, block: block, week: week)
        case .edit, .swap:
            guard let exercise else { break }
            store.editExercise(exercise, name: trimmed, isCompound: isCompound, isCardio: isCardio,
                               sets: Int(sets), repRange: repRange, rpeTarget: rpeTarget, notes: notes,
                               block: block, week: week, resetSets: mode.resetsSets)
        }
        dismiss()
    }
}
