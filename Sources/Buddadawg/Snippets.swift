import AppKit
import BarkCore

/// Voice-triggered canned text, stored in `~/.config/buddadawg/snippets`.
///
/// File format (one entry per line):
///   trigger => canned text
///   # comment lines are ignored
///
/// `\n` inside the canned text becomes a real newline, `\t` a tab. Trigger names
/// may contain spaces and are matched case-insensitively.
///
/// To fire a snippet, dictate exactly `snippet <trigger>` as the whole utterance
/// (case-insensitive). Whole-utterance matching only — saying "my snippet url"
/// mid-sentence never expands. The canned text then goes through the normal
/// paste/send path, so Auto-Send and Secure Input behave exactly like dictation.
/// Matching rules live in `BarkCore.SnippetMatcher` (pure, unit-tested).
enum Snippets {
    static let file = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/buddadawg/snippets")

    private static func load() -> [SnippetMatcher.Entry] {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return SnippetMatcher.parse(raw)
    }

    /// Returns canned text when `utterance` is exactly "snippet <trigger>".
    static func match(_ utterance: String) -> String? {
        SnippetMatcher.match(utterance, entries: load())
    }

    /// Creates the file with a commented example if it doesn't exist.
    static func ensureFile() {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = """
        # Buddadawg snippets — canned text triggered by voice.
        #
        # Format:  trigger => text you want pasted
        # Say exactly:  snippet <trigger>
        #
        # Examples (uncomment to use):
        # schedule link => Here's my calendar: https://calendly.com/me/30min\\nLet me know what works!
        # email sig => Best,\\nAlex
        # status => Heads down today, back online tomorrow.
        """
        try? seed.write(to: file, atomically: true, encoding: .utf8)
    }

    static func edit() {
        ensureFile()
        NSWorkspace.shared.open(file)
    }
}
