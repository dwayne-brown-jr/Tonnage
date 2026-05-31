import SwiftUI
import WatchKit
import TonnageCore

/// Crown-driven set logging: spin the Digital Crown for weight, tap for reps,
/// log the set (starts the rest timer), and advance.
struct WatchSetLogger: View {
    let model: WatchSessionModel
    let exerciseIndex: Int
    let rest: WatchRestTimer

    @Environment(\.dismiss) private var dismiss
    @State private var setIndex = 0
    @State private var weight = 0.0
    @State private var reps = 0
    @FocusState private var crownFocused: Bool

    private var exercise: WatchSessionModel.Exercise { model.exercises[exerciseIndex] }
    private var isLastSet: Bool { setIndex + 1 >= exercise.sets.count }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                Text("SET \(setIndex + 1) / \(exercise.sets.count)")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)

                // Weight — tappable −/+ (step by 5 lb), with the Digital Crown as a
                // power-user shortcut. Without the buttons, sweaty fingers or a quick
                // glance had no obvious way to adjust weight at all.
                HStack(spacing: DS.Spacing.md) {
                    crownButton("minus") { weight = max(0, weight - 5) }
                    Text("\(Int(weight))")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.accent)
                        .focusable()
                        .focused($crownFocused)
                        .digitalCrownRotation($weight, from: 0, through: 2000, by: 5,
                                              sensitivity: .low, isContinuous: false)
                        .frame(minWidth: 80)
                    crownButton("plus") { weight = min(2000, weight + 5) }
                }
                Text("LB").font(.system(.caption2, weight: .semibold)).foregroundStyle(.secondary)

                // Reps — steppers
                HStack(spacing: DS.Spacing.md) {
                    crownButton("minus") { reps = max(0, reps - 1) }
                    Text("\(reps)").font(.system(.title2, weight: .bold).monospacedDigit()).frame(minWidth: 40)
                    crownButton("plus") { reps += 1 }
                }
                Text("REPS").font(.system(.caption2, weight: .semibold)).foregroundStyle(.secondary)

                Button(action: logSet) {
                    Text(isLastSet ? "Log · Finish Exercise" : "Log Set")
                        .font(.system(.body, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.accent)
                .padding(.top, DS.Spacing.xs)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Resume at the next set that hasn't been logged (on the phone OR the watch).
            // Without this we'd default to set 1 and a "Log Set" tap would silently
            // overwrite already-completed work. If every set is done, sit on the last
            // one so a correction is still possible.
            setIndex = exercise.sets.firstIndex(where: { !$0.completed })
                ?? max(0, exercise.sets.count - 1)
            crownFocused = true
            load()
        }
    }

    private func crownButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .bold)) }
            .buttonStyle(.bordered)
            .tint(.gray)
    }

    private func load() {
        guard exercise.sets.indices.contains(setIndex) else { return }
        weight = exercise.sets[setIndex].weight
        reps = exercise.sets[setIndex].reps
    }

    private func logSet() {
        guard model.exercises.indices.contains(exerciseIndex),
              model.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        model.exercises[exerciseIndex].sets[setIndex].weight = weight
        model.exercises[exerciseIndex].sets[setIndex].reps = reps
        model.exercises[exerciseIndex].sets[setIndex].completed = true

        if !exercise.isCardio {
            let compound = UserDefaults.standard.object(forKey: "rest.compound") as? Int ?? 180
            let isolation = UserDefaults.standard.object(forKey: "rest.isolation") as? Int ?? 75
            rest.start(seconds: exercise.isCompound ? compound : isolation)
        }
        WKInterfaceDevice.current().play(.success)
        WatchConnectivityClient.shared.syncLive(model.payload())   // auto-sync to phone

        if isLastSet {
            dismiss()
        } else {
            setIndex += 1
            load()
        }
    }
}
