import SwiftUI
import SwiftData
import TonnageCore

/// COACH: chat with the AI coach. Builds full live context (program + logs +
/// HealthKit recovery) into the system prompt on each send.
struct CoachView: View {
    @Query private var workouts: [LoggedWorkout]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context

    @State private var vm = CoachViewModel()
    @State private var input = ""
    @AppStorage("coach.model") private var modelRaw = CoachModel.haiku.rawValue
    // Mirror of the TRAIN screen's current selection (written by TrainView) so the coach
    // can answer about the exact session/day the athlete is looking at.
    @AppStorage("train.focusWeek") private var focusWeek = 1
    @AppStorage("train.focusSession") private var focusSession = ""
    @AppStorage("train.focusDayType") private var focusDayType = DayType.lift.rawValue
    @FocusState private var inputFocused: Bool

    private var model: CoachModel { CoachModel(rawValue: modelRaw) ?? .haiku }

    private let suggestions = [
        "How did my week look?",
        "Should I push bench this week?",
        "Slept badly — adjust today?"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    transcript
                    inputBar
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.accent)
        .task { vm.configure(context) }
    }

    // MARK: Header

    private var header: some View {
        TonnageHeader("COACH") { modelMenu }
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $modelRaw) {
                ForEach(CoachModel.allCases) { m in Text(m.label).tag(m.rawValue) }
            }
            if !vm.messages.isEmpty {
                Divider()
                Button(role: .destructive) { vm.clear() } label: { Label("Clear Chat", systemImage: "trash") }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 11, weight: .bold))
                Text(model == .haiku ? "Fast" : "Deep").font(.system(.caption, weight: .bold))
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 6)
            .background(Capsule().fill(Color.surfaceElevated2))
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.md) {
                    if vm.messages.isEmpty { emptyState }
                    ForEach(vm.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(.move(edge: message.role == .user ? .trailing : .leading).combined(with: .opacity))
                    }
                    if vm.isSending {
                        TypingBubble().id("typing")
                    }
                    if let error = vm.errorText {
                        errorBanner(error)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(DS.Spacing.lg)
                .animation(DS.spring, value: vm.messages.count)
                .animation(DS.spring, value: vm.isSending)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in withAnimation(DS.spring) { proxy.scrollTo("bottom") } }
            .onChange(of: vm.isSending) { _, sending in if sending { withAnimation(DS.spring) { proxy.scrollTo("bottom") } } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
            VStack(spacing: DS.Spacing.xs) {
                Text("Your Coach").font(DSFont.title).foregroundStyle(Color.textPrimary)
                Text(vm.hasKey
                     ? "Ask about your week, a swap, or how to train around your recovery."
                     : "Add your Anthropic API key in Settings, then ask away.")
                    .font(DSFont.callout).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            }
            if vm.usingSharedKey {
                Text(vm.quotaRemaining > 0
                     ? "\(vm.quotaRemaining) free Coach messages left today · add your own key in Settings for unlimited"
                     : "Out of free Coach messages today · add your own key in Settings for unlimited")
                    .font(DSFont.caption).foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if vm.hasKey {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { send(s) } label: {
                            Text(s).font(.system(.subheadline, weight: .medium)).foregroundStyle(Color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Spacing.md)
                                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.xxl)
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.danger)
                Text(text).font(DSFont.caption).foregroundStyle(Color.textSecondary)
            }
            // Don't leave a failed turn stranded — let them re-send the last message.
            if vm.canRetry {
                Button {
                    Task { await vm.retryLast(system: systemContext(), model: model) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(.caption, weight: .bold)).foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            TextField("Ask your coach…", text: $input, axis: .vertical)
                .font(DSFont.body)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))

            Button { send(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? Color.accent : Color.surfaceElevated2))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline) }
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isSending }

    private func send(_ text: String) {
        let toSend = text
        input = ""
        inputFocused = false
        Task { await vm.send(toSend, system: systemContext(), model: model) }
    }

    private func systemContext() -> String {
        let bw = health.bodyweight
        let recovery = CoachRecovery(
            bodyweightLb: bw.last?.pounds,
            bodyweightChangeLb: bw.count >= 2 ? (bw.last!.pounds - bw.first!.pounds) : nil,
            restingHR: health.latestRestingHR,
            hrvMs: health.latestHRV,
            sleepHours: health.lastNightSleepHours
        )
        let focusDay = DayType(rawValue: focusDayType) ?? .lift
        let context = CoachContext.build(program: programs.first, currentWeek: focusWeek,
                                         recentWorkouts: workouts, activities: activities,
                                         recovery: recovery, readiness: health.currentReadiness(),
                                         focusSession: focusSession.isEmpty ? nil : focusSession,
                                         focusDay: focusDay,
                                         maxWorkouts: 12, maxActivities: 8)
        return CoachContext.systemPrompt(for: ProfileStore.current, split: ProfileStore.split) + "\n\n" + context
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: CoachMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: DS.Spacing.xl) }
            bubble
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(isUser ? Color.accent : Color.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .strokeBorder(isUser ? Color.clear : Color.hairline, lineWidth: DS.Stroke.hairline)
                )
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: DS.Spacing.xl) }
        }
    }

    @ViewBuilder private var bubble: some View {
        if isUser {
            // User text is plain — render it verbatim on the accent bubble.
            Text(message.text)
                .font(DSFont.body)
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Coach replies are markdown — render bold/bullets/tables properly.
            CoachMarkdownText(text: message.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TypingBubble: View {
    @State private var t = 0.0
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.textSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * abs(sin(t + Double(i) * 0.7)))
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            Spacer(minLength: DS.Spacing.xl)
        }
        .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { t = .pi * 2 } }
    }
}

#Preview("Coach") {
    CoachView()
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
