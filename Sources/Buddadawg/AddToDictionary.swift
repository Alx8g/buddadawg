import AppKit
import ApplicationServices

/// "Add Selection to Dictionary…": reads the correctly-spelled text the user has
/// selected in another app, then asks what the engine heard so a `heard => written`
/// pair can be appended to ~/.config/buddadawg/dictionary.
enum AddToDictionary {
    @MainActor
    static func prompt(app: App) {
        Task { @MainActor in
            guard let selection = await SelectionText.read(), !selection.isEmpty else {
                app.setStatus("No text selected — select the correct spelling first")
                return
            }
            DictionaryPanel.present(written: selection) { heard, written in
                if Dictionary.add(heard: heard, written: written) {
                    log("dictionary: added entry")
                    app.setStatus("Dictionary updated — applies to the next dictation")
                    return true
                }
                app.setStatus("Could not add to dictionary (empty field or bad characters)")
                return false
            }
        }
    }
}

/// Best-effort read of the frontmost app's selected text. Accessibility first (no
/// clipboard side effects); falls back to a tagged synthetic Cmd-C with the pasteboard
/// saved and restored, for apps where AX selection is flaky (Electron, terminals).
enum SelectionText {
    static func read() async -> String? {
        if let s = axSelectedText(), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return await copyFallback()
    }

    static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let focused = ref else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let s = sel as? String else { return nil }
        return s
    }

    static func copyFallback() async -> String? {
        let board = NSPasteboard.general
        // Snapshot every pasteboard item so the user's clipboard survives the round-trip.
        let saved = board.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        let changeCountBefore = board.changeCount
        Paster.sendCopyKeystroke()
        try? await Task.sleep(nanoseconds: 180_000_000)
        // If the app didn't actually copy (no selection, or it ignored Cmd-C), the
        // pasteboard is untouched — its contents are whatever was there before, which
        // is often our own previous paste. changeCount only moves on a real write.
        guard board.changeCount != changeCountBefore else {
            log("selection: Cmd-C produced no pasteboard change; treating as no selection")
            return nil
        }
        let text = board.string(forType: .string)
        board.clearContents()
        if let saved {
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                board.writeObjects([item])
            }
        }
        return text
    }
}

/// Minimal floating panel: "Heard" field on top (what the engine misheard — the user
/// types it), "Correct" field below pre-filled with the selection. Add writes the pair;
/// the panel stays open on invalid input so the mistake can be fixed.
final class DictionaryPanel: NSPanel {
    private let heardField = NSTextField(string: "")
    private let writtenField = NSTextField(string: "")
    private var onSubmit: ((String, String) -> Bool)?

    static func present(written: String, onSubmit: @escaping (String, String) -> Bool) {
        let panel = DictionaryPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 170),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Add to Dictionary"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.writtenField.stringValue = written
        panel.onSubmit = onSubmit
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        panel.heardField.becomeFirstResponder()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])

        heardField.placeholderString = "what you said (the mishearing)"
        writtenField.placeholderString = "correct spelling"
        for field in [heardField, writtenField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 428).isActive = true
        }

        func labelledRow(_ label: String, _ field: NSTextField) -> NSStackView {
            let row = NSStackView(views: [NSTextField(labelWithString: label), field])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            return row
        }

        let hint = NSTextField(wrappingLabelWithString:
            "Maps the mishearing to the correct spelling for every future dictation.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        let add = NSButton(title: "Add", target: self, action: #selector(submit))
        add.keyEquivalent = "\r"
        add.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelOp))
        cancel.bezelStyle = .rounded
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(add)

        stack.addArrangedSubview(labelledRow("Heard:", heardField))
        stack.addArrangedSubview(labelledRow("Correct:", writtenField))
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(buttons)
    }

    @objc private func submit() {
        if onSubmit?(heardField.stringValue, writtenField.stringValue) == true { close() }
    }

    @objc private func cancelOp() { close() }

    override func cancelOperation(_ sender: Any?) { close() }
}
