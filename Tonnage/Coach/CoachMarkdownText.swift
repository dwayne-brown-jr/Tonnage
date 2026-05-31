import SwiftUI
import TonnageCore

/// Renders the coach's replies the way they should look in a narrow chat bubble:
/// inline bold/italic, headings, dash/number bullet lists — and, crucially, it degrades
/// any markdown table the model emits into clean stacked rows (a 3-column table never
/// fits a phone bubble). Raw `**asterisks**` and `|pipes|` never reach the user.
struct CoachMarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(DSFont.body)
        .foregroundStyle(Color.textPrimary)
    }

    // MARK: Block model

    private enum Block {
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case numbered([(String, String)])
        case table([[String]])
    }

    private var blocks: [Block] { Self.parse(text) }

    @ViewBuilder private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let s):
            inline(s)
                .font(.system(.subheadline, weight: .bold))

        case .paragraph(let s):
            inline(s)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text("•").foregroundStyle(Color.accent)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text("\(item.0).").foregroundStyle(Color.accent).monospacedDigit()
                        inline(item.1).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .table(let rows):
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    tableRow(cells)
                }
            }
        }
    }

    /// A degraded table row: first cell as a bold title, the rest as a secondary line.
    private func tableRow(_ cells: [String]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let first = cells.first, !first.isEmpty {
                inline(first).font(.system(.subheadline, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            let rest = cells.dropFirst().filter { !$0.isEmpty }
            if !rest.isEmpty {
                inline(rest.joined(separator: " · "))
                    .font(.system(.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Inline markdown (bold/italic/code/links) → styled Text, with a plain-text fallback.
    private func inline(_ s: String) -> Text {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
        if let attr = try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(cleaned)
    }

    // MARK: Parser

    private static func parse(_ text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.isEmpty { flushParagraph(); i += 1; continue }

            // Table: a run of lines that look like markdown rows.
            if isTableLine(line) {
                flushParagraph()
                var tableLines: [String] = []
                while i < lines.count, isTableLine(lines[i].trimmingCharacters(in: .whitespaces)) {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.table(parseTable(tableLines)))
                continue
            }

            // ATX heading (#, ##, …)
            if line.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }

            // A line that's entirely bold → treat as a heading.
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(2).dropLast(2))))
                i += 1; continue
            }

            // Bullet list
            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    i += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            // Numbered list
            if numbered(line) != nil {
                flushParagraph()
                var items: [(String, String)] = []
                while i < lines.count, let n = numbered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(n); i += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func isBullet(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ")
    }

    private static func numbered(_ s: String) -> (String, String)? {
        var idx = s.startIndex
        var digits = ""
        while idx < s.endIndex, s[idx].isNumber { digits.append(s[idx]); idx = s.index(after: idx) }
        guard !digits.isEmpty, idx < s.endIndex, s[idx] == "." else { return nil }
        let afterDot = s.index(after: idx)
        guard afterDot < s.endIndex, s[afterDot] == " " else { return nil }
        return (digits, String(s[s.index(after: afterDot)...]))
    }

    private static func isTableLine(_ s: String) -> Bool {
        s.contains("|") && s.filter { $0 == "|" }.count >= 2
    }

    private static func parseTable(_ lines: [String]) -> [[String]] {
        var rows: [[String]] = []
        var sawSeparator = false
        for line in lines {
            var cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.first == "" { cells.removeFirst() }
            if cells.last == "" { cells.removeLast() }
            guard !cells.isEmpty else { continue }
            // Separator row like |---|:--:|
            let isSeparator = cells.allSatisfy { c in
                !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
            }
            if isSeparator { sawSeparator = true; continue }
            rows.append(cells)
        }
        // If there was a separator, the first remaining row is the column header — drop it,
        // since each stacked row is already self-describing.
        if sawSeparator, !rows.isEmpty { rows.removeFirst() }
        return rows
    }
}

#Preview("Coach markdown") {
    ScrollView {
        CoachMarkdownText(text: """
        **Tomorrow is Lower A — Squat focus.**

        Here's your session:

        | Lift | Prescription | Notes |
        |------|--------------|-------|
        | **Barbell Back Squat** | 3×5-7, reps left: 3→2→2 | Ramp up. Last set is your top set — log it. |
        | **Romanian Deadlift** | 3×8-10, 2 reps left | Neutral spine, hinge pattern. |
        | **Standing Calf Raise** | 3×12-15, 1 rep left | Full stretch, pause top. |

        **Readiness:** 82/100 — you're primed. HRV up, resting HR clean, sleep solid.

        A couple of cues:
        - Brace hard before each squat rep.
        - Keep the bar over mid-foot.
        """)
        .padding()
    }
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
