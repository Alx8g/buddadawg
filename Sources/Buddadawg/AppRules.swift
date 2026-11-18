import AppKit

/// Per-app delivery rules, stored in `~/.config/buddadawg/app-rules`.
///
/// File format (one rule per line):
///   bundle.id.substring => send|paste
///   # comment lines are ignored
///
/// Matching is a case-insensitive substring match on the frontmost app's bundle
/// identifier — `slack` matches `com.tinyspeck.slackmacgap`, `com.apple.Terminal`
/// matches exactly or as a substring. First matching rule wins; no match = send.
///
/// `send` (the default) pastes and presses Enter. `paste` pastes only — for apps
/// where Enter submits prematurely (chat, terminals, composers). Explicit gestures
/// still win: a double-tap-to-send or the armed re-send always sends regardless of
/// rules; only the automatic Enter after a normal dictation is governed.
enum AppRules {
    static let file = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/buddadawg/app-rules")

    private struct Rule {
        let bundleFragment: String
        let pasteOnly: Bool
    }

    private static func load() -> [Rule] {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return raw.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let arrow = trimmed.range(of: "=>") else { return nil }
            let fragment = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            let action = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            guard !fragment.isEmpty, action == "send" || action == "paste" else { return nil }
            return Rule(bundleFragment: fragment, pasteOnly: action == "paste")
        }
    }

    /// Whether the automatic Enter should fire for the current frontmost app.
    /// Unknown apps and lookup failures default to send — rules only ever restrict.
    static func allowsSend() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() else {
            return true
        }
        for rule in load() where bundleID.contains(rule.bundleFragment) {
            return !rule.pasteOnly
        }
        return true
    }

    /// Creates the file with commented examples if it doesn't exist.
    static func ensureFile() {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = """
        # Buddadawg app rules — control whether dictation presses Enter per app.
        #
        # Format:  bundle.id.fragment => send|paste
        #   send   = paste text and press Enter (default for every app)
        #   paste  = paste text only, no Enter
        #
        # Matching is a case-insensitive substring of the app's bundle identifier;
        # first match wins. Examples:
        #
        # com.tinyspeck.slackmacgap => paste
        # com.apple.Terminal => paste
        # com.apple.mail => send
        #
        # Note: explicit double-tap-to-send and "re-send last dictation" always send,
        # regardless of rules — rules only govern the automatic Enter.
        """
        try? seed.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Opens the rules file in the default editor.
    static func edit() {
        ensureFile()
        NSWorkspace.shared.open(file)
    }
}
