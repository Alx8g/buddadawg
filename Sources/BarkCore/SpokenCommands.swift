import Foundation

/// Spoken editing commands in dictation ("scratch that", "new paragraph", "bullet point …",
/// "comma", "question mark" …).
/// Pure and deterministic, like `DictationFormatter`: no state, no I/O, unit-tested.
///
/// Deliberately conservative — a mis-fired command silently eats or alters the user's words,
/// which is worse than a missed command pasted as text:
/// - "scratch that" discards only when it is the *entire* utterance ("scratch that itch"
///   is ordinary speech and passes through).
/// - "new line" / "new paragraph" act only at the very end of the utterance (or alone),
///   never mid-sentence, and not when an article/possessive directly precedes them, so
///   "a new line of work" and "add a new line" stay text.
/// - "bullet point" acts only at the very start, so "the bullet point said …" stays text.
/// - Punctuation commands ("comma" -> ",", "question mark" -> "?", "open quote" -> "“" …)
///   share the breaks' trailing/standalone placement and noun-phrase guard, and additionally
///   refuse to fire when the command's last word already carries sentence punctuation —
///   "question mark?" means the punctuation was dictated, not commanded.
/// - Capitalisation ("capitalize", "all caps") and ITN (numbers -> digits, "percent" -> %)
///   are deliberately absent: both need mid-sentence rewriting or are too ambiguous.
///
/// Run this *after* `DictationFormatter.format`, whose whitespace collapsing (`\s+` -> " ")
/// would erase the line/paragraph breaks produced here. Matching is case-insensitive and
/// ignores punctuation attached to the command words, so formatted text still matches.
public enum SpokenCommands {

    public enum Action: Equatable, Sendable {
        /// Throw the whole utterance away; paste nothing, add nothing to Recents.
        case discard
        case insertLineBreak
        case insertParagraphBreak
        /// The remaining text is prefixed with "• ".
        case bulletPoint
        /// Append a literal punctuation mark spoken as a word ("comma" -> ",").
        case insertPunctuation(String)
    }

    public struct Result: Equatable, Sendable {
        /// Text to paste. Empty when `shouldDiscard`; just the break(s) for a standalone
        /// "new paragraph" / "new line" utterance. Unchanged from the input when no
        /// command matched, so ordinary dictation is never re-flowed by this parser.
        public let text: String
        /// Commands found, in the order they apply to the text (bullet before breaks).
        public let actions: [Action]

        public init(text: String, actions: [Action]) {
            self.text = text
            self.actions = actions
        }

        public var shouldDiscard: Bool { actions.contains(.discard) }
    }

    // Words that make a trailing command a noun phrase rather than a command:
    // "add a new line", "a question mark", "the grace period", "serial comma".
    private static let nounPhraseHeads: Set<String> = [
        "a", "an", "the", "this", "that", "another", "one", "each", "every", "brand",
        "my", "your", "his", "her", "their", "our", "its",
        // Noun adjuncts that need no determiner to form a phrase, mostly for
        // "… period" ("the grace period") and "… comma" ("serial comma").
        "grace", "notice", "waiting", "cooling", "trial", "probation", "interim", "pay",
        "report", "billing", "accounting", "fiscal", "financial", "tax", "incubation",
        "recovery", "warranty", "guarantee", "serial", "eligibility", "qualification",
        "reflection", "detention", "remand", "suspension", "recess", "intermission",
    ]

    /// Multi-word commands matched at the end of the utterance. `punctuation` marks the
    /// ones that must not already carry sentence punctuation on their last word —
    /// "question mark?" means the mark was dictated, not commanded. Breaks are exempt:
    /// "new paragraph." still commands a break.
    private static let phraseCommands: [(phrase: [String], action: Action, punctuation: Bool)] = [
        (["new", "paragraph"], .insertParagraphBreak, false),
        (["new", "line"], .insertLineBreak, false),
        (["question", "mark"], .insertPunctuation("?"), true),
        (["exclamation", "mark"], .insertPunctuation("!"), true),
        (["exclamation", "point"], .insertPunctuation("!"), true),
        (["full", "stop"], .insertPunctuation("."), true),
        (["open", "quote"], .insertPunctuation("“"), true),
        (["close", "quote"], .insertPunctuation("”"), true),
        (["dot", "dot", "dot"], .insertPunctuation("…"), true),
    ]

    /// Single-word punctuation commands. Bare "quote" is excluded ("a quote", "quote of
    /// the day") and so is "dot" — too easily a noun or a number fragment.
    private static let punctuationWords: [String: String] = [
        "comma": ",", "period": ".", "colon": ":", "semicolon": ";", "ellipsis": "…",
    ]

    /// Lowercased word with surrounding sentence punctuation stripped ("paragraph." -> "paragraph").
    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"“”()[]")).lowercased()
    }

    /// Removes trailing `,;:` (not `.!?`) — "Hello world, new line" keeps its sentence intact
    /// but drops the comma that only introduced the command.
    private static func strippingTrailingJoiners(_ token: String) -> String {
        var t = token
        while let last = t.last, ",;:".contains(last) { t.removeLast() }
        return t
    }

    /// True when the token's trailing punctuation run contains sentence-ending marks
    /// (".", "!", "?", "…"). For punctuation commands this means the mark was already
    /// dictated ("question mark?"), so the words stay text. Joiners like "comma,"
    /// don't count — the comma only introduced the command.
    private static func hasSentencePunctuation(_ token: String) -> Bool {
        for ch in token.reversed() {
            if ".,!?;:\"'’”…“”()[]".contains(ch) {
                if ".!?…".contains(ch) { return true }
            } else { break }
        }
        return false
    }

    /// The token before a trailing command decides noun phrase vs. command. Besides the
    /// determiners in `nounPhraseHeads`, a capitalised word mid-utterance counts:
    /// `DictationFormatter` capitalises only sentence-initial words and proper
    /// nouns/adjectives, so "the Victorian period" is a phrase while "Hello comma" is
    /// not — the utterance's first token is always capitalised, so it never counts, and
    /// a capital after ".!?" starts a new sentence ("… milk. Eggs comma"), not a phrase.
    private static func nounPhrasePrecedes(_ tokens: [String], before index: Int) -> Bool {
        guard index > 0 else { return false }
        let pred = tokens[index - 1]
        if nounPhraseHeads.contains(core(pred)) { return true }
        guard let first = pred.first, first.isUppercase else { return false }
        if index == 1 { return false }
        if let last = tokens[index - 2].last, ".!?".contains(last) { return false }
        return true
    }

    /// What a tail action appends to the text ("" for actions that never appear in `tail`).
    private static func literal(for action: Action) -> String {
        switch action {
        case .insertParagraphBreak: return "\n\n"
        case .insertLineBreak: return "\n"
        case .insertPunctuation(let mark): return mark
        case .discard, .bulletPoint: return ""
        }
    }

    public static func parse(_ raw: String) -> Result {
        var tokens = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return Result(text: "", actions: []) }

        // Whole-utterance discard. Trailing terminal punctuation is part of the last
        // token's suffix and is ignored by `core`, so "Scratch that." matches too.
        if tokens.map(core) == ["scratch", "that"] {
            return Result(text: "", actions: [.discard])
        }

        // Trailing commands — line/paragraph breaks and punctuation share one placement
        // rule: end of utterance (or alone), never mid-sentence, never right after a
        // noun-phrase word. Longest match wins ("dot dot dot" before nothing shorter).
        // Collected back-to-front and re-inserted at 0 to keep spoken order.
        var tail: [Action] = []
        while !tokens.isEmpty {
            var hit: (action: Action, length: Int, punctuation: Bool)?
            for length in stride(from: min(3, tokens.count), through: 1, by: -1) {
                let span = tokens.suffix(length).map(core)
                if let cmd = phraseCommands.first(where: { $0.phrase == span }) {
                    hit = (cmd.action, length, cmd.punctuation)
                } else if length == 1, let mark = punctuationWords[span[0]] {
                    hit = (.insertPunctuation(mark), 1, true)
                }
                if hit != nil { break }
            }
            guard let match = hit else { break }
            if match.punctuation, hasSentencePunctuation(tokens[tokens.count - 1]) { break }
            if nounPhrasePrecedes(tokens, before: tokens.count - match.length) { break }
            tokens.removeLast(match.length)
            tail.insert(match.action, at: 0)
            if let last = tokens.last {
                let cleaned = strippingTrailingJoiners(last)
                if cleaned.isEmpty { tokens.removeLast() } else { tokens[tokens.count - 1] = cleaned }
            }
        }

        // Leading "bullet point" only. A separator the speaker dictated right after it
        // ("bullet point, buy milk") is dropped rather than pasted.
        var bullet = false
        if tokens.count >= 2, [core(tokens[0]), core(tokens[1])] == ["bullet", "point"] {
            bullet = true
            tokens.removeFirst(2)
            while let first = tokens.first, core(first).isEmpty { tokens.removeFirst() }
            if let first = tokens.first {
                var cleaned = first
                while let ch = cleaned.first, ",;:".contains(ch) { cleaned.removeFirst() }
                tokens[0] = cleaned
            }
        }

        // No command: hand the input back byte-for-byte, never a re-joined version of it.
        guard bullet || !tail.isEmpty else { return Result(text: raw, actions: []) }

        let body = tokens.joined(separator: " ")
        var text = bullet ? (body.isEmpty ? "•" : "• " + body) : body
        for action in tail { text += literal(for: action) }
        return Result(text: text, actions: (bullet ? [.bulletPoint] : []) + tail)
    }
}
