import AppKit

/// Butter Dog easter egg: dictate the meme's catchphrase and the animated GIF plays
/// bottom-center for a few seconds — the Grain Horizon glow's bottom effect, but make
/// it the dog with the butter. The GIF itself cycles the meme text, so no extra labels.
final class MemePanel {
    private let panel: NSPanel
    private let imageView: NSImageView
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        if let gif = NSImage(contentsOf: Bundle.main.resourceURL!
                                .appendingPathComponent("butterdog.gif")) {
            imageView.image = gif
        }
        panel.contentView = imageView
    }

    /// Bottom-centre, sitting inside the glow zone; ~6 s then gone. Re-triggering
    /// restarts the timer rather than stacking panels.
    func celebrate() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let img = imageView.image, img.isValid else { return }
        let h: CGFloat = 200
        let w = h * img.size.width / img.size.height
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2,
                              y: screen.frame.minY + 4,
                              width: w, height: h), display: false)
        imageView.frame = NSRect(origin: .zero, size: panel.frame.size)
        if !panel.isVisible { panel.orderFrontRegardless() }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Whole-utterance-ish match for the meme's dog phrases. Deliberately forgiving:
    /// ASR renders "da dog wit da butter" a dozen ways, so the rule is "short utterance
    /// containing both a butter-word and a dog-word", plus the exact narration lines.
    static func matches(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard words.count <= 12 else { return false }
        let joined = words.joined(separator: " ")
        let exact = ["i put the butter on him", "i put da butter on him",
                     "put the butter on him", "put da butter on him",
                     "butter dog", "the butter dog", "buddadawg"]
        if exact.contains(joined) { return true }
        let butter = joined.contains("butter") || joined.contains("butta") || joined.contains("buter")
        let dog = joined.contains("dog") || joined.contains("dawg")
        return butter && dog
    }
}
