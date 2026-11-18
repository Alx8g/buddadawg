import AppKit

/// Live partial transcript while dictating: a borderless, click-through panel above
/// the Grain Horizon glow showing the latest streaming decode. Purely cosmetic —
/// the authoritative text still comes from the final transcription on fn release.
final class PartialHUD {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        label = NSTextField(labelWithString: "")
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.cell?.truncatesLastVisibleLine = true

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        label.autoresizingMask = [.width, .height]
        container.addSubview(label)
        panel.contentView = container
    }

    /// Shows `text` (empty hides). Keeps the panel bottom-centred above the overlay glow.
    func show(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let screen = NSScreen.main ?? NSScreen.screens.first else {
            hide()
            return
        }
        label.stringValue = trimmed
        let maxWidth = min(720, screen.frame.width * 0.62)
        let maxHeight: CGFloat = 120
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font as Any]
        let bounding = (trimmed as NSString).boundingRect(
            with: CGSize(width: maxWidth - 28, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let size = CGSize(width: min(maxWidth, max(bounding.width + 28, 120)),
                          height: min(maxHeight, bounding.height + 18))
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.minY + Overlay.height + 14,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        label.frame = NSRect(x: 14, y: 9, width: max(size.width - 28, 0), height: max(size.height - 18, 0))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
        label.stringValue = ""
    }
}
