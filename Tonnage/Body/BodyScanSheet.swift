import SwiftUI
import SwiftData
import UIKit
import TonnageCore

/// Photo → AI measurement estimate → review/adjust → save. Honest by design: the user
/// sees a consent step (the photo leaves the device for analysis), the numbers are
/// labeled estimates, and nothing is written until they confirm.
struct BodyScanSheet: View {
    /// Downscaled JPEG bytes of the chosen photo.
    let imageData: Data
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .consent
    @State private var ordered: [MeasurementType] = []
    @State private var values: [MeasurementType: Double] = [:]
    @State private var confidence = "low"
    @State private var note = ""

    private enum Phase: Equatable { case consent, loading, review, error(String) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                switch phase {
                case .consent:        consentView
                case .loading:        loadingView
                case .review:         reviewView
                case .error(let m):   errorView(m)
                }
            }
            .navigationTitle("Estimate from Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
            }
        }
        .tint(.accent)
        .preferredColorScheme(.dark)
    }

    private var thumbnail: some View {
        Group {
            if let ui = UIImage(data: imageData) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Color.surfaceElevated2
            }
        }
        .frame(maxWidth: .infinity).frame(height: 240).clipped()
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: Consent

    private var consentView: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                thumbnail
                VStack(spacing: DS.Spacing.xs) {
                    Text("AI measurement estimate").font(DSFont.title).foregroundStyle(Color.textPrimary)
                    Text("Tonnage will send this photo to Anthropic to estimate your measurements. These are rough visual estimates — you'll review and adjust each one, and nothing is saved until you confirm. The photo isn't stored unless you add it as a progress photo separately.")
                        .font(DSFont.callout).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await analyze() } } label: {
                    Label("Analyze Photo", systemImage: "sparkles")
                        .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Uses the AI coach (and the shared key if you haven't added your own).")
                    .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView().tint(Color.accent).scaleEffect(1.4)
            Text("Reading your photo…").font(DSFont.callout).foregroundStyle(Color.textSecondary)
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    HStack(spacing: DS.Spacing.sm) {
                        Text("CONFIDENCE").dsLabel()
                        Text(confidence.capitalized)
                            .font(.system(.caption, weight: .bold)).foregroundStyle(confidenceColor)
                            .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 3)
                            .background(Capsule().fill(confidenceColor.opacity(0.15)))
                        Spacer()
                    }
                    Text(note.isEmpty ? "Rough estimates from one photo — adjust to match a tape measurement, then save." : note)
                        .font(DSFont.caption).foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(ordered) { estimateRow($0) }
                    }

                    Text("These are estimates, not a substitute for a tape measure. You can edit any value before saving.")
                        .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
            saveBar
        }
    }

    private func estimateRow(_ type: MeasurementType) -> some View {
        HStack {
            Text(type.label).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Spacer()
            StepperField(value: valueBinding(type),
                         step: type == .bodyFat ? 0.1 : 0.25,
                         range: 0...(type == .bodyFat ? 70 : 90),
                         unit: type.unit, isDecimal: true)
        }
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var saveBar: some View {
        Button { commit() } label: {
            Text("Save \(savableCount) Measurement\(savableCount == 1 ? "" : "s")")
                .font(.system(.headline, weight: .bold)).foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(savableCount == 0)
        .opacity(savableCount == 0 ? 0.5 : 1)
        .padding(DS.Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: DS.Stroke.hairline) }
    }

    // MARK: Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.danger)
            Text(message).font(DSFont.callout).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, DS.Spacing.xl)
            Button { phase = .consent } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                    .padding(.horizontal, DS.Spacing.xl).padding(.vertical, DS.Spacing.md)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: State helpers

    private var confidenceColor: Color {
        switch confidence.lowercased() {
        case "high":   return Color.success
        case "medium": return Color.accent
        default:       return Color.textTertiary
        }
    }

    private var savableCount: Int { ordered.filter { (values[$0] ?? 0) > 0 }.count }

    private func valueBinding(_ t: MeasurementType) -> Binding<Double> {
        Binding(get: { values[t] ?? 0 }, set: { values[t] = $0 })
    }

    // MARK: Network + commit

    private func analyze() async {
        guard let key = CoachKey.resolved else {
            phase = .error("Add your Anthropic API key in Settings to use photo estimates.")
            return
        }
        guard SharedKeyQuota.hasRemaining else {
            phase = .error(SharedKeyQuota.limitMessage)
            return
        }
        phase = .loading
        let system = BodyScanEstimator.systemPrompt(for: ProfileStore.current)
        let user = BodyScanEstimator.userPrompt(for: ProfileStore.current)
        do {
            let text = try await AnthropicClient(apiKey: key).sendVision(
                system: system, userText: user,
                jpegBase64: imageData.base64EncodedString(),
                model: .opus, maxTokens: 1024
            )
            guard let result = BodyScanEstimator.parse(response: text) else {
                phase = .error("Couldn't read estimates from that photo. Try a clearer, full-body shot in fitted clothing.")
                return
            }
            ordered = result.estimates.map(\.type)
            values = Dictionary(result.estimates.map { ($0.type, $0.value) }, uniquingKeysWith: { a, _ in a })
            confidence = result.confidence
            note = result.note
            SharedKeyQuota.recordUse()
            phase = .review
            Haptics.selection()
        } catch let error as CoachError {
            phase = .error(error.errorDescription ?? "Analysis failed.")
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func commit() {
        for type in ordered {
            guard let v = values[type], v > 0 else { continue }
            context.insert(BodyMeasurement(type: type, value: v, date: .now))
        }
        try? context.save()
        Haptics.success()
        onSaved()
        dismiss()
    }
}
