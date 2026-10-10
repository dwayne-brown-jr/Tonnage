import SwiftUI

/// Front + back body map built from faceted vector plates — the brutalist/precision
/// counterpart to an anatomy chart. Two modes: an exercise's targets (primary in accent with
/// a glow, secondary dimmed), or a heat map of per-muscle intensity (0…1).
///
/// Everything is drawn from `BodyGeometry` in a 100×200 unit space per figure, so it stays
/// crisp at any size and costs nothing in bundle weight.
public struct MuscleMapView: View {

    public enum Mode: Equatable {
        case targets(MuscleTargets)
        /// Intensity per muscle, 0…1. Missing / zero = untouched.
        case heat([Muscle: Double])
    }

    private let mode: Mode
    private let highlight: Color
    private let showsCaptions: Bool
    private let glows: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// - Parameters:
    ///   - highlight: color for worked muscles (white when placed on an accent fill).
    ///   - showsCaptions: FRONT / BACK labels under each figure.
    ///   - glows: soft bloom behind primary muscles; off for tiny thumbnails.
    public init(_ mode: Mode, highlight: Color = .accent, showsCaptions: Bool = true, glows: Bool = true) {
        self.mode = mode
        self.highlight = highlight
        self.showsCaptions = showsCaptions
        self.glows = glows
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            figure(BodyGeometry.front, caption: "Front")
            figure(BodyGeometry.back, caption: "Back")
        }
        .onAppear {
            if reduceMotion { revealed = true } else {
                withAnimation(.easeOut(duration: 0.5).delay(0.08)) { revealed = true }
            }
        }
        .animation(DS.spring, value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle map")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: Figure

    private func figure(_ regions: [BodyRegion], caption: String) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            GeometryReader { geo in
                let scale = min(geo.size.width / 100, geo.size.height / 200)
                ZStack {
                    if glows { glow(regions, scale: scale) }
                    ZStack {
                        ForEach(regions) { r in
                            UnitPolygons(polygons: r.polygons).fill(fill(for: r.muscle))
                        }
                        // Carve the grooves between plates out to transparency so the map
                        // reads correctly on any background.
                        ForEach(regions) { r in
                            UnitPolygons(polygons: r.polygons)
                                .stroke(.black, style: StrokeStyle(lineWidth: max(0.75, scale * 1.1), lineJoin: .round))
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
            }
            .aspectRatio(0.5, contentMode: .fit)
            if showsCaptions {
                Text(caption)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Bloom under the strongest muscles — the "lit from within" signature.
    private func glow(_ regions: [BodyRegion], scale: CGFloat) -> some View {
        ZStack {
            ForEach(regions) { r in
                if let m = r.muscle, intensity(of: m) >= 0.75 {
                    UnitPolygons(polygons: r.polygons).fill(highlight)
                }
            }
        }
        .blur(radius: max(2, scale * 5))
        .opacity(revealed ? 0.55 : 0)
    }

    // MARK: Color

    /// 0 = untouched, 0.6 = secondary, 1 = primary; heat mode passes its value through.
    private func intensity(of muscle: Muscle) -> Double {
        switch mode {
        case .targets(let t):
            switch t.emphasis(of: muscle) {
            case .primary:   1
            case .secondary: 0.6
            case .none:      0
            }
        case .heat(let values):
            min(max(values[muscle] ?? 0, 0), 1)
        }
    }

    private func fill(for muscle: Muscle?) -> Color {
        guard let muscle else { return Color.white.opacity(0.05) }      // head, hands, joints
        let v = revealed ? intensity(of: muscle) : 0
        guard v > 0 else { return Color.white.opacity(0.10) }           // untouched muscle
        // Ease-in so low values stay dim and the top of the range separates clearly.
        return highlight.opacity(0.18 + 0.82 * v * v)
    }

    private var accessibilityValue: String {
        switch mode {
        case .targets(let t):
            var parts = ["Primary: " + t.primary.map(\.label).joined(separator: ", ")]
            if !t.secondary.isEmpty { parts.append("Secondary: " + t.secondary.map(\.label).joined(separator: ", ")) }
            return parts.joined(separator: ". ")
        case .heat(let values):
            let worked = Muscle.allCases.filter { (values[$0] ?? 0) > 0 }
                .sorted { (values[$0] ?? 0) > (values[$1] ?? 0) }
            return worked.isEmpty ? "No muscles worked" : "Most worked: " + worked.prefix(5).map(\.label).joined(separator: ", ")
        }
    }
}

// MARK: - Geometry

struct BodyRegion: Identifiable {
    let id: String
    /// nil = non-muscle body part (head, hands, knees, feet) drawn as a dim base.
    let muscle: Muscle?
    let polygons: [[CGPoint]]
}

/// Scales unit-space (100×200) polygons into the given rect, centered.
struct UnitPolygons: Shape {
    let polygons: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 100, rect.height / 200)
        let ox = rect.midX - 50 * s, oy = rect.midY - 100 * s
        var p = Path()
        for poly in polygons where poly.count > 2 {
            p.addLines(poly.map { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) })
            p.closeSubpath()
        }
        return p
    }
}

/// Hand-authored plates for the viewer's-left half of each figure (x < 50); every plate is
/// mirrored across x = 50, so the centerline groove reads as the linea alba / spine.
enum BodyGeometry {

    typealias Half = [(CGFloat, CGFloat)]

    static let front: [BodyRegion] = [
        BodyRegion(id: "base.head", muscle: nil, polygons: [head]),
        base("neck", [[(45, 19.5), (49.4, 21), (49.4, 30.5), (44.5, 28.5)]]),
        muscle(.traps, [[(44, 23), (44.5, 28.5), (36, 31.5), (40, 28)]]),
        muscle(.sideDelts, [[(35, 31), (29, 32.5), (25.5, 37), (24.5, 44), (26.5, 47), (28, 40), (31, 35)]]),
        muscle(.frontDelts, [[(37, 31.5), (35, 31), (31, 35), (28, 40), (26.5, 47), (30, 46), (34, 40.5), (36.5, 36)]]),
        muscle(.upperChest, [[(49.4, 32), (38, 32), (36.5, 36), (35, 40.5), (49.4, 41)]]),
        muscle(.chest, [[(49.4, 42), (35, 41.5), (34, 45), (35.5, 49.5), (40, 52), (49.4, 52.5)]]),
        muscle(.biceps, [[(30.5, 47), (26.5, 48), (24, 55), (23.8, 63), (27.5, 66), (30, 59), (31, 52)]]),
        muscle(.forearms, forearm),
        base("hand", [hand]),
        muscle(.abs, [
            [(49.4, 54.5), (42, 54), (41.5, 61.5), (49.4, 62)],
            [(49.4, 63.5), (41.5, 63), (41.5, 70.5), (49.4, 71)],
            [(49.4, 72.5), (41.5, 72), (42, 79.5), (49.4, 80)],
            [(49.4, 81.5), (42, 81), (43.5, 88), (49.4, 94)]
        ]),
        muscle(.obliques, [[(40.3, 54), (35.5, 51.5), (34.6, 58), (35.2, 67), (36.5, 76), (38, 84), (41, 87), (40.3, 71)]]),
        muscle(.hipFlexors, [[(38, 85.5), (42, 88.5), (45, 95), (42, 99), (35, 93), (36, 89)]]),
        // Drawn before quads so the inner quad plate sits on top.
        muscle(.adductors, [[(42.5, 99), (49.4, 101.5), (48.5, 112), (46.5, 124), (45.8, 109)]]),
        muscle(.quads, [
            [(35, 94.5), (32.5, 108), (33, 126), (36, 140), (38.5, 141), (38.3, 118), (37.5, 103)],
            [(39, 97.5), (37.8, 103), (38.8, 118), (39, 141), (43, 142), (45.5, 132), (46, 124), (45.5, 110), (42, 100)]
        ]),
        base("knee", [knee]),
        base("shin", [[(36.5, 150), (40, 150), (39.5, 170), (38, 180), (36.5, 170), (35.5, 160)]]),
        muscle(.calves, [[(40.5, 150), (44, 150.5), (45, 158), (43.5, 170), (40.5, 180), (40, 168)]]),
        base("foot", [[(36.5, 182), (41.5, 182), (43, 190), (42, 195), (34, 195), (34.5, 189)]])
    ]

    static let back: [BodyRegion] = [
        BodyRegion(id: "base.head", muscle: nil, polygons: [head]),
        base("neck", [[(45, 19.5), (49.4, 20.5), (49.4, 22), (45, 23)]]),
        muscle(.traps, [[(49.4, 22), (45, 23), (44.5, 28), (36, 31.5), (42, 35), (46.5, 44), (49.4, 52)]]),
        muscle(.sideDelts, [[(34.5, 31), (29, 32.5), (25.5, 37), (24.5, 44), (26.5, 47), (27.8, 40), (30.5, 35)]]),
        muscle(.rearDelts, [[(36, 31.8), (34.5, 31.2), (30.5, 35), (27.8, 40), (26.5, 47), (30.3, 46), (33.5, 40), (36, 36)]]),
        muscle(.upperBack, [[(41.5, 35.5), (36.8, 36.5), (34, 41), (36, 47), (42, 48), (46, 44.5)]]),
        muscle(.lats, [[(34, 42), (32.5, 48), (34, 58), (36.5, 68), (40.5, 76), (44, 77), (44.6, 66), (46.6, 56), (46.3, 46.5), (42, 49), (36, 48)]]),
        muscle(.lowerBack, [[(49.4, 53), (47.2, 57), (45.6, 66), (45, 77), (44, 86), (49.4, 88)]]),
        muscle(.triceps, [[(30.5, 47), (26.5, 48), (24, 55), (23.8, 63), (27.5, 66), (30, 59), (31, 52)]]),
        muscle(.forearms, forearm),
        base("hand", [hand]),
        muscle(.glutes, [[(49.4, 89), (43.5, 87.5), (37.5, 91), (34.8, 98), (36, 106), (41, 110), (49.4, 108)]]),
        muscle(.hamstrings, [
            [(35.5, 108), (33, 118), (34, 132), (37, 141), (39.5, 140), (39.5, 124), (39, 111)],
            [(40, 111.5), (40.2, 124), (40.5, 140), (44, 141), (46, 130), (47, 118), (48.5, 110), (44, 111.5)]
        ]),
        base("knee", [knee]),
        muscle(.calves, [
            [(36, 149), (35, 158), (36.5, 168), (39.5, 172), (40, 160), (39.5, 150)],
            [(40.4, 150), (44.5, 150.5), (45.5, 158), (44, 168), (40.6, 173), (40.7, 160)]
        ]),
        base("ankle", [[(37, 173.5), (43.5, 173.5), (41.5, 181), (38, 181)]]),
        base("foot", [[(36.5, 182), (42, 182), (42.5, 192), (36, 192)]])
    ]

    // Shared parts (identical from front and back).
    private static let forearm: [Half] = [[(24, 67.5), (28, 67), (28.5, 72), (26, 82), (24.5, 89), (20.5, 89), (19.5, 80), (21, 72)]]
    private static let hand: Half = [(20, 90.5), (25, 90.5), (25.5, 97), (23, 101), (19.5, 99), (19, 94)]
    private static let knee: Half = [(36.5, 142), (43, 143), (43, 148.5), (37.5, 148.5)]

    /// Faceted 12-gon head — whole, not mirrored, so it has no centerline groove.
    private static let head: [CGPoint] = (0..<12).map { i in
        let a = Double(i) * .pi / 6
        return CGPoint(x: 50 + 7.5 * cos(a), y: 11.5 + 9.5 * sin(a))
    }

    private static func muscle(_ m: Muscle, _ halves: [Half]) -> BodyRegion {
        BodyRegion(id: m.rawValue, muscle: m, polygons: mirrored(halves))
    }

    private static func base(_ id: String, _ halves: [Half]) -> BodyRegion {
        BodyRegion(id: "base." + id, muscle: nil, polygons: mirrored(halves))
    }

    private static func mirrored(_ halves: [Half]) -> [[CGPoint]] {
        halves.flatMap { half in
            let left = half.map { CGPoint(x: $0.0, y: $0.1) }
            return [left, left.map { CGPoint(x: 100 - $0.x, y: $0.y) }]
        }
    }
}

#Preview("Targets — Bench") {
    MuscleMapView(.targets(MuscleTargets(primary: [.chest], secondary: [.frontDelts, .triceps])))
        .frame(height: 260)
        .padding()
        .background(Color.surface)
}

#Preview("Targets — Deadlift") {
    MuscleMapView(.targets(ExerciseLibrary.muscleTargets(for: "Deadlift")!))
        .frame(height: 260)
        .padding()
        .background(Color.surface)
}

#Preview("Heat") {
    MuscleMapView(.heat([.chest: 1, .frontDelts: 0.6, .triceps: 0.5, .lats: 0.8, .upperBack: 0.7,
                         .quads: 0.9, .glutes: 0.6, .hamstrings: 0.3, .biceps: 0.4]))
        .frame(height: 260)
        .padding()
        .background(Color.surfaceElevated)
}
