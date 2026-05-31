import SwiftUI
import SwiftData
import Charts
import PhotosUI
import UIKit
import TonnageCore

/// BODY: tape-measure tracking (and, in a follow-up, progress photos). Bodyweight lives
/// on the DATA tab via HealthKit; this covers the circumferences + body-fat % Health
/// doesn't. Pushed from the DATA tab.
struct BodyView: View {
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @Environment(\.modelContext) private var context
    @AppStorage("photos.iCloudSync") private var iCloudSync = false

    @State private var showEntry = false
    @State private var selectedType: MeasurementType?
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewerPhoto: ProgressPhoto?
    @State private var scanPickerItem: PhotosPickerItem?
    @State private var scanImage: ScanImage?

    private var latest: [BodyMetrics.Latest] { BodyMetrics.latest(measurements) }
    private var tracked: [MeasurementType] { BodyMetrics.trackedTypes(in: measurements) }
    private var lastValues: [MeasurementType: Double] {
        Dictionary(latest.map { ($0.type, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    if measurements.isEmpty {
                        measurementsEmpty
                    } else {
                        latestGrid
                        trendCard
                    }
                    estimateButton
                    photosCard
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.impact(.light); showEntry = true } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                }
                .tint(.accent)
                .accessibilityLabel("Log measurement")
            }
        }
        .tint(.accent)
        .sheet(isPresented: $showEntry) {
            BodyMeasurementSheet(lastValues: lastValues) { type, value, date in
                context.insert(BodyMeasurement(type: type, value: value, date: date))
                try? context.save()
                Haptics.success()
            }
        }
        .fullScreenCover(item: $viewerPhoto) { photo in
            ProgressPhotoViewer(photo: photo) { deletePhoto(photo) }
        }
        .sheet(item: $scanImage) { img in
            BodyScanSheet(imageData: img.data)
        }
        .onChange(of: pickerItem) { _, item in importPickedPhoto(item) }
        .onChange(of: scanPickerItem) { _, item in loadScanImage(item) }
        .onAppear { syncSelection() }
        .onChange(of: tracked) { _, _ in syncSelection() }
    }

    // MARK: Estimate from photo

    private var estimateButton: some View {
        PhotosPicker(selection: $scanPickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimate from Photo")
                        .font(.system(.headline, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Text("AI reads a photo into rough measurements you confirm")
                        .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
        }
        .buttonStyle(.plain)
    }

    private func loadScanImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { scanPickerItem = nil }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let encoded = ProgressPhotoStore.encode(raw) else { return }
            scanImage = ScanImage(data: encoded)
        }
    }

    // MARK: Photo import / delete

    private func importPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { pickerItem = nil }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let encoded = ProgressPhotoStore.encode(raw) else { return }
            let photo: ProgressPhoto
            if iCloudSync {
                photo = ProgressPhoto(date: .now, syncedData: encoded)
            } else if let filename = ProgressPhotoStore.writeLocal(encoded) {
                photo = ProgressPhoto(date: .now, localFilename: filename)
            } else {
                return
            }
            context.insert(photo)
            try? context.save()
            Haptics.success()
        }
    }

    private func deletePhoto(_ photo: ProgressPhoto) {
        if let name = photo.localFilename { ProgressPhotoStore.deleteLocal(name) }
        context.delete(photo)
        try? context.save()
        Haptics.warning()
        viewerPhoto = nil
    }

    private func syncSelection() {
        if selectedType == nil || !(tracked.contains(selectedType ?? .waist)) {
            selectedType = tracked.first
        }
    }

    // MARK: Latest grid

    private var latestGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.md),
                            GridItem(.flexible(), spacing: DS.Spacing.md)],
                  spacing: DS.Spacing.md) {
            ForEach(latest) { metricCard($0) }
        }
    }

    private func metricCard(_ m: BodyMetrics.Latest) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(m.type.label.uppercased())
                .font(.system(.caption2, weight: .bold)).kerning(0.6)
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmt(m.value)).font(DSFont.number).monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(m.type.unit).font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            }
            deltaChip(m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    @ViewBuilder private func deltaChip(_ m: BodyMetrics.Latest) -> some View {
        if let d = m.delta, abs(d) >= 0.01 {
            let improving = (d < 0) == m.type.lowerIsBetter
            HStack(spacing: 2) {
                Image(systemName: d < 0 ? "arrow.down" : "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                Text(fmt(abs(d))).font(.system(.caption2, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(improving ? Color.success : Color.textTertiary)
        } else {
            Text(m.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: Trend

    @ViewBuilder private var trendCard: some View {
        let type = selectedType ?? tracked.first ?? .waist
        let series = BodyMetrics.series(of: type, in: measurements)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Trend").dsLabel()
                Spacer()
                typePicker(current: type)
            }
            if series.count >= 2 {
                Chart(series) { p in
                    AreaMark(x: .value("Date", p.date), y: .value(type.unit, p.value))
                        .foregroundStyle(.linearGradient(colors: [Color.accent.opacity(0.30), Color.accent.opacity(0.02)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", p.date), y: .value(type.unit, p.value))
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date), y: .value(type.unit, p.value))
                        .foregroundStyle(Color.accent).symbolSize(50)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.hairline)
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.hairline)
                        AxisValueLabel().foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(height: 180)
            } else {
                Text("Log \(type.label.lowercased()) at least twice to see a trend.")
                    .font(DSFont.caption).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Spacing.lg)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private func typePicker(current: MeasurementType) -> some View {
        Menu {
            ForEach(tracked) { t in
                Button(t.label) { selectedType = t }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(current.label).font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.textPrimary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.sm)
            .background(Color.surfaceElevated2, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Measurements empty prompt

    private var measurementsEmpty: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "ruler.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
            Text("Track your measurements").font(.system(.headline, weight: .bold)).foregroundStyle(Color.textPrimary)
            Text("Waist, arms, body fat — the recomp progress your scale weight hides.")
                .font(DSFont.caption).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            Button { Haptics.impact(.light); showEntry = true } label: {
                Label("Log a Measurement", systemImage: "plus")
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.onAccent)
                    .padding(.horizontal, DS.Spacing.lg).padding(.vertical, DS.Spacing.sm)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    // MARK: Progress photos

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Progress Photos").dsLabel()
                Spacer()
                storageMenu
            }
            if !photos.isEmpty {
                photoStrip
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(photos.isEmpty ? "Add Your First Photo" : "Add Photo", systemImage: "camera.fill")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(photos.isEmpty ? Color.onAccent : Color.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.sm)
                    .background(photos.isEmpty ? AnyShapeStyle(Color.accent) : AnyShapeStyle(Color.accent.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
            storageHint
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(photos) { thumbnail($0) }
            }
            .padding(.vertical, 2)
        }
    }

    private func thumbnail(_ photo: ProgressPhoto) -> some View {
        Button { Haptics.impact(.light); viewerPhoto = photo } label: {
            ZStack(alignment: .bottomLeading) {
                if let data = ProgressPhotoStore.data(for: photo), let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 116, height: 156).clipped()
                } else {
                    ZStack {
                        Color.surfaceElevated2
                        VStack(spacing: 4) {
                            Image(systemName: "icloud.slash").font(.system(size: 18, weight: .semibold))
                            Text("On another\ndevice").font(.system(.caption2)).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color.textTertiary)
                    }
                    .frame(width: 116, height: 156)
                }
                Text(photo.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(.caption2, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: DS.Stroke.hairline))
        }
        .buttonStyle(.plain)
    }

    private var storageMenu: some View {
        Menu {
            Picker("Storage", selection: $iCloudSync) {
                Label("On this device only", systemImage: "iphone").tag(false)
                Label("Sync with iCloud", systemImage: "icloud").tag(true)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iCloudSync ? "icloud.fill" : "iphone")
                    .font(.system(size: 10, weight: .bold))
                Text(iCloudSync ? "iCloud" : "On-device")
                    .font(.system(.caption, weight: .bold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 5)
            .background(Capsule().fill(Color.surfaceElevated2))
        }
    }

    private var storageHint: some View {
        Text(iCloudSync
             ? "iCloud: new photos sync to all your devices and survive a reinstall. Uses your iCloud storage; bytes leave this device (to your private iCloud)."
             : "On-device: most private — new photos never leave this phone. They won't appear on your other devices or survive a reinstall.")
            .font(.system(.caption2)).foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Identifiable wrapper so a picked-and-encoded scan photo can drive `.sheet(item:)`.
private struct ScanImage: Identifiable {
    let id = UUID()
    let data: Data
}

/// Single-measurement entry — pick a type, dial the value, choose the date. Prefills the
/// last recorded value for the chosen type so it's a quick adjust, not a fresh entry.
private struct BodyMeasurementSheet: View {
    let lastValues: [MeasurementType: Double]
    let onSave: (MeasurementType, Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: MeasurementType = .waist
    @State private var value: Double = 0
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    Text("Measurement").dsLabel()
                    Picker("Measurement", selection: $type) {
                        ForEach(MeasurementType.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.accent)

                    HStack {
                        Text("Value (\(type.unit))").dsLabel()
                        Spacer()
                        StepperField(value: $value, step: type == .bodyFat ? 0.1 : 0.25,
                                     range: 0...(type == .bodyFat ? 70 : 90), unit: type.unit, isDecimal: true)
                    }

                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .tint(Color.accent)
                        .foregroundStyle(Color.textPrimary)

                    Spacer()
                }
                .padding(DS.Spacing.xl)
            }
            .navigationTitle("Log Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(type, value, date); dismiss() }
                        .fontWeight(.bold).foregroundStyle(Color.accent)
                        .disabled(value <= 0)
                }
            }
            .onAppear { value = lastValues[type] ?? 0 }
            .onChange(of: type) { _, t in value = lastValues[t] ?? 0 }
        }
        .preferredColorScheme(.dark)
    }
}

/// Full-screen photo viewer with date title and a confirmed delete.
private struct ProgressPhotoViewer: View {
    let photo: ProgressPhoto
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data = ProgressPhotoStore.data(for: photo), let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFit()
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "icloud.slash").font(.system(size: 40, weight: .semibold))
                        Text("This photo is stored on another device.")
                            .font(DSFont.callout).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.textTertiary)
                    .padding(DS.Spacing.xl)
                }
            }
            .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(Color.danger)
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Photo", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the photo permanently.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Body") {
    NavigationStack {
        BodyView()
            .modelContainer(TonnageStore.makeContainer(inMemory: true))
            .preferredColorScheme(.dark)
    }
}
