import Foundation

/// One AI-estimated measurement from a photo (inches for circumferences, % for body fat).
public struct MeasurementEstimate: Sendable, Equatable, Identifiable {
    public let type: MeasurementType
    public let value: Double
    public var id: MeasurementType { type }
    public init(type: MeasurementType, value: Double) {
        self.type = type
        self.value = value
    }
}

/// The parsed result of a photo body-measurement estimate.
public struct BodyScanResult: Sendable, Equatable {
    public let estimates: [MeasurementEstimate]
    public let confidence: String   // "low" / "medium" / "high"
    public let note: String
    public init(estimates: [MeasurementEstimate], confidence: String, note: String) {
        self.estimates = estimates
        self.confidence = confidence
        self.note = note
    }
}

/// Builds the prompt for estimating body measurements from a single photo, and parses
/// the structured reply. Deliberately honest: a single 2D photo can't yield tape-accurate
/// circumferences, so the prompt asks for rough estimates the user confirms before saving.
public enum BodyScanEstimator {

    // MARK: System prompt

    public static func systemPrompt(for profile: CoachProfile) -> String {
        let stats = profile.statsClause
        let statsLine = stats.isEmpty
            ? "No height/weight provided — estimate from visual proportions only, and lower your confidence."
            : "Use the athlete's stats as a scale anchor: \(stats)."
        return """
        You estimate body measurements from a single photo to help an athlete track recomposition.
        IMPORTANT: a single 2D photo cannot give tape-accurate circumferences. Give honest, rough estimates — the user will confirm them against a tape before saving. Do not overstate precision; prefer "low" confidence for one photo.
        \(statsLine)
        Estimate only the measurements you can reasonably infer from what's visible — omit anything hidden by clothing or framing. Circumferences are in INCHES; body fat is a PERCENT.
        Allowed measurement types (use these exact keys): shoulders, chest, arm, waist, hips, thigh, calf, neck, bodyFat.
        OUTPUT FORMAT — STRICT: wrap JSON in <measurements> tags, no prose outside, no markdown.
        <measurements>
        {
          "estimates": [
            {"type": "chest", "value": 42},
            {"type": "waist", "value": 33.5},
            {"type": "arm", "value": 15},
            {"type": "bodyFat", "value": 16}
          ],
          "confidence": "low",
          "note": "Rough visual estimate from one photo — confirm with a tape."
        }
        </measurements>
        """
    }

    // MARK: User prompt

    public static func userPrompt(for profile: CoachProfile) -> String {
        "Estimate this person's body measurements from the attached photo. Circumferences in inches, body fat as a percent. Only include measurements you can reasonably infer. Return the <measurements> JSON exactly as specified."
    }

    // MARK: Parsing

    public static func parse(response: String) -> BodyScanResult? {
        guard let start = response.range(of: "<measurements>"),
              let end = response.range(of: "</measurements>", range: start.upperBound..<response.endIndex)
        else { return nil }
        let json = response[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawScan.self, from: data)
        else { return nil }

        let estimates: [MeasurementEstimate] = (raw.estimates ?? []).compactMap { e in
            guard let type = MeasurementType.loose(e.type), let v = e.value, v > 0 else { return nil }
            return MeasurementEstimate(type: type, value: v)
        }
        // Keep one per type, in canonical order (drops any duplicate the model listed).
        let deduped = MeasurementType.allCases.compactMap { t in
            estimates.first(where: { $0.type == t })
        }
        guard !deduped.isEmpty else { return nil }
        return BodyScanResult(estimates: deduped,
                              confidence: raw.confidence ?? "low",
                              note: raw.note ?? "")
    }

    /// Lenient decode target — tolerates unknown type strings (filtered later) and
    /// missing optional fields.
    private struct RawScan: Decodable {
        struct RawEstimate: Decodable { let type: String; let value: Double? }
        let estimates: [RawEstimate]?
        let confidence: String?
        let note: String?
    }
}
