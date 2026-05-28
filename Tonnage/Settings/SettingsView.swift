import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TonnageCore

/// SETTINGS: AI coach (key + model), Apple Health, rest-timer defaults, and data export/import.
struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [LoggedWorkout]
    @Query private var activities: [Activity]

    @AppStorage("rest.compound") private var compoundRest = 180
    @AppStorage("rest.isolation") private var isolationRest = 75
    @AppStorage("coach.model") private var coachModelRaw = CoachModel.haiku.rawValue

    @State private var connecting = false
    @State private var apiKeyInput = ""
    @State private var keySet = Keychain.read(Keychain.apiKeyAccount) != nil

    @State private var exportDoc: JSONBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showResetConfirm = false
    @State private var importMessage: String?
    @State private var showHowItWorks = false
    @State private var showProfileEditor = false

    @AppStorage(ProfileStore.Key.name) private var profileName = ""
    @AppStorage(ProfileStore.Key.goal) private var profileGoalRaw = TrainingGoal.recomp.rawValue
    @AppStorage(ProfileStore.Key.experience) private var profileExperienceRaw = ExperienceLevel.returning.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        profileCard
                        coachCard
                        healthCard
                        restTimerCard
                        howItWorksCard
                        dataCard
#if DEBUG
                        debugCard
#endif
                        aboutCard
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.accent)
        .onChange(of: compoundRest) { _, _ in PhoneConnectivity.shared.pushContext() }
        .onChange(of: isolationRest) { _, _ in PhoneConnectivity.shared.pushContext() }
        .task { await health.importExternalWorkouts(into: modelContext) }
        .fileExporter(isPresented: $showExporter, document: exportDoc,
                      contentType: .json, defaultFilename: "tonnage-backup") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fullScreenCover(isPresented: $showHowItWorks) {
            OnboardingView(onFinish: { showHowItWorks = false }, finishTitle: "Done")
        }
        .sheet(isPresented: $showProfileEditor) {
            ProfileSetupView(onFinish: { showProfileEditor = false }, finishTitle: "Done")
        }
        .confirmationDialog("Reset all logged data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) {
                resetLoggedData(in: modelContext)
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every logged workout and activity. Your Block 01 program stays. This can't be undone.")
        }
    }

    // MARK: Data (export / import / reset)

    private var dataCard: some View {
        card {
            Label("Data", systemImage: "externaldrive.fill")
                .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)

            HStack {
                Text("\(workouts.count) workouts · \(activities.count) activities").dsLabel()
                Spacer()
            }

            HStack(spacing: DS.Spacing.sm) {
                dataButton("Export", systemImage: "square.and.arrow.up") {
                    let backup = makeBackup(workouts: workouts, activities: activities)
                    if let data = try? backup.encoded() {
                        exportDoc = JSONBackupDocument(data: data)
                        showExporter = true
                    }
                }
                dataButton("Import", systemImage: "square.and.arrow.down") { showImporter = true }
            }

            Button(role: .destructive) { showResetConfirm = true } label: {
                Text("Reset All Data")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                    .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)

            if let importMessage {
                Text(importMessage).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func dataButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url), let backup = BackupData.decoded(from: data) else {
            importMessage = "Couldn't read that backup file."
            return
        }
        applyBackup(backup, to: modelContext)
        importMessage = "Imported \(backup.workouts.count) workouts · \(backup.activities.count) activities."
        Haptics.success()
    }

    private var header: some View { TonnageHeader("SETTINGS") }

    // MARK: AI Coach

    private var coachCard: some View {
        card {
            HStack {
                Label("AI Coach", systemImage: "brain.head.profile")
                    .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text(keySet ? "Key Set" : "No Key")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(keySet ? Color.success : Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 3)
                    .background(Capsule().fill(Color.surfaceElevated2))
            }

            // Model
            HStack {
                Text("Model").dsLabel()
                Spacer()
                Picker("Model", selection: $coachModelRaw) {
                    ForEach(CoachModel.allCases) { m in Text(m.label).tag(m.rawValue) }
                }
                .pickerStyle(.menu)
                .tint(Color.accent)
            }

            // API key
            Text("Anthropic API Key").dsLabel()
            SecureField(keySet ? "Enter a new key to replace" : "sk-ant-…", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(DSFont.mono)
                .foregroundStyle(Color.textPrimary)
                .padding(DS.Spacing.md)
                .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            HStack(spacing: DS.Spacing.sm) {
                Button {
                    Keychain.save(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.apiKeyAccount)
                    apiKeyInput = ""
                    keySet = true
                    Haptics.success()
                } label: {
                    Text("Save Key").font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                if keySet {
                    Button {
                        Keychain.delete(Keychain.apiKeyAccount)
                        keySet = false
                        Haptics.warning()
                    } label: {
                        Text("Remove").font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.danger)
                            .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Stored in the Keychain on this device only — never in plain settings.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: Apple Health

    private var healthCard: some View {
        card {
            HStack {
                Label("Apple Health", systemImage: "heart.fill")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                statusPill
            }

            if !health.isAvailable {
                Text("Health data isn't available on this device.")
                    .font(DSFont.callout).foregroundStyle(Color.textSecondary)
            } else if health.hasRequested {
                recoveryReadout
                connectButton(title: "Refresh from Health")
            } else {
                Text("Connect to sync workouts and read your bodyweight, sleep, and resting heart rate.")
                    .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                connectButton(title: "Connect Apple Health")
            }
        }
    }

    private var statusPill: some View {
        let connected = health.hasRequested && health.isAvailable
        return Text(connected ? "Connected" : "Off")
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(connected ? Color.success : Color.textTertiary)
            .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 3)
            .background(Capsule().fill(Color.surfaceElevated2))
    }

    private var recoveryReadout: some View {
        HStack(spacing: DS.Spacing.sm) {
            readout(value: health.bodyweight.last.map { "\(CoachEngine.fmt($0.pounds))" } ?? "—", unit: "lb", label: "Weight")
            divider
            readout(value: health.latestRestingHR.map { "\(Int($0))" } ?? "—", unit: "bpm", label: "Rest HR")
            divider
            readout(value: health.lastNightSleepHours.map { String(format: "%.1f", $0) } ?? "—", unit: "hr", label: "Sleep")
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func readout(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(DSFont.number).foregroundStyle(Color.textPrimary)
                Text(unit).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            Text(label).font(.system(.caption2, weight: .semibold)).textCase(.uppercase).foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func connectButton(title: String) -> some View {
        Button {
            connecting = true
            Task {
                await health.requestAuthorization()
                await health.importExternalWorkouts(into: modelContext)
                connecting = false
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                if connecting { ProgressView().tint(Color.onAccent) }
                Text(title).font(.system(.subheadline, weight: .bold))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(connecting)
    }

    // MARK: Rest timer

    private var restTimerCard: some View {
        card {
            Label("Rest Timer", systemImage: "timer")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            stepperRow(label: "Compound", seconds: $compoundRest)
            stepperRow(label: "Isolation", seconds: $isolationRest)
        }
    }

    private func stepperRow(label: String, seconds: Binding<Int>) -> some View {
        HStack {
            Text(label).dsLabel()
            Spacer()
            TimeStepperField(seconds: seconds, step: 15)
        }
    }

    // MARK: Athlete profile

    private var profileCard: some View {
        card {
            Button {
                Haptics.impact(.light)
                showProfileEditor = true
            } label: {
                HStack {
                    Label("Athlete Profile", systemImage: "person.crop.circle.fill")
                        .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            Text(profileSummary)
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }

    private var profileSummary: String {
        let name = profileName.trimmingCharacters(in: .whitespaces)
        let goal = TrainingGoal(rawValue: profileGoalRaw)?.label ?? "Recomp"
        let experience = ExperienceLevel(rawValue: profileExperienceRaw)?.label ?? "Returning"
        let who = name.isEmpty ? "Set your name" : name
        return "\(who) · \(goal) · \(experience) — personalizes your coach."
    }

    // MARK: How it works

    private var howItWorksCard: some View {
        card {
            Button {
                Haptics.impact(.light)
                showHowItWorks = true
            } label: {
                HStack {
                    Label("How Tonnage Works", systemImage: "questionmark.circle.fill")
                        .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            Text("The split, the 5-week block, and how your weights get suggested.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }

#if DEBUG
    // MARK: Debug (never in release builds)

    private var debugCard: some View {
        card {
            Label("Debug", systemImage: "ladybug.fill")
                .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)

            Toggle(isOn: Binding(
                get: { health.isDemoRecovery },
                set: { on in Task { await health.setDemoRecovery(on); Haptics.selection() } }
            )) {
                Text("Demo recovery data").font(DSFont.callout).foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accent)

            Text("Simulator-only: serves sample HRV / resting HR / sleep so the Readiness card and Recovery charts populate. Compiled out of release builds.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }
#endif

    // MARK: About

    private var aboutCard: some View {
        card {
            HStack {
                Text("Version").dsLabel()
                Spacer()
                Text(Self.versionString).font(DSFont.numberSm).foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// Read from the bundle so the About row always tracks the archived build —
    /// no hand-edits when CFBundleShortVersionString / CFBundleVersion change.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = (info?["CFBundleShortVersionString"] as? String) ?? "—"
        let b = (info?["CFBundleVersion"] as? String) ?? "—"
        return "Block 01 · v\(v) (\(b))"
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md, content: content)
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private var divider: some View { Rectangle().fill(Color.hairline).frame(width: DS.Stroke.hairline, height: 28) }
}

/// Wraps backup JSON for `.fileExporter`.
struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(HealthKitManager())
        .modelContainer(TonnageStore.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
