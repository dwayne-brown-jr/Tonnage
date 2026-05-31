import SwiftUI
import SwiftData
import TonnageCore

/// "Plan Block N+1 with Coach." Hits Anthropic with the full program + lifetime PRs +
/// last block's adherence, previews the structured plan it returns with kept/swap/new
/// badges + per-exercise rationale, and on Use This Plan rewrites the program's
/// ExerciseTemplates so the next block runs on the new layout.
struct PlanBlockSheet: View {
    let currentBlockNumber: Int
    /// Called after the plan is committed to SwiftData — TrainView wires this to its
    /// existing `startNewBlock()` so currentBlock advances + week resets to 1.
    var onCommit: () -> Void

    @Query private var workouts: [LoggedWorkout]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .idle
    /// Set when the user taps "Use This Plan" — drives the confirmation dialog. Holding
    /// the plan here (rather than committing on tap) gives an explicit, reversible
    /// checkpoint before we rewrite the program.
    @State private var pendingPlan: BlockPlan?
    /// Non-nil when a SwiftData save failed; surfaced as an alert so a half-applied
    /// rewrite never passes silently.
    @State private var saveError: String?

    private enum Phase {
        case idle
        case loading
        case preview(BlockPlan)
        case error(String)
    }

    private var nextBlockNumber: Int { currentBlockNumber + 1 }
    private var program: Program? { programs.first }
    private var prs: [PRMoment] { PersonalRecords.recentPRs(in: workouts, limit: 15) }
    private var adherence: BlockAdherence? {
        guard let p = program else { return nil }
        return AdherenceEngine.computeBlock(workouts: workouts, blockNumber: currentBlockNumber,
                                            sessionsPerWeek: p.orderedSessions.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                switch phase {
                case .idle, .loading:       loadingView
                case .preview(let plan):    previewView(plan)
                case .error(let message):   errorView(message)
                }
            }
            .navigationTitle("Plan Block \(String(format: "%02d", nextBlockNumber))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
            }
        }
        .tint(.accent)
        .task { if case .idle = phase { await loadPlan() } }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Use this plan for Block \(String(format: "%02d", nextBlockNumber))?",
            isPresented: Binding(get: { pendingPlan != nil },
                                 set: { if !$0 { pendingPlan = nil } }),
            titleVisibility: .visible,
            presenting: pendingPlan
        ) { plan in
            Button("Rewrite Program", role: .destructive) { commit(plan) }
            Button("Cancel", role: .cancel) { pendingPlan = nil }
        } message: { plan in
            Text(confirmationMessage(plan))
        }
        .alert("Couldn't save", isPresented: Binding(get: { saveError != nil },
                                                     set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Loading / error

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView().tint(Color.accent).scaleEffect(1.4)
            VStack(spacing: DS.Spacing.xs) {
                Text("Coach is drafting Block \(String(format: "%02d", nextBlockNumber))")
                    .font(DSFont.title).foregroundStyle(Color.textPrimary)
                Text("Reading your PRs, adherence, and current program…")
                    .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Spacing.xl)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.danger)
            Text(message)
                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            Button { Task { await loadPlan() } } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, DS.Spacing.xl).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: Preview

    private func previewView(_ plan: BlockPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    intro(plan)
                    ForEach(plan.sessions) { sessionCard($0) }
                    disclaimer
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
            actionsBar(plan)
        }
    }

    private func intro(_ plan: BlockPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(plan.theme.uppercased())
                .font(.system(.caption, weight: .heavy).width(.condensed))
                .kerning(0.6)
                .foregroundStyle(Color.accent)
            Text(plan.summary)
                .font(DSFont.callout)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.lg)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.accent.opacity(0.30), lineWidth: DS.Stroke.hairline))
    }

    private func sessionCard(_ session: SessionPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(session.name).font(DSFont.numberSm).foregroundStyle(Color.textPrimary)
                Text("·").font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                Text(session.subtitle.uppercased())
                    .font(.system(.caption2, weight: .bold)).kerning(0.6)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { i, ex in
                    exerciseRow(ex)
                    if i < session.exercises.count - 1 {
                        Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline)
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func exerciseRow(_ ex: ExercisePlan) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            changeBadge(ex.change).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ex.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                    Spacer(minLength: DS.Spacing.sm)
                    Text(prescriptionText(ex))
                        .font(DSFont.numberSm).monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                Text(ex.rationale)
                    .font(.system(.caption2))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .swapped(let from) = ex.change {
                    Text("Replaces \(from)")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Color.accent.opacity(0.85))
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func prescriptionText(_ ex: ExercisePlan) -> String {
        ex.isCardio ? ex.repRange : "\(ex.prescribedSets)×\(ex.repRange)"
    }

    @ViewBuilder private func changeBadge(_ change: PlanChange) -> some View {
        switch change {
        case .kept:
            Image(systemName: "equal.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.textTertiary)
        case .swapped:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
        case .new:
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.success)
        }
    }

    private var disclaimer: some View {
        Text("Committing rewrites the program template. Past logged workouts keep their original exercise names — only future weeks adopt the new plan.")
            .font(.system(.caption2))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, DS.Spacing.sm)
    }

    private func actionsBar(_ plan: BlockPlan) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Button { Task { await loadPlan() } } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                    .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { pendingPlan = plan } label: {
                Text("Use This Plan")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline) }
    }

    // MARK: Network

    private func loadPlan() async {
        guard let key = CoachKey.resolved else {
            phase = .error("Add your Anthropic API key in Settings to plan with Coach.")
            return
        }
        phase = .loading
        let system = CoachBlockPlanner.systemPrompt(for: ProfileStore.current)
        let user = CoachBlockPlanner.userPrompt(
            currentBlockNumber: currentBlockNumber,
            program: program,
            prs: prs,
            adherence: adherence,
            readinessAvg: nil
        )
        do {
            let text = try await AnthropicClient(apiKey: key).send(
                system: system,
                history: [CoachMessage(role: .user, text: user)],
                model: .opus,
                maxTokens: 4096
            )
            if let plan = CoachBlockPlanner.parse(response: text) {
                phase = .preview(plan)
                Haptics.selection()
            } else {
                phase = .error("Coach returned an unexpected format. Tap Try Again.")
            }
        } catch let error as CoachError {
            phase = .error(error.errorDescription ?? "Coach call failed.")
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: Commit

    /// Program sessions the plan didn't include (matched by name). These keep their old
    /// layout on commit rather than being silently dropped — we call them out so the user
    /// isn't surprised that one session stayed put.
    private func unmatchedSessionNames(_ plan: BlockPlan) -> [String] {
        guard let program else { return [] }
        let planNames = Set(plan.sessions.map(\.name))
        return program.orderedSessions.map(\.name).filter { !planNames.contains($0) }
    }

    private func confirmationMessage(_ plan: BlockPlan) -> String {
        var msg = "This rewrites your program's exercises to the new layout. Past logged workouts are untouched, but the change to the template can't be undone."
        let unmatched = unmatchedSessionNames(plan)
        if !unmatched.isEmpty {
            let list = unmatched.joined(separator: ", ")
            msg += "\n\nHeads up: \(list) \(unmatched.count == 1 ? "wasn't" : "weren't") in the plan, so \(unmatched.count == 1 ? "it keeps" : "they keep") the current exercises."
        }
        return msg
    }

    /// Apply the plan to the existing Program: delete each SessionTemplate's
    /// ExerciseTemplates and rewrite from the proposal. Past LoggedExercise snapshots
    /// keep their original names via SwiftData's nullify rule on the template inverse.
    /// On a save failure we roll back so the program is never left half-rewritten.
    private func commit(_ plan: BlockPlan) {
        guard let program else { return }
        pendingPlan = nil
        let plansByName = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.name, $0) })

        for session in program.orderedSessions {
            guard let proposal = plansByName[session.name] else { continue }
            session.subtitle = proposal.subtitle
            for old in session.orderedExercises { context.delete(old) }
            for (idx, e) in proposal.exercises.enumerated() {
                let t = ExerciseTemplate(
                    name: e.name,
                    prescribedSets: e.prescribedSets,
                    repRange: e.repRange,
                    rpeTarget: e.rpeTarget,
                    notes: e.notes,
                    isCompound: e.isCompound,
                    isCardio: e.isCardio,
                    sortOrder: idx
                )
                t.session = session
                context.insert(t)
            }
        }

        do {
            try context.save()
            Haptics.success()
            onCommit()
            dismiss()
        } catch {
            context.rollback()   // discard the in-memory rewrite so nothing is half-applied
            Haptics.warning()
            saveError = "The new plan couldn't be saved (\(error.localizedDescription)). Your current program is unchanged — try again."
        }
    }
}
