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
    @State private var aiSwaps: [String] = []
    @State private var aiLoading = false
    @State private var aiError: String?

    init(store: TrainStore, exercise: LoggedExercise?, mode: ExerciseFormMode) {
        self.store = store
        self.exercise = exercise
        self.mode = mode
        _name = State(initialValue: mode == .swap ? "" : (exercise?.name ?? ""))
        _isCompound = State(initialValue: exercise?.isCompound ?? false)
        _isCardio = State(initialValue: exercise?.isCardio ?? false)
        _sets = State(initialValue: Double(exercise?.prescribedSets ?? 3))
        // Sensible defaults for a fresh add so a quick-add tap → "Add" gives 3×8-12 @ RPE 8.
        _repRange = State(initialValue: exercise?.repRange ?? (mode == .addCustom ? "8-12" : ""))
        // Keep the slot's effort target on a swap — you're changing the movement, not the
        // set/rep scheme. Notes are movement-specific, so those reset.
        _rpeTarget = State(initialValue: exercise?.rpeTarget ?? (mode == .addCustom ? "8" : ""))
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
                        if mode == .swap && hasLoggedSets { swapWarning }
                        if mode == .swap { swapSuggestions; coachSwapSection }
                        if mode == .addCustom { quickAddSuggestions }
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

    /// A swap rebuilds the slot's sets, so any logged work for it is lost — warn first.
    private var hasLoggedSets: Bool { (exercise?.sets ?? []).contains { $0.completed && !$0.isWarmup } }

    private var swapWarning: some View {
        Label("Swapping clears the sets you've already logged for this slot.", systemImage: "exclamationmark.triangle.fill")
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(Color.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Names already in the current session — excluded from suggestions so they're
    /// context-specific (and never offer something you're already doing).
    private var sessionExerciseNames: Set<String> {
        Set((exercise?.workout ?? store.workout)?.orderedExercises.map(\.name) ?? [])
    }

    /// Quick-add grid for the "Add Exercise" flow — tap a common movement (calisthenics-forward)
    /// to fill name + compound, or type your own below. Excludes what's already in this session.
    @ViewBuilder private var quickAddSuggestions: some View {
        let picks = ExerciseLibrary.quickAddSuggestions.filter { !sessionExerciseNames.contains($0) }
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("Quick Add").dsLabel()
                chipGrid(picks)
                Text("Tap to fill, or type your own below.")
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
    }

    /// Same-muscle swap suggestions (instant, rule-based). Tap to fill, or type your own.
    @ViewBuilder private var swapSuggestions: some View {
        let original = exercise?.name ?? ""
        let alts = ExerciseLibrary.alternatives(for: original, excluding: sessionExerciseNames)
        if !alts.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if let group = ExerciseLibrary.muscleGroup(for: original) {
                    Text("Same muscle · \(group.label)").dsLabel()
                } else {
                    Text("Suggestions").dsLabel()
                }
                chipGrid(alts)
                Text("Pick one, or type your own below.")
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
    }

    /// Optional AI pass — smarter, context-aware alternatives (factors in your goal +
    /// limitations, and reaches beyond the built-in catalog).
    @ViewBuilder private var coachSwapSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !aiSwaps.isEmpty {
                Label("Coach suggests", systemImage: "sparkles")
                    .font(.system(.caption2, weight: .bold)).textCase(.uppercase).kerning(0.6)
                    .foregroundStyle(Color.accent)
                chipGrid(aiSwaps)
            }
            Button { Task { await askCoach() } } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if aiLoading { ProgressView().tint(Color.accent) }
                    else { Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)) }
                    Text(aiLoading ? "Asking Coach…"
                         : (aiSwaps.isEmpty ? "Ask Coach for alternatives" : "Ask Coach again"))
                        .font(.system(.subheadline, weight: .semibold))
                }
                .foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(aiLoading)
            if let aiError {
                Text(aiError).font(.system(.caption2)).foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shared tap-to-pick grid used by both the rule-based and AI suggestion lists.
    private func chipGrid(_ names: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.sm)],
                  spacing: DS.Spacing.sm) {
            ForEach(names, id: \.self) { alt in
                Button {
                    name = alt
                    isCompound = ExerciseLibrary.isCompound(alt)
                    Haptics.selection()
                } label: {
                    Text(alt)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(name == alt ? Color.onAccent : Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2).minimumScaleFactor(0.85)
                        .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(name == alt ? Color.accent : Color.surfaceElevated2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor private func askCoach() async {
        guard let route = CoachKey.route else {
            aiError = "Add your Anthropic API key in Settings to ask Coach."
            return
        }
        aiError = nil
        aiLoading = true
        defer { aiLoading = false }
        let original = exercise?.name ?? name
        // Avoid what's already in the session and anything we already showed, so
        // "Ask Coach again" returns genuinely new options.
        let avoid = Array(sessionExerciseNames) + aiSwaps
        let system = CoachSwapSuggester.systemPrompt(for: ProfileStore.current)
        let user = CoachSwapSuggester.userPrompt(exerciseName: original, isCardio: isCardio, avoid: avoid)
        do {
            let text = try await AnthropicClient(route: route)
                .send(system: system, history: [CoachMessage(role: .user, text: user)],
                      model: .haiku, maxTokens: 300)
            let names = CoachSwapSuggester.parse(text)
            if names.isEmpty {
                aiError = "Coach didn't return usable suggestions — try again."
            } else {
                aiSwaps = names
                Haptics.selection()
            }
        } catch let error as CoachError {
            aiError = error.errorDescription ?? "Coach request failed."
        } catch {
            aiError = error.localizedDescription
        }
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
