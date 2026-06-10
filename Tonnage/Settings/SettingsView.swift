import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit
import TonnageCore

/// SETTINGS: AI coach (key + model), Apple Health, rest-timer defaults, and data export/import.
struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showMail = false
    @Query private var workouts: [LoggedWorkout]
    @Query private var activities: [Activity]

    @AppStorage("rest.compound") private var compoundRest = 180
    @AppStorage("rest.isolation") private var isolationRest = 75
    @AppStorage("coach.model") private var coachModelRaw = CoachModel.haiku.rawValue

    @State private var connecting = false
    @State private var apiKeyInput = ""
    @State private var keySet = Keychain.read(Keychain.apiKeyAccount) != nil
    @State private var keyError: String?
    @State private var feedbackNote: String?
    @State private var iCloudAvailable: Bool?   // nil = still checking
    @State private var reminders = TrainingReminders()

    @State private var exportDoc: JSONBackupDocument?
    @State private var showExporter = false
    @State private var csvDoc: CSVDocument?
    @State private var showCSVExporter = false
    @State private var showImporter = false
    @State private var showResetConfirm = false
    @State private var importMessage: String?
    @State private var showHowItWorks = false
    @State private var showProfileEditor = false

    @AppStorage(ProfileStore.Key.name) private var profileName = ""
    @AppStorage(ProfileStore.Key.goal) private var profileGoalRaw = TrainingGoal.recomp.rawValue
    @AppStorage(ProfileStore.Key.experience) private var profileExperienceRaw = ExperienceLevel.returning.rawValue
    @AppStorage(ProfileStore.Key.split) private var splitRaw = SplitPreset.upperLower.rawValue
    @State private var showSplitPicker = false

    private var split: SplitPreset { SplitPreset(rawValue: splitRaw) ?? .upperLower }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        profileCard
                        splitCard
                        coachCard
                        healthCard
                        restTimerCard
                        remindersCard
                        howItWorksCard
                        syncCard
                        dataCard
                        feedbackCard
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
        .task { await reminders.refreshAuthStatus() }
        .task {
            let status = try? await CKContainer(identifier: TonnageStore.cloudKitContainerID).accountStatus()
            iCloudAvailable = (status == .available)
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc,
                      contentType: .json, defaultFilename: "tonnage-backup") { result in
            switch result {
            case .success: importMessage = "Backup saved."; Haptics.success()
            case .failure: importMessage = "Backup wasn't saved."
            }
        }
        .fileExporter(isPresented: $showCSVExporter, document: csvDoc,
                      contentType: .commaSeparatedText, defaultFilename: "tonnage-workouts") { result in
            switch result {
            case .success: importMessage = "CSV saved."; Haptics.success()
            case .failure: importMessage = "CSV wasn't saved."
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fullScreenCover(isPresented: $showHowItWorks) {
            OnboardingView(onFinish: { showHowItWorks = false }, finishTitle: "Done")
                .environment(health)   // covers don't reliably inherit @Observable env
        }
        .sheet(isPresented: $showMail) {
            MailComposeView(recipient: Feedback.recipient, subject: Feedback.subject, body: Feedback.body)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showProfileEditor) {
            ProfileSetupView(onFinish: { showProfileEditor = false }, finishTitle: "Done")
        }
        .sheet(isPresented: $showSplitPicker) {
            SplitPickerSheet()
        }
        .confirmationDialog("Reset all logged data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) {
                resetLoggedData(in: modelContext)
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every logged workout and activity (your program stays). This can't be undone — export a backup first if you might want it later.")
        }
    }

    // MARK: iCloud sync status

    private var syncCard: some View {
        let on = iCloudAvailable == true
        let checking = iCloudAvailable == nil
        return card {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: on ? "checkmark.icloud.fill" : (checking ? "icloud" : "icloud.slash"))
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(on ? Color.success : Color.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(checking ? "Checking iCloud…" : (on ? "Synced via iCloud" : "iCloud is off"))
                        .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Text(on
                         ? "Your workouts and progress back up and sync across your devices automatically."
                         : "Your data is saved on this device. Turn on iCloud Drive in iOS Settings to back it up and sync across devices.")
                        .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
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
                    } else {
                        importMessage = "Couldn't prepare the backup."
                        Haptics.warning()
                    }
                }
                dataButton("Import", systemImage: "square.and.arrow.down") { showImporter = true }
            }

            // Set-level spreadsheet export — for coaches and lifters who live in Sheets.
            dataButton("Export Workouts as CSV", systemImage: "tablecells") {
                csvDoc = CSVDocument(text: CSVExport.workoutsCSV(workouts))
                showCSVExporter = true
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

            Text("Coach features send your profile, training history, recovery metrics, and (for photo estimates) your photo to Anthropic to generate replies. Nothing else leaves your device.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

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
                    let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Don't store an obviously-wrong key behind a green "Key Set".
                    guard key.hasPrefix("sk-ant-") else {
                        withAnimation(DS.spring) { keyError = "That doesn't look like an Anthropic key — they start with \"sk-ant-\"." }
                        Haptics.warning()
                        return
                    }
                    Keychain.save(key, for: Keychain.apiKeyAccount)
                    apiKeyInput = ""
                    keySet = true
                    keyError = nil
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

            if let keyError {
                Text(keyError).font(.system(.caption2)).foregroundStyle(Color.danger)
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
                Text("Reads bodyweight, sleep, HRV, resting heart rate, and — from a ring — body temperature & breathing rate; writes your workouts back. Cardio (runs, walks, rides) from other apps imports into MOVE automatically. Strength workouts logged in other apps are NOT imported — log lifts in TRAIN so they count toward progression. Recovery needs an Apple Watch or ring.")
                    .font(.system(.caption2))
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text("Connect to sync workouts and read your bodyweight, sleep, and resting heart rate.")
                    .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                connectButton(title: "Connect Apple Health")
            }
        }
    }

    private var statusPill: some View {
        // Honest three-state: Off (not connected) / No data (connected but nothing read —
        // e.g. no Apple Watch) / Connected (data flowing). Never a false green "Connected".
        let (text, color): (String, Color) =
            !(health.hasRequested && health.isAvailable) ? ("Off", Color.textTertiary)
            : health.hasRecoveryData ? ("Connected", Color.success)
            : ("No data", Color.textSecondary)
        return Text(text)
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(color)
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

    // MARK: Training reminders

    private var remindersCard: some View {
        card {
            HStack {
                Label("Training Reminders", systemImage: "bell.badge.fill")
                    .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { on in Task { await reminders.setEnabled(on); Haptics.selection() } }
                ))
                .labelsHidden()
                .tint(Color.accent)
            }

            if reminders.authDenied {
                Text("Notifications are off for Tonnage. Turn them on in iOS Settings → Notifications → Tonnage.")
                    .font(.system(.caption2)).foregroundStyle(Color.danger)
            }

            if reminders.isEnabled && !reminders.authDenied {
                HStack {
                    Text("Time").dsLabel()
                    Spacer()
                    DatePicker("", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Color.accent)
                }
                Text("Days").dsLabel()
                weekdayPicker
                Label("Set for \(reminderClock) on your selected days.", systemImage: "checkmark.circle.fill")
                    .font(.system(.caption2)).foregroundStyle(Color.success)
            }

            Text("A nudge on your training days so you don't break the chain.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }

    private var reminderClock: String {
        let d = Calendar.current.date(from: DateComponents(hour: reminders.hour, minute: reminders.minute)) ?? Date()
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: d)
    }

    /// Bridges the manager's hour/minute to a `Date` the system DatePicker can edit.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminders.hour, minute: reminders.minute)) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminders.hour = c.hour ?? 18
                reminders.minute = c.minute ?? 0
            }
        )
    }

    private var weekdayPicker: some View {
        // Calendar weekdays: 1 = Sunday … 7 = Saturday.
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: DS.Spacing.xs) {
            ForEach(1...7, id: \.self) { wd in
                let on = reminders.weekdays.contains(wd)
                Button {
                    Haptics.selection()
                    if on { reminders.weekdays.remove(wd) } else { reminders.weekdays.insert(wd) }
                } label: {
                    Text(symbols[wd - 1])
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(on ? Color.onAccent : Color.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(on ? Color.accent : Color.surfaceElevated2,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.weekdayName(wd))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private static func weekdayName(_ wd: Int) -> String {
        Calendar.current.weekdaySymbols[(wd - 1) % 7]
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

    // MARK: Training split

    private var splitCard: some View {
        card {
            Button {
                Haptics.impact(.light)
                showSplitPicker = true
            } label: {
                HStack {
                    Label("Training Split", systemImage: "square.grid.2x2.fill")
                        .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(split.label).font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            Text("\(split.daysPerWeek) days/week — tap to change. Switching rewrites your program; logged workouts are kept.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
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

            Divider().overlay(Color.hairline)

            Button {
                UserDefaults.standard.set(1, forKey: "currentBlock")
                UserDefaults.standard.set(3, forKey: "train.week")     // jump to the most recent week
                DemoData.seedTrainingData(in: modelContext)
                Task { await health.setDemoRecovery(true) }
                Haptics.success()
            } label: {
                Text("Load 3 Weeks of Demo Data")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Wipes logged data, then seeds 3 weeks of workouts (with warm-ups + progression) and a few cardio sessions into Block 01, and turns on demo recovery — so DATA, the Today card, per-muscle volume, PRs, progression, insights, and the share cards all populate.")
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }
#endif

    // MARK: Feedback

    private var feedbackCard: some View {
        card {
            Label("Feedback", systemImage: "envelope.fill")
                .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("Hit a bug or have an idea? I read everything — your version and device are attached automatically.")
                .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if MailComposeView.canSend {
                    showMail = true
                } else if let url = Feedback.mailtoURL, UIApplication.shared.canOpenURL(url) {
                    openURL(url)
                } else {
                    // No Mail app / handler — don't no-op; copy the address so they can reach me.
                    UIPasteboard.general.string = Feedback.recipient
                    withAnimation(DS.spring) { feedbackNote = "No mail app set up — copied \(Feedback.recipient) to your clipboard." }
                }
                Haptics.selection()
            } label: {
                Label("Send Feedback", systemImage: "paperplane.fill")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            if let feedbackNote {
                Text(feedbackNote).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
        }
    }

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

/// Wraps a CSV string for `.fileExporter`.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
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
