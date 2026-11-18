import Foundation

/// Pure, deterministic snippet matching — no I/O, no state. The app layer
/// (`Buddadawg/Snippets.swift`) owns the file; this owns the rules.
///
/// A snippet fires only when the *entire* normalized utterance is exactly
/// "snippet <trigger>" (case-insensitive, whitespace-collapsed). Mid-sentence
/// mentions like "my snippet url" never expand.
public enum SnippetMatcher {
    public struct Entry: Equatable {
        /// Normalized spoken key, e.g. "snippet schedule link".
        public let spoken: String
        /// Canned text with escapes already decoded.
        public let text: String
    }

    public static func normalized(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Parses `trigger => text` lines. `#` comments and malformed lines are skipped.
    /// `\n`, `\t`, `\r`, `\\` escapes in the text are decoded; unknown escapes keep
    /// their backslash.
    public static func parse(_ raw: String) -> [Entry] {
        var entries: [Entry] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let range = trimmed.range(of: "=>") else { continue }
            let trigger = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty, !text.isEmpty else { continue }
            entries.append(Entry(spoken: normalized("snippet " + trigger),
                                 text: decodeEscapes(text)))
        }
        return entries
    }

    /// Returns the canned text when `utterance` is exactly "snippet <trigger>".
    public static func match(_ utterance: String, entries: [Entry]) -> String? {
        let key = normalized(utterance)
        guard key.hasPrefix("snippet ") else { return nil }
        return entries.first(where: { $0.spoken == key })?.text
    }

    private static func decodeEscapes(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                default:
                    out.append("\\")
                    out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out
    }
}
