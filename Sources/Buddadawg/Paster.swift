import AppKit

/// Pastes text at the cursor via the clipboard and Cmd-V. The text stays on the clipboard
/// afterwards by design: if the paste landed in the wrong place, a manual Cmd-V puts it
/// where it was meant to go. The synthetic keystroke is tagged so the hotkey tap ignores it.
enum Paster {
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func paste(_ text: String) {
        copy(text)
        sendPasteKeystroke()
    }

    /// Pastes, then presses Return so chat-style apps send the message. The keystroke is
    /// tagged like the paste so the hotkey tap ignores it, and delayed a beat so the host
    /// app has time to insert the pasted text before Enter arrives.
    static func pasteAndSend(_ text: String) {
        paste(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sendReturn() }
    }

    static func sendReturn() {
        sendKey(virtualKey: 36)  // Return
    }

    static func sendPasteKeystroke() {
        sendKey(virtualKey: 9, command: true)  // V
    }

    /// Tagged Cmd-C, used only to read another app's selection for the dictionary
    /// prompt; the pasteboard is saved and restored around it by the caller.
    static func sendCopyKeystroke() {
        sendKey(virtualKey: 8, command: true)  // C
    }

    private static func sendKey(virtualKey: UInt16, command: Bool = false) {
        // Tag via the event *source* userData: that is what .eventSourceUserData reports
        // on receipt; setting the field on the event alone does not survive posting.
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = Hotkey.syntheticUserData
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down)
            e?.flags = command ? .maskCommand : []
            e?.setIntegerValueField(.eventSourceUserData, value: Hotkey.syntheticUserData)
            e?.post(tap: .cghidEventTap)
        }
    }
}

/// Plain-text replacements from ~/.config/buddadawg/dictionary, one `heard => written` per line (# for comments).
/// Matching is case-insensitive on whole words, so "tail scale => Tailscale" fixes it anywhere in a sentence.
enum Dictionary {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/buddadawg/dictionary")

    /// Creates the dictionary with starter entries from observed mishearings, once.
    static func seedIfNeeded() {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? """
        # heard => written, one per line
        tail scale => Tailscale
        butter dog => Buddadawg
        budda dawg => Buddadawg
        neuro engine => Neural Engine
        s.s. h => SSH
        """.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Appends a `heard => written` pair. Returns false for invalid input (empty side,
    /// embedded "=>" or newline) so the caller can keep the prompt open; an existing
    /// identical pair counts as success. `apply` re-reads the file per dictation, so a
    /// new entry takes effect on the very next transcription.
    @discardableResult
    static func add(heard: String, written: String) -> Bool {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !w.isEmpty,
              !h.contains("=>"), !w.contains("=>"),
              !h.contains("\n"), !w.contains("\n") else { return false }
        seedIfNeeded()
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        for line in existing.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].caseInsensitiveCompare(h) == .orderedSame, parts[1] == w { return true }
        }
        var text = existing
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += "\(h) => \(w)\n"
        do { try text.write(to: file, atomically: true, encoding: .utf8); return true }
        catch { return false }
    }

    static func apply(_ text: String) -> String {
        guard let lines = try? String(contentsOf: file, encoding: .utf8) else { return text }
        var out = text
        for line in lines.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: parts[0]) + "\\b"
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: parts[1]),
                                           options: [.regularExpression, .caseInsensitive])
        }
        return out
    }
}
