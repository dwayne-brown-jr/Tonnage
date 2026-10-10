import Foundation

/// Pulls the JSON payload out of a model reply that wraps it in `<tag>…</tag>`, and
/// cleans up the ways real replies go wrong: markdown code fences inside the tags,
/// prose that mentions the tag before the real payload, trailing commas, and replies
/// cut off mid-JSON. Pair with `Lossy` so one malformed item doesn't empty the result.
public enum AIResponse {

    /// The cleaned JSON between the LAST `</tag>` and the opening tag before it. A reply
    /// cut off before its closing tag still yields everything after the last opening tag.
    public static func payload(in response: String, tag: String) -> String? {
        let open = "<\(tag)>", close = "</\(tag)>"
        let body: Substring
        if let end = response.range(of: close, options: .backwards) {
            guard let start = response.range(of: open, options: .backwards,
                                             range: response.startIndex..<end.lowerBound) else { return nil }
            body = response[start.upperBound..<end.lowerBound]
        } else if let start = response.range(of: open, options: .backwards) {
            body = response[start.upperBound...]
        } else {
            return nil
        }
        let json = repairTruncated(removingTrailingCommas(stripCodeFence(String(body))))
        return json.isEmpty ? nil : json
    }

    /// Decodes the tagged payload as `T`, or nil if there's nothing usable.
    public static func decode<T: Decodable>(_ type: T.Type, from response: String, tag: String) -> T? {
        guard let json = payload(in: response, tag: tag), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Cleanup steps

    /// Drops a ```json … ``` (or bare ```) fence around the payload.
    static func stripCodeFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        // Remove the opening fence line, including any language tag.
        if let newline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: newline)...])
        } else {
            t = String(t.dropFirst(3))
        }
        if let fence = t.range(of: "```", options: .backwards) {
            t = String(t[..<fence.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes commas that sit directly before `]` or `}` — outside of strings.
    static func removingTrailingCommas(_ s: String) -> String {
        var out: [Character] = []
        var inString = false, escaped = false
        for ch in s {
            if inString {
                out.append(ch)
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true }
            if ch == "]" || ch == "}" {
                // Back over whitespace to a dangling comma, if any.
                var i = out.count - 1
                while i >= 0, out[i].isWhitespace { i -= 1 }
                if i >= 0, out[i] == "," { out.remove(at: i) }
            }
            out.append(ch)
        }
        return String(out)
    }

    /// Closes JSON that was cut off mid-reply. Cuts back to the last comma between
    /// complete values, then closes every bracket still open at that point. Complete
    /// JSON passes through unchanged.
    static func repairTruncated(_ s: String) -> String {
        var stack: [Character] = []
        var inString = false, escaped = false
        var lastCut: (index: Int, stack: [Character])?
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]": if !stack.isEmpty { stack.removeLast() }
            case ",": lastCut = (i, stack)
            default: break
            }
        }
        guard !stack.isEmpty || inString else { return s }
        guard let cut = lastCut else { return s }
        return String(chars[..<cut.index]) + String(cut.stack.reversed())
    }
}

/// An array that decodes element by element, skipping elements that fail instead of
/// failing the whole array.
public struct Lossy<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                out.append(value)
            } else {
                _ = try? container.decode(Skip.self)   // advance past the bad element
            }
        }
        elements = out
    }

    /// Decodes (and discards) any JSON value.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
