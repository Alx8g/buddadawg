import AppKit
import AVFoundation
import ApplicationServices

/// First-run onboarding: a single dark window shown once on launch that explains
/// what Buddadawg is, why it needs Mic + Accessibility, and the fn gestures —
/// with a "Grant Permissions" button wired to the same permission path the app
/// uses at launch (`App.requestPermissions()`). Re-openable any time from the
/// menu bar's "Show Onboarding…". Completion is persisted in UserDefaults under
/// `hasCompletedOnboarding`; dismissing is always allowed (permissions can be
/// granted later from System Settings).
final class Onboarding: NSObject {
    static let completedKey = "hasCompletedOnboarding"
    /// Wrap width for every text row: document 460 minus the stack's 20+20 insets.
    private static let textWidth: CGFloat = 420

    private let app: App
    private let panel: NSPanel
    private var statusTimer: Timer?
    private var micLabel: NSTextField!
    private var accessLabel: NSTextField!

    init(app: App) {
        self.app = app
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Welcome to Buddadawg"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        super.init()
        buildContent()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            self?.statusTimer?.invalidate()
            self?.statusTimer = nil
        }
    }

    /// Centres and fronts the window; permission statuses are polled once a
    /// second so grants made in System Settings show up without reopening.
    func show() {
        refreshPermissionStatus()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    @objc private func done() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        panel.close()
    }

    /// Same request path as launch: mic prompt + Accessibility check. The mic
    /// prompt only appears while status is undetermined, and Hotkey.install()
    /// is idempotent, so this is safe to press repeatedly.
    @objc private func grantPermissions() {
        app.requestPermissions()
        refreshPermissionStatus()
    }

    /// Accessibility can't be granted programmatically; the AX prompt's own
    /// "Open System Settings" button does the same thing, but a direct deep
    /// link is one less click for users who dismissed the prompt.
    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        } else {
            log("onboarding: could not build Accessibility settings URL")
        }
    }

    private func refreshPermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micLabel.stringValue = "Microphone: allowed"
        case .denied, .restricted: micLabel.stringValue = "Microphone: denied — enable it in System Settings"
        case .notDetermined: micLabel.stringValue = "Microphone: not asked yet"
        @unknown default: micLabel.stringValue = "Microphone: unknown"
        }
        accessLabel.stringValue = AXIsProcessTrusted()
            ? "Accessibility: allowed"
            : "Accessibility: not granted yet"
    }

    // MARK: - Layout

    private func buildContent() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
        ])

        // Fixed-width document so wrapping labels size predictably; the window
        // clips nothing because the stack scrolls instead. 460 leaves room for
        // the scroller inside the 480 pt window.
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: 460),
        ])
        scroll.documentView = document

        let title = NSTextField(wrappingLabelWithString: "Buddadawg")
        title.font = .boldSystemFont(ofSize: 24)
        title.textColor = .white

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body("Private dictation that lives on your Mac. " +
            "Tap fn, talk, tap fn again — the text is cleaned up and pasted at your cursor. " +
            "The audio and transcript never leave this machine."))

        stack.addArrangedSubview(spacer(6))
        stack.addArrangedSubview(heading("Permissions"))
        stack.addArrangedSubview(gestureRow("Microphone — ",
            "hears you only while fn is down; transcribed on-device, never uploaded."))
        micLabel = statusLabel()
        stack.addArrangedSubview(micLabel)
        stack.addArrangedSubview(gestureRow("Accessibility — ",
            "lets Buddadawg hear the fn key and paste text into other apps. macOS never " +
            "lets apps grant this themselves, so approve it in System Settings."))
        accessLabel = statusLabel()
        stack.addArrangedSubview(accessLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let grant = NSButton(title: "Grant Permissions", target: self, action: #selector(grantPermissions))
        grant.bezelStyle = .rounded
        grant.keyEquivalent = "\r"
        let settings = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibilitySettings))
        settings.bezelStyle = .rounded
        buttons.addArrangedSubview(grant)
        buttons.addArrangedSubview(settings)
        stack.addArrangedSubview(buttons)

        stack.addArrangedSubview(spacer(6))
        stack.addArrangedSubview(heading("Gestures"))
        // Keep in sync with Hotkey.swift's state machine.
        stack.addArrangedSubview(gestureRow("Tap fn", " — start dictating."))
        stack.addArrangedSubview(gestureRow("Tap fn again", " — stop: clean up, paste, and send (Enter)."))
        stack.addArrangedSubview(gestureRow("Hold fn", " — push-to-talk: hold, talk, release to finish."))
        stack.addArrangedSubview(gestureRow("Double-tap fn while recording", " — stop and send, same as tap-again with Auto-Send on."))
        stack.addArrangedSubview(gestureRow("fn + Control together", " — Smart Dictation: an on-device LLM cleans up the transcript."))
        stack.addArrangedSubview(gestureRow("Triple-tap fn", " — Smart Dictation fallback when the chord feels awkward."))
        stack.addArrangedSubview(gestureRow("Say “snippet <name>”", " — paste a canned snippet you defined."))
        stack.addArrangedSubview(gestureRow("Menu → Command Selection…", " — rewrite the text you have selected."))

        stack.addArrangedSubview(spacer(6))
        let tryIt = body("Try it now: tap fn and say something — the text pastes where your cursor is.", secondary: true)
        tryIt.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12.5),
                                                  toHaveTrait: .italicFontMask)
        stack.addArrangedSubview(tryIt)

        stack.addArrangedSubview(spacer(10))
        let doneButton = NSButton(title: "Get Started", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        stack.addArrangedSubview(doneButton)
    }

    private func heading(_ text: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = .boldSystemFont(ofSize: 13)
        f.textColor = .white
        f.preferredMaxLayoutWidth = Self.textWidth
        return f
    }

    private func body(_ text: String, secondary: Bool = false) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = .systemFont(ofSize: 12.5)
        f.textColor = secondary ? .secondaryLabelColor : .labelColor
        f.preferredMaxLayoutWidth = Self.textWidth
        return f
    }

    /// Status line under each permission: plain secondary text, refreshed by the timer.
    private func statusLabel() -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: "")
        f.font = .systemFont(ofSize: 11.5)
        f.textColor = .secondaryLabelColor
        f.preferredMaxLayoutWidth = Self.textWidth
        return f
    }

    /// Bold lead-in (the gesture or permission name) followed by a dimmer
    /// explanation — one attributed string so the pair wraps as a single line.
    private func gestureRow(_ lead: String, _ rest: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: "")
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: lead,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12.5), .foregroundColor: NSColor.white]))
        attr.append(NSAttributedString(string: rest,
            attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.secondaryLabelColor]))
        f.attributedStringValue = attr
        f.preferredMaxLayoutWidth = Self.textWidth
        return f
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
}
