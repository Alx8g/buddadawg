import AppKit

/// Pastes text at the cursor via the clipboard and ⌘V, then puts the previous clipboard back.
enum Paster {
    static func paste(_ text: String) {
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        board.clearContents()
        board.setString(text, forType: .string)
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)  // V
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !saved.isEmpty else { return }
            board.clearContents()
            board.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
    }
}

/// Plain-text replacements from ~/.config/buddadawg/dictionary, one `heard => written` per line (# for comments).
/// Matching is case-insensitive on whole words, so "tail scale => Tailscale" fixes it anywhere in a sentence.
enum Dictionary {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/buddadawg/dictionary")

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
