import SwiftUI
import WatchKit
import TonnageCore

/// Active watch session: live HR + volume header, the rest-timer ring, the exercise
/// list, and finish (which ends the HKWorkoutSession and syncs to the phone).
struct WatchSessionView: View {
    let session: SessionTemplate
    let week: Int

    @Environment(\.dismiss) private var dismiss
    @State private var model: WatchSessionModel
    @State private var workout = WatchWorkoutManager()
    @State private var rest = WatchRestTimer()

    init(session: SessionTemplate, week: Int, existing: WorkoutPayload? = nil) {
        self.session = session
        self.week = week
        let block = UserDefaults.standard.object(forKey: "currentBlock") as? Int ?? 1
        _model = State(initialValue: WatchSessionModel(session: session, block: block, week: week, existing: existing))
    }

    var body: some View {
        List {
            Section { statsHeader }
            if !workout.isRunning {
                Section {
                    Button(action: startWorkout) {
                        Label("Start Workout", systemImage: "play.circle.fill")
                    }
                    .tint(.accent)
                } footer: {
                    Text("Optional — tracks heart rate and closes your rings. You can log sets without it.")
                }
            }
            if rest.isRunning { Section { restRow } }
            Section("Exercises") {
                ForEach(Array(model.exercises.enumerated()), id: \.element.id) { index, exercise in
                    NavigationLink {
                        WatchSetLogger(model: model, exerciseIndex: index, rest: rest)
                    } label: {
                        exerciseRow(exercise)
                    }
                }
            }
            Section {
                Button(role: .destructive, action: finish) {
                    Label("Finish Session", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .navigationTitle(session.name)
    }

    /// Explicit opt-in — a live workout (heart rate + rings) only starts when the
    /// athlete asks for it, never just from opening the session screen.
    private func startWorkout() {
        WKInterfaceDevice.current().play(.start)
        Task {
            await workout.requestAuthorization()
            workout.start()
        }
    }

    private var statsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "—")")
                    .font(.title3.monospacedDigit()).foregroundStyle(.red)
                Label("BPM", systemImage: "heart.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(model.totalVolume))").font(.title3.monospacedDigit()).foregroundStyle(Color.accent)
                Text("\(model.completedSets) SETS · LB").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private var restRow: some View {
        HStack {
            Image(systemName: "timer").foregroundStyle(Color.accent)
            Text("Rest \(rest.remaining)s").font(.headline.monospacedDigit())
            Spacer()
            Button("Skip") { rest.skip() }.font(.caption).buttonStyle(.borderless).tint(.accent)
        }
    }

    private func exerciseRow(_ exercise: WatchSessionModel.Exercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name).font(.headline).lineLimit(1)
                Text(exercise.isCardio ? exercise.repRange : "\(exercise.prescribedSets)×\(exercise.repRange)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(exercise.completedCount)/\(exercise.sets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(exercise.isDone ? .green : .secondary)
        }
    }

    private func finish() {
        workout.end()
        WatchConnectivityClient.shared.send(model.payload())
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}
