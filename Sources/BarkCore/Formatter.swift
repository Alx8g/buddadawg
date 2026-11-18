import Foundation

/// Conservative orthographic tidy-up for raw ASR output: sentence capitals, punctuation
/// spacing, and unambiguous number words to digits ("one thousand two hundred and fifty" -> 1250,
/// "three forty five pm" -> "3:45 pm"). Single number words stay words ("one of these days")
/// unless a unit follows ("five dollars" -> "5 dollars"). It never drops or reorders words;
/// filler removal is the Clean model's job.
public enum DictationFormatter {
    // Compiled once: NSRegularExpression is immutable and thread-safe, and compiling per
    // format() call cost more than the match itself on dictation-length strings.
    private static let whitespaceRun = try! NSRegularExpression(pattern: "\\s+")
    private static let spaceBeforePunct = try! NSRegularExpression(pattern: " +([.,!?;:%])")
    private static let loneI = try! NSRegularExpression(pattern: "(?<![A-Za-z])i(?=(?:['’](?:m|ve|ll|d|re))?(?![A-Za-z]))")

    private static func replace(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    public static func format(_ text: String) -> String {
        var s = replace(whitespaceRun, in: text, with: " ")
            .trimmingCharacters(in: .whitespaces)
        s = replace(spaceBeforePunct, in: s, with: "$1")
        s = convertNumbers(s)
        s = capitalise(s)
        return s
    }

    // MARK: - Capitals

    private static func capitalise(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var capNext = true
        for ch in s {
            if capNext, ch.isLetter {
                out.append(contentsOf: ch.uppercased())
                capNext = false
            } else {
                out.append(ch)
                if ch.isLetter || ch.isNumber { capNext = false }
            }
            if ch == "." || ch == "!" || ch == "?" { capNext = true }
        }
        return replace(loneI, in: out, with: "I")
    }

    // MARK: - Numbers

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]
    private static let units: Set<String> = ["dollar", "dollars", "cent", "cents", "percent", "%", "euros", "pounds"]

    private struct Parsed { let rendered: String; let consumed: Int; let words: Int; let strong: Bool }

    private static let punctSet = CharacterSet(charactersIn: ".,!?;:")

    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: punctSet).lowercased()
    }
    private static func suffix(_ token: String) -> String {
        var i = token.endIndex
        while i > token.startIndex {
            let prev = token.index(before: i)
            guard ".,!?;:".contains(token[prev]) else { break }
            i = prev
        }
        return String(token[i...])
    }

    /// Splits a space-separated token into number-ish words (handles "eighty-two").
    private static func numberWords(_ token: String) -> [String] {
        core(token).split(separator: "-").map(String.init)
    }

    private static func isNumberish(_ word: String) -> Bool {
        ones[word] != nil || tens[word] != nil || scales[word] != nil || word == "hundred" || word == "point"
    }

    /// Parses an English number starting at token `start`. Returns nil if no number starts there.
    /// Grammar-aware: a ones word cannot follow a ones word, so counting lists
    /// ("one two three") parse as separate single words and are left alone, while real
    /// compounds ("thirty six hundred", "four thousand eighty-two") still parse whole.
    private enum NumState { case start, ones, tens, hundred, scale }

    private static func accepts(_ state: NumState, _ w: String) -> NumState? {
        if w == "point" { return state == .start ? nil : state }
        switch state {
        case .start:
            if ones[w] != nil { return .ones }
            if tens[w] != nil { return .tens }
            return nil
        case .ones:
            if w == "hundred" { return .hundred }
            if scales[w] != nil { return .scale }
            return nil
        case .tens:
            if let v = ones[w], v < 10 { return .ones }
            if w == "hundred" { return .hundred }
            if scales[w] != nil { return .scale }
            return nil
        case .hundred:
            if ones[w] != nil { return .ones }
            if tens[w] != nil { return .tens }
            if scales[w] != nil { return .scale }
            return nil
        case .scale:
            if ones[w] != nil { return .ones }
            if tens[w] != nil { return .tens }
            return nil
        }
    }

    private static func parseNumber(_ tokens: [String], from start: Int) -> Parsed? {
        var i = start
        var total = 0.0, current = 0.0, fraction = ""
        var words = 0, strong = false, saw = false, inFraction = false
        var state = NumState.start
        while i < tokens.count {
            let parts = numberWords(tokens[i])
            if parts == ["and"], saw, state == .hundred || state == .scale, i + 1 < tokens.count,
               numberWords(tokens[i + 1]).first.flatMap({ accepts(state, $0) }) != nil {
                i += 1
                continue
            }
            guard !parts.isEmpty, parts.allSatisfy(isNumberish) else { break }
            var tokenWords = 0
            var rejected = false
            for w in parts {
                if inFraction {
                    guard let d = ones[w], d < 10 else { rejected = true; break }
                    fraction += String(d); tokenWords += 1; continue
                }
                guard let next = accepts(state, w) else { rejected = true; break }
                state = next
                tokenWords += 1
                if w == "point" {
                    strong = true; inFraction = true
                } else if let v = ones[w] {
                    current += Double(v)
                } else if let v = tens[w] {
                    current += Double(v)
                } else if w == "hundred" {
                    current *= 100; strong = true
                } else if let v = scales[w] {
                    total += current * Double(v); current = 0; strong = true
                }
            }
            if rejected { break }  // this token starts something else (or the next counted number)
            words += tokenWords
            saw = true
            i += 1
        }
        guard saw else { return nil }
        return finish(total + current, fraction: fraction, consumed: i - start, words: words, strong: strong)
    }

    private static func finish(_ value: Double, fraction: String, consumed: Int, words: Int, strong: Bool) -> Parsed {
        let base = fraction.isEmpty ? String(Int(value)) : "\(Int(value)).\(fraction)"
        return Parsed(rendered: base, consumed: consumed, words: words, strong: strong)
    }

    private static func convertNumbers(_ s: String) -> String {
        var tokens = s.split(separator: " ").map(String.init)
        // Merge "a. m." / "p. m." into single am/pm tokens so times can see them.
        var merged: [String] = []
        var j = 0
        while j < tokens.count {
            if j + 1 < tokens.count, ["a.", "p."].contains(tokens[j].lowercased()),
               core(tokens[j + 1]) == "m" {
                merged.append((core(tokens[j]) == "a" ? "am" : "pm") + suffix(tokens[j + 1]).filter { $0 != "." })
                j += 2
            } else {
                merged.append(tokens[j]); j += 1
            }
        }
        tokens = merged

        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if let time = parseTime(tokens, from: i) {
                out.append(time.rendered + suffix(tokens[i + time.consumed - 1]))
                i += time.consumed
                continue
            }
            if let n = parseNumber(tokens, from: i) {
                let next = i + n.consumed < tokens.count ? core(tokens[i + n.consumed]) : ""
                if n.words >= 2 || n.strong || units.contains(next) {
                    out.append(n.rendered + suffix(tokens[i + n.consumed - 1]))
                    i += n.consumed
                    continue
                }
            }
            out.append(tokens[i]); i += 1
        }
        return out.joined(separator: " ")
    }

    /// "three forty five pm" / "three oh five am" -> "3:45 pm". Hour must be 1...12 and am/pm present.
    private static func parseTime(_ tokens: [String], from start: Int) -> Parsed? {
        guard start < tokens.count else { return nil }
        func smallValue(_ idx: Int) -> Int? {
            let parts = numberWords(tokens[idx])
            if parts.count == 1 {
                if parts[0] == "oh" { return 0 }
                return ones[parts[0]] ?? tens[parts[0]]
            }
            if parts.count == 2, let t = tens[parts[0]], let o = ones[parts[1]], o < 10 { return t + o }
            return nil
        }
        guard let hour = smallValue(start), (1...12).contains(hour) else { return nil }
        // Minutes: [tens ones], [oh ones], or a single 0...59 word.
        let ampm: (Int) -> String? = { idx in
            guard idx < tokens.count else { return nil }
            let c = core(tokens[idx])
            return (c == "am" || c == "pm") ? c : nil
        }
        if start + 3 < tokens.count + 1, start + 2 < tokens.count,
           let tensPart = smallValue(start + 1), let onesPart = smallValue(start + 2),
           onesPart < 10, let ap = ampm(start + 3) {
            let minutes = tensPart + onesPart
            guard minutes < 60 else { return nil }
            return Parsed(rendered: "\(hour):\(String(format: "%02d", minutes)) \(ap)", consumed: 4, words: 3, strong: true)
        }
        if start + 1 < tokens.count, let minutes = smallValue(start + 1), minutes < 60, let ap = ampm(start + 2) {
            return Parsed(rendered: "\(hour):\(String(format: "%02d", minutes)) \(ap)", consumed: 3, words: 2, strong: true)
        }
        return nil
    }
}
