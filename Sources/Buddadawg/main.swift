import AppKit
import AVFoundation
import BarkCore
import ServiceManagement

/// Appends a timestamped line to ~/Library/Logs/Buddadawg.log (never the transcribed text itself).
func log(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Buddadawg.log")
    let line = "\(Date().formatted(.iso8601)) \(message)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

/// Hold fn, speak, release: Bark 3.0 transcribes on-device and the text is pasted at the cursor.
final class App: NSObject, NSApplicationDelegate {
    let recorder = Recorder()
    let hotkey = Hotkey()
    let overlay = Overlay()
    let work = DispatchQueue(label: "buddadawg.transcribe", qos: .userInteractive)
    var transcriber: Transcriber?
    var status: NSStatusItem!
    var statusLine: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        // Launch at login is on by default; it's set only once so turning it off in the menu sticks.
        if !CommandLine.arguments.contains("--precompile"), !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
        buildMenu()
        overlay.level = { [recorder] in recorder.level }
        if CommandLine.arguments.contains("--demo") { runDemo() }
        hotkey.onStart = { [self] in
            log("fn down (model ready: \(transcriber != nil), mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
            guard transcriber != nil else { return }
            do { try recorder.start(); overlay.show(.listening) } catch { setStatus("Mic error: \(error.localizedDescription)") }
        }
        hotkey.onCancel = { [self] in log("cancelled by another key"); _ = recorder.stop(); overlay.show(.cancelled) }
        hotkey.onFinish = { [self] in finish() }

        AVCaptureDevice.requestAccess(for: .audio) { ok in log("mic access: \(ok)") }
        log("launch: accessibility trusted = \(AXIsProcessTrusted())")
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            setStatus("Allow Accessibility, then relaunch")
        }
        if !hotkey.install() { setStatus("Allow Accessibility, then relaunch") }
        Task { await loadModel() }
    }

    func loadModel() async {
        let started = Date()
        setStatus("Loading model…")
        // A first load (or the first after a macOS update) compiles the encoder for the Neural Engine, which takes
        // minutes; say so instead of leaving a vague "Loading" up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            if transcriber == nil { setStatus("Preparing model (one-time, ~5 min)…") }
        }
        let resources = Bundle.main.resourceURL!.appendingPathComponent("Models")
        let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Buddadawg")
        let units = Transcriber.Units(rawValue: UserDefaults.standard.string(forKey: "units") ?? "") ?? .ane
        do {
            let t = try await Transcriber(models: resources, cache: cache, units: units)
            _ = try t.transcribe([Float](repeating: 0, count: 16000))  // warm up so the first dictation is as fast as the rest
            transcriber = t
            log("model ready in \(Int(Date().timeIntervalSince(started))) s")
            setStatus("Ready: hold fn to dictate")
            try await t.loadRemaining()  // the 15 s encoder compiles in the background; dictation already works
            log("all encoders ready in \(Int(Date().timeIntervalSince(started))) s")
            if CommandLine.arguments.contains("--precompile") { exit(0) }  // install-time warm-up: compile, cache, quit
        } catch {
            setStatus("Model failed: \(error.localizedDescription)")
        }
    }

    func finish() {
        let audio = recorder.stop()
        log("fn up: \(audio.count / 16) ms of audio, peak level \(audio.map(abs).max() ?? 0)")
        guard audio.count > 1600, let transcriber else { overlay.show(.hidden); return }  // ignore taps under 0.1 s
        overlay.show(.transcribing)
        work.async { [self] in
            let started = Date()
            let text = (try? transcriber.transcribe(audio)).map(Dictionary.apply) ?? ""
            log("transcribed \(text.count) chars in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            DispatchQueue.main.async { [self] in
                if text.isEmpty { overlay.show(.hidden); return }
                Paster.paste(text + " ")
                overlay.show(.pasted)
            }
        }
    }

    /// `--demo`: loops the overlay with a speech-like fake level (listen, paste, listen, cancel) so it can be seen without talking.
    func runDemo() {
        let start = Date()
        overlay.level = {
            let t = Date().timeIntervalSince(start)
            let syllables = max(0, sin(t * 9.1) * 0.6 + sin(t * 5.3 + 1) * 0.5 + sin(t * 13.7) * 0.25)
            let phrase = 0.5 + 0.5 * sin(t * 1.3)
            let gate = sin(t * 0.71) + sin(t * 1.9 + 0.4) > -1.1 ? 1.0 : 0.1
            return Float(min(1, (0.07 + syllables * 0.8 * (0.45 + 0.6 * phrase)) * gate))
        }
        var cycle = 0
        func loop() {
            overlay.show(.listening)
            let cancel = cycle % 3 == 2
            cycle += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + (cancel ? 2.5 : 4.5)) { [self] in
                if cancel { overlay.show(.cancelled) } else {
                    overlay.show(.transcribing)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { self.overlay.show(.pasted) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { loop() }
            }
        }
        loop()
    }

    func buildMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Buddadawg")
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Edit Dictionary…", action: #selector(editDictionary), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Buddadawg", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = item.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        status.menu = menu
    }

    func setStatus(_ text: String) { log("status: " + text); DispatchQueue.main.async { self.statusLine.title = text } }

    @objc func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { setStatus("Login item: \(error.localizedDescription)") }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func editDictionary() {
        let file = Dictionary.file
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# heard => written, one per line\ntail scale => Tailscale\n".write(to: file, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(file)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
