import AppKit
import AVFoundation
import BarkCore
import Carbon
import ServiceManagement

private let logQueue = DispatchQueue(label: "buddadawg.log")
/// Appends a timestamped line to ~/Library/Logs/Buddadawg.log (never the transcribed text itself).
/// Serialised on one queue so concurrent callers can't interleave bytes mid-line.
func log(_ message: String) {
    logQueue.async {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Buddadawg.log")
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// The last few dictations, kept in UserDefaults so a missed paste can be re-sent from the menu.
/// Deliberately small and local-only; Clear Recents wipes it.
enum Recents {
    private static let key = "recentDictations"
    static let cap = 8
    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func add(_ text: String) {
        var items = all.filter { $0 != text }
        items.insert(text, at: 0)
        UserDefaults.standard.set(Array(items.prefix(cap)), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Tap fn to start, tap again to stop: Bark 3.0 Clean transcribes on-device,
/// drops fillers and false starts, and the text is pasted at the cursor and left on the
/// clipboard so Cmd-V can re-send it. Bark 3.0 (verbatim) remains as a fallback engine.
final class App: NSObject, NSApplicationDelegate {
    let recorder = Recorder()
    let hotkey = Hotkey()
    let overlay = Overlay()
    var cleanTranscriber: CleanTranscriber?
    var barkTranscriber: Transcriber?
    // Media pausing is keyed by dictation epoch: each fn-down bumps it, and the pause
    // query's session token is stored under that epoch. A finish resumes only its own
    // dictation's pause — a newer dictation's in-flight pause can never be resumed early.
    private var mediaEpoch = 0
    private var mediaTokens: [Int: Int] = [:]
    private var mediaInFlight: Set<Int> = []
    private var mediaResumePending: Set<Int> = []
    private var transcriptionTail: Task<Void, Never>?
    private var transcriptionInFlight = false
    private var sendOnNextPaste = false
    private var lastPastedText: String?
    /// Command Mode (Apple Intelligence): menu-started capture that rewrites the
    /// current selection instead of pasting dictation. `pendingCommandSelection`
    /// holds the text grabbed before recording began.
    private var commandMode = false
    private var pendingCommandSelection: String?
    /// Smart Dictation (triple-tap fn): a normal dictation whose transcript gets a
    /// local LLM cleanup pass before pasting. The model pre-warms while the user
    /// speaks so the pass overlaps nothing.
    private var smartDictation = false
    /// Streaming preview: while a normal dictation records, re-decode the in-progress
    /// audio every ~1.8 s and show the partial text in PartialHUD. Cosmetic only —
    /// finish() still runs the authoritative final transcription. Decodes chain
    /// serially and skip while the final pass is running.
    let partialHUD = PartialHUD()
    /// Butter Dog easter egg: a dictated meme phrase plays the GIF bottom-centre.
    let memePanel = MemePanel()
    private var partialTimer: Timer?
    private var vaultPruneTimer: Timer?
    private var partialTail: Task<Void, Never>?
    private var partialBusy = false
    private var partialEpoch = 0
    /// Triple-tap veto data: the hotkey detects the tap rhythm; the App confirms the
    /// clip between tap1-2 wasn't real speech. Gesture clips contain fn-key clicks
    /// (peak ~0.02-0.03) but no voice (speech peaks 0.1+), so the threshold sits at 0.08.
    private var lastDictationSeconds: Double = .infinity
    private var lastDictationPeak: Float = 1
    private var lastDictationEnd = Date.distantPast
    private var armedUntil = Date.distantPast
    private static let armedWindow: TimeInterval = 6  // double-tap fn this long after a paste re-sends + Enter
    var engineName = ""
    /// Auto-Send (default on): every stop pastes AND presses Enter — no double-tap needed.
    /// The menu toggle flips it back to tap=paste / double-tap=Enter.
    var autoSendEnter: Bool { UserDefaults.standard.object(forKey: "enterAfterDictation") as? Bool ?? true }
    var ready: Bool { cleanTranscriber != nil || barkTranscriber != nil }
    var status: NSStatusItem!
    var statusLine: NSMenuItem!
    var recentsMenu: NSMenu!
    var vaultDeleteItem: NSMenuItem!
    var storedMenu: NSMenu!

    func applicationDidFinishLaunching(_ note: Notification) {
        // Two instances means two event taps, two mics and everything pasted twice. Keep exactly one.
        if let bid = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bid)
               .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            log("another Buddadawg instance is already running; quitting this one")
            NSApp.terminate(nil)
            return
        }
        // Launch at login is on by default; it's set only once so turning it off in the menu sticks.
        if !CommandLine.arguments.contains("--precompile"), !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
        Dictionary.seedIfNeeded()
        Snippets.ensureFile()
        AppRules.ensureFile()
        DispatchQueue.global(qos: .utility).async { AudioVault.prune() }
        vaultPruneTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async { AudioVault.prune() }
        }
        buildMenu()
        overlay.level = { [recorder] in recorder.level }
        if CommandLine.arguments.contains("--demo") { runDemo() }
        hotkey.onStart = { [self] in startCapture() }
        hotkey.onTripleTap = { [self] in
            // The hotkey confirmed three rapid taps and already armed this press as the
            // recording starter — a capture MUST begin either way. The veto below only
            // decides Smart Dictation vs plain: the clip between tap1-2 must have been
            // silence, or it was two quick dictations, not a gesture.
            if !commandMode, RewriteEngine.isAvailable,
               lastDictationSeconds < 1.6, lastDictationPeak < 0.08,
               Date().timeIntervalSince(lastDictationEnd) < 1.6 {
                smartDictation = true
                overlay.smart = true
                RewriteEngine.prewarm(prefix: RewriteEngine.cleanupInstructions)
                log("smart dictation: triple-tap detected")
            }
            startCapture()
        }
        hotkey.onCancel = { [self] in
            if commandMode {
                log("command mode cancelled by another key")
                stopPartialStreaming()
                _ = recorder.stop()
                commandMode = false
                hotkey.externalCapture = false
                pendingCommandSelection = nil
                smartDictation = false
                overlay.smart = false
                overlay.show(.cancelled)
                setStatus(readyStatus)
                return
            }
            log("cancelled by another key")
            stopPartialStreaming()
            _ = recorder.stop()
            smartDictation = false
            overlay.smart = false
            lastDictationSeconds = .infinity
            lastDictationPeak = 1
            resumeMedia()
            overlay.show(.cancelled)
        }
        hotkey.autoSend = autoSendEnter
        hotkey.onChordEngaged = { [self] in
            // fn-first chord: the dictation is already recording; just flag it smart.
            guard !commandMode, !smartDictation, RewriteEngine.isAvailable else { return }
            smartDictation = true
            overlay.smart = true
            RewriteEngine.prewarm(prefix: RewriteEngine.cleanupInstructions)
            log("smart dictation: fn+control chord (fn first)")
        }
        hotkey.onChord = { [self] in
            // fn+Control: explicit Smart Dictation — no silence veto needed, the
            // chord IS the intent. Degrades to plain dictation without Apple Intelligence.
            if !commandMode, RewriteEngine.isAvailable {
                smartDictation = true
                overlay.smart = true
                RewriteEngine.prewarm(prefix: RewriteEngine.cleanupInstructions)
                log("smart dictation: fn+control chord")
            }
            startCapture()
        }
        hotkey.onFinish = { [self] send in
            if commandMode { finishCommand() } else { finish(send: send) }
        }

        requestPermissions()
        Task { await loadModel() }
        // First run only: the onboarding window explains the app and walks the
        // permission grants. The flag is set by Onboarding's "Get Started".
        if !CommandLine.arguments.contains("--precompile"),
           !UserDefaults.standard.bool(forKey: Onboarding.completedKey) {
            showOnboarding()
        }
    }

    /// Mic + Accessibility requests, shared by launch and Onboarding's "Grant
    /// Permissions" button. Safe to call repeatedly: the mic prompt only appears
    /// while status is undetermined, and Hotkey.install() is idempotent.
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in log("mic access: \(ok)") }
        log("accessibility trusted = \(AXIsProcessTrusted())")
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            setStatus("Allow Accessibility, then relaunch")
        }
        if !hotkey.install() { setStatus("Allow Accessibility, then relaunch") }
    }

    private var onboarding: Onboarding?

    /// First run shows it automatically; "Show Onboarding…" in the menu re-opens it.
    @objc func showOnboarding() {
        if let onboarding { onboarding.show(); return }
        let created = Onboarding(app: self)
        onboarding = created
        created.show()
    }

    /// Shared capture start for fn taps and the triple-tap gesture: the mic must be
    /// live the instant fn goes down, so recording starts immediately and media pausing
    /// runs concurrently (it used to gate recorder.start behind up-to-0.35 s of Now
    /// Playing queries — fine for hold-fn, deadly for taps).
    private func startCapture() {
        log("fn down (model ready: \(ready), mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
        guard ready else {
            setStatus("Model still loading…")
            overlay.show(.cancelled)
            return
        }
        do {
            try recorder.start()
            overlay.show(.listening)
        } catch {
            log("recorder start failed: \(error.localizedDescription)")
            setStatus("Mic error: \(error.localizedDescription)")
            return
        }
        partialEpoch += 1
        mediaEpoch += 1
        let epoch = mediaEpoch
        mediaInFlight.insert(epoch)
        MediaPauser.shared.pauseIfPlaying { [self] token in
            DispatchQueue.main.async { [self] in
                mediaInFlight.remove(epoch)
                mediaTokens[epoch] = token
                if mediaResumePending.remove(epoch) != nil {
                    MediaPauser.shared.resumeIfPausedByUs(session: token)
                    mediaTokens.removeValue(forKey: epoch)
                }
            }
        }
        startPartialStreaming()
    }

    /// Kicks the ~1.8 s partial-decode cadence for the current recording. Re-armed on
    /// every capture start; stopped by stopPartialStreaming on finish/cancel.
    private func startPartialStreaming() {
        stopPartialStreaming()
        partialTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            self?.partialTick()
        }
    }

    private func stopPartialStreaming() {
        partialTimer?.invalidate()
        partialTimer = nil
        partialEpoch += 1
        partialHUD.hide()
    }

    /// One streaming step: snapshot the in-progress audio and queue a decode behind
    /// any partial still running. Clean-model only — the Bark fallback stays batch.
    /// Stale results are dropped via partialEpoch so a decode from a previous
    /// recording can never overwrite a new dictation's preview.
    private func partialTick() {
        guard recorder.isRecording, !commandMode, !transcriptionInFlight,
              !partialBusy, let transcriber = cleanTranscriber else { return }
        let epoch = partialEpoch
        let audio = recorder.snapshot()
        guard audio.count > 24000 else { return }  // under ~1.5 s: nothing worth decoding
        partialBusy = true
        let previous = partialTail
        partialTail = Task { [self] in
            _ = await previous?.result
            defer { Task { @MainActor in self.partialBusy = false } }
            do {
                let raw = try await transcriber.transcribe(audio)
                let text = DictationFormatter.format(Dictionary.apply(raw))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { [self] in
                    guard epoch == partialEpoch, recorder.isRecording else { return }
                    partialHUD.show(text)
                }
            } catch {
                // Partial decodes are best-effort; a failure just means no preview update.
            }
        }
    }

    var readyStatus: String {
        autoSendEnter ? "Ready (\(engineName)): tap fn, tap again to send"
                     : "Ready (\(engineName)): tap fn, double-tap for Enter"
    }

    func loadModel() async {
        let started = Date()
        setStatus("Loading model…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            if !ready { setStatus("Preparing model (one-time, a minute or so)…") }
        }
        let resources = Bundle.main.resourceURL!.appendingPathComponent("Models")
        let modelsClean = Bundle.main.resourceURL!.appendingPathComponent("ModelsClean")
        let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Buddadawg")

        // Primary engine: Bark 3.0 Clean (bundled Core ML). Set defaults `engine=bark` to skip it.
        if UserDefaults.standard.string(forKey: "engine") != "bark",
           FileManager.default.fileExists(atPath: modelsClean.appendingPathComponent("Encoder.mlmodelc").path) {
            do {
                let clean = try await CleanTranscriber(modelsDir: modelsClean)
                _ = try? await clean.transcribe([Float](repeating: 0, count: 16000))  // warm up
                cleanTranscriber = clean
                engineName = "Clean"
                log("Clean model ready in \(Int(Date().timeIntervalSince(started))) s")
                setStatus(readyStatus)
                if CommandLine.arguments.contains("--precompile") { exit(0) }
                return
            } catch {
                log("Clean model failed, falling back to Bark: \(error.localizedDescription)")
            }
        }
        // Fallback: the original Bark 3.0 (verbatim) pipeline in BarkCore.
        let units = Transcriber.Units(rawValue: UserDefaults.standard.string(forKey: "units") ?? "") ?? .ane
        do {
            let t = try await Transcriber(models: resources, cache: cache, units: units)
            _ = try t.transcribe([Float](repeating: 0, count: 16000))
            barkTranscriber = t
            engineName = "Bark fallback"
            log("Bark model ready in \(Int(Date().timeIntervalSince(started))) s")
            setStatus(cleanTranscriber == nil && UserDefaults.standard.string(forKey: "engine") != "bark"
                      ? "Ready (\(engineName)): tap fn — Clean failed to load" : readyStatus)
            try await t.loadRemaining()
            log("all Bark encoders ready in \(Int(Date().timeIntervalSince(started))) s")
            if CommandLine.arguments.contains("--precompile") { exit(0) }
        } catch {
            log("model failed: \(error.localizedDescription)")
            setStatus("Model failed: \(error.localizedDescription)")
        }
    }

    /// Resumes media paused for the dictation `epoch` (default: the current one), tolerating
    /// a pause query still in flight: if it hasn't completed yet the request is remembered
    /// and honoured on arrival.
    func resumeMedia(epoch: Int? = nil) {
        let e = epoch ?? mediaEpoch
        if mediaInFlight.contains(e) { mediaResumePending.insert(e); return }
        guard let token = mediaTokens.removeValue(forKey: e) else { return }
        MediaPauser.shared.resumeIfPausedByUs(session: token)
    }

    func finish(send: Bool) {
        stopPartialStreaming()
        let audio = recorder.stop()
        lastDictationSeconds = Double(audio.count) / 16000
        lastDictationEnd = Date()
        let wasSmart = smartDictation
        smartDictation = false
        overlay.smart = false
        let stats = recorder.lastStats
        lastDictationPeak = stats.peak
        let epoch = mediaEpoch
        let secureInput = IsSecureEventInputEnabled()
        if secureInput { log("secure input active: skipping audio vault and recents for this dictation") }
        log("fn up: \(audio.count / 16) ms of audio, peak level \(stats.peak), buffers \(stats.buffers), clamped \(stats.clampedSamples), send=\(send)")
        if audio.isEmpty, recorder.lastHeldSeconds > 0.5 {
            log("held \(String(format: "%.1f", recorder.lastHeldSeconds)) s but captured no audio; flagging instead of staying silent")
            setStatus("No audio captured — check your mic input in Sound settings")
            resumeMedia(epoch: epoch)
            overlay.show(.cancelled)
            return
        }
        guard audio.count > 1600, ready else { resumeMedia(epoch: epoch); overlay.show(.hidden); return }  // ignore taps under 0.1 s
        // A double-tap that captured no speech (peak under ~0.02 = room tone) is the send
        // gesture, not dictation — the pendingFinish deferral pads it past 1 s of silence,
        // so duration can't discriminate; loudness can. While a transcription is running,
        // flag its paste for Enter; within the armed window after a paste, re-send the last
        // dictation + Enter; otherwise the gesture is ignored.
        if send, stats.peak < 0.02 {
            if transcriptionInFlight {
                sendOnNextPaste = true
                resumeMedia(epoch: epoch)
                overlay.show(.transcribing)
            } else if !autoSendEnter, Date() < armedUntil, let last = lastPastedText {
                log("double-tap with no speech while armed: re-sending last dictation + Enter")
                resumeMedia(epoch: epoch)
                overlay.show(.pasted)
                Paster.pasteAndSend(last)
                armedUntil = Date().addingTimeInterval(Self.armedWindow)
            } else {
                log("double-tap with no speech and nothing to send; ignoring")
                resumeMedia(epoch: epoch)
                overlay.show(.hidden)
            }
            return
        }
        overlay.show(.transcribing)
        _ = transcribeAndDeliver(audio: audio, send: send, secureInput: secureInput,
                                 epoch: epoch, saveToVault: true, llmCleanup: wasSmart)
    }

    /// Shared transcription → format → paste tail for live dictation and vault
    /// re-transcription, so both get identical ordering, formatting and paste behaviour.
    /// Chains behind `transcriptionTail` so results always paste in request order.
    /// `epoch` resumes that dictation's media pause (nil when nothing was paused, e.g.
    /// re-transcription); `vaultEntry` is retained because synthetic paste has no delivery acknowledgement.
    @discardableResult
    func transcribeAndDeliver(audio: [Float], send: Bool, secureInput: Bool, epoch: Int?,
                              saveToVault: Bool, vaultEntry: AudioVault.Entry? = nil,
                              llmCleanup: Bool = false) -> Task<Void, Never> {
        transcriptionInFlight = true
        let previous = transcriptionTail
        let task = Task { [self] in
            _ = await previous?.result
            // A partial decode may still be inside AsrManager when fn releases;
            // AsrManager isn't documented reentrant, so let the partial chain drain
            // first — the final pass is authoritative anyway.
            _ = await partialTail?.result
            if saveToVault, !secureInput { AudioVault.save(audio) }  // no-op unless the user opted in
            let started = Date()
            do {
                let raw: String
                if let cleanTranscriber {
                    raw = try await cleanTranscriber.transcribe(audio)
                } else if let barkTranscriber {
                    raw = try await Task.detached(priority: .userInitiated) { try barkTranscriber.transcribe(audio) }.value
                } else { raw = "" }
                let formatted = DictationFormatter.format(Dictionary.apply(raw))
                // Whole-utterance snippet trigger ("snippet <name>") expands to canned
                // text. Matched on the formatted text BEFORE SpokenCommands.parse —
                // otherwise a trigger ending in "new line"/"period" etc. would have its
                // tail eaten as a command and never match. Canned text skips command
                // parsing and LLM cleanup.
                let snippet = Snippets.match(formatted)
                let parsed = snippet == nil ? SpokenCommands.parse(formatted) : nil
                let shouldDiscard = parsed?.shouldDiscard ?? false
                var text = snippet ?? parsed?.text ?? formatted
                if snippet != nil { log("snippet expanded") }
                log("transcribed \(text.count) chars in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(engineName))\(llmCleanup ? " [smart]" : "")")
                // Smart Dictation: polish the transcript with the on-device LLM. Any
                // failure falls back to the raw transcript — cleanup is best-effort.
                if llmCleanup, snippet == nil, !shouldDiscard, !text.isEmpty {
                    let cleanStart = Date()
                    if let cleaned = await RewriteEngine.cleanup(text) {
                        log("cleanup: \(text.count) -> \(cleaned.count) chars in \(Int(Date().timeIntervalSince(cleanStart) * 1000)) ms")
                        text = cleaned
                    } else {
                        log("cleanup unavailable; pasting raw transcript")
                    }
                }
                let finalText = text
                await MainActor.run { [self] in
                    transcriptionInFlight = false
                    if let epoch { resumeMedia(epoch: epoch) }
                    let enter = send || sendOnNextPaste || (autoSendEnter && AppRules.allowsSend())
                    sendOnNextPaste = false
                    if shouldDiscard {
                        log("discarded by spoken command")
                        overlay.show(.cancelled)
                        return
                    }
                    if finalText.isEmpty { overlay.show(.hidden); return }
                    if MemePanel.matches(finalText) { memePanel.celebrate() }
                    if !secureInput { Recents.add(finalText) }
                    rebuildRecents()
                    let payload = finalText.hasSuffix("\n") ? finalText : finalText + " "  // also leaves it on the clipboard for a manual Cmd-V
                    if enter { Paster.pasteAndSend(payload) } else { Paster.paste(payload) }
                    lastPastedText = finalText
                    armedUntil = Date().addingTimeInterval(Self.armedWindow)
                    overlay.show(.pasted)
                    setStatus(readyStatus)
                    if vaultEntry != nil {
                        refreshVaultMenu()
                        setStatus("Re-transcribed — audio kept for recovery")
                    }
                }
            } catch {
                log("transcription failed: \(error.localizedDescription)")
                await MainActor.run { [self] in
                    transcriptionInFlight = false
                    sendOnNextPaste = false
                    if let epoch { resumeMedia(epoch: epoch) }
                    setStatus("Transcription failed: \(error.localizedDescription)")
                    overlay.show(.hidden)
                }
            }
        }
        transcriptionTail = task
        return task
    }

    /// Command Mode: capture a spoken command for the current selection, then let
    /// Apple's on-device model rewrite it. The selection is read BEFORE recording so a
    /// missing selection fails fast; the fn tap that stops the capture is routed by
    /// `hotkey.externalCapture` so it can't start a normal dictation.
    @objc func commandSelection() {
        Task { @MainActor in
            guard RewriteEngine.isAvailable else {
                setStatus("Apple Intelligence isn't available on this Mac")
                return
            }
            guard ready, !commandMode, !recorder.isRecording else { return }
            guard !IsSecureEventInputEnabled() else {
                setStatus("Command Mode is off in password fields")
                return
            }
            guard let selection = await SelectionText.read(),
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                setStatus("Select some text first, then run Command Selection")
                return
            }
            do {
                try recorder.start()
            } catch {
                setStatus("Mic error: \(error.localizedDescription)")
                return
            }
            pendingCommandSelection = selection
            commandMode = true
            hotkey.externalCapture = true
            overlay.show(.listening)
            RewriteEngine.prewarm()
            setStatus("Command mode — say what to do, tap fn to finish")
        }
    }

    private func finishCommand() {
        stopPartialStreaming()
        let audio = recorder.stop()
        commandMode = false
        hotkey.externalCapture = false
        overlay.smart = false
        lastDictationSeconds = .infinity
        lastDictationPeak = 1
        let selection = pendingCommandSelection
        pendingCommandSelection = nil
        guard audio.count > 1600, let cleanTranscriber, let selection else {
            overlay.show(.hidden)
            setStatus(readyStatus)
            return
        }
        overlay.show(.transcribing)
        transcriptionInFlight = true
        let previous = transcriptionTail
        transcriptionTail = Task { [self] in
            // Same ordering as transcribeAndDeliver: AsrManager isn't documented
            // reentrant, so wait for earlier final and partial decodes to drain.
            _ = await previous?.result
            _ = await partialTail?.result
            defer { Task { @MainActor in self.transcriptionInFlight = false } }
            do {
                let sttStart = Date()
                let raw = try await cleanTranscriber.transcribe(audio)
                let command = DictationFormatter.format(Dictionary.apply(raw))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else {
                    await MainActor.run { overlay.show(.hidden); setStatus(readyStatus) }
                    return
                }
                log("command: \(command.count) chars (stt \(Int(Date().timeIntervalSince(sttStart) * 1000)) ms)")
                let llmStart = Date()
                let rewritten = try await RewriteEngine.rewriteChecked(selection, command: command)
                log("rewrite: \(selection.count) -> \(rewritten.count) chars in \(Int(Date().timeIntervalSince(llmStart) * 1000)) ms")
                await MainActor.run { [self] in
                    guard !rewritten.isEmpty else {
                        overlay.show(.hidden)
                        setStatus("Rewrite came back empty")
                        return
                    }
                    Paster.paste(rewritten)
                    overlay.show(.pasted)
                    setStatus("Rewritten — it replaced your selection")
                }
            } catch {
                log("command mode failed: \(error.localizedDescription)")
                await MainActor.run { [self] in
                    overlay.show(.hidden)
                    setStatus("Command failed: \(error.localizedDescription)")
                }
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
        recentsMenu = NSMenu()
        let recentsItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        recentsItem.submenu = recentsMenu
        menu.addItem(recentsItem)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let pauseMedia = NSMenuItem(title: "Pause Media While Dictating", action: #selector(togglePauseMedia(_:)), keyEquivalent: "")
        pauseMedia.state = MediaPauser.shared.enabled ? .on : .off
        menu.addItem(pauseMedia)
        let autoSend = NSMenuItem(title: "Auto-Send Dictation (Enter)", action: #selector(toggleAutoSend(_:)), keyEquivalent: "")
        autoSend.state = autoSendEnter ? .on : .off
        menu.addItem(autoSend)
        let vaultToggle = NSMenuItem(title: "Keep Audio for Recovery (7 days)", action: #selector(toggleAudioVault(_:)), keyEquivalent: "")
        vaultToggle.state = AudioVault.isEnabled ? .on : .off
        menu.addItem(vaultToggle)
        menu.addItem(NSMenuItem(title: "Open Audio Vault Folder", action: #selector(openVaultFolder), keyEquivalent: ""))
        storedMenu = NSMenu()
        let storedItem = NSMenuItem(title: "Stored Audio", action: nil, keyEquivalent: "")
        storedItem.submenu = storedMenu
        menu.addItem(storedItem)
        vaultDeleteItem = NSMenuItem(title: "Delete Stored Audio", action: #selector(deleteVaultAudio), keyEquivalent: "")
        menu.addItem(vaultDeleteItem)
        menu.addItem(NSMenuItem(title: "Edit Dictionary…", action: #selector(editDictionary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit Snippets…", action: #selector(editSnippets), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit App Rules…", action: #selector(editAppRules), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Onboarding…", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add Selection to Dictionary…", action: #selector(addSelectionToDictionary), keyEquivalent: ""))
        let commandItem = NSMenuItem(title: "Command Selection… (Apple Intelligence)", action: #selector(commandSelection), keyEquivalent: "")
        commandItem.isEnabled = RewriteEngine.isAvailable
        menu.addItem(commandItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Buddadawg", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = item.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        status.menu = menu
        rebuildRecents()
    }

    func refreshVaultMenu() {
        guard vaultDeleteItem != nil else { return }
        let entries = AudioVault.entries()
        vaultDeleteItem.isEnabled = !entries.isEmpty
        vaultDeleteItem.title = entries.isEmpty
            ? "Delete Stored Audio"
            : "Delete Stored Audio (\(entries.count) files, \(ByteCountFormatter.string(fromByteCount: AudioVault.totalSizeBytes(), countStyle: .file)))"
    }

    /// "Stored Audio" submenu: each vault WAV re-transcribes through the loaded engine
    /// and pastes the result (the file is retained — it is the recovery
    /// copy until then). Newest first, capped so the menu stays usable.
    func refreshStoredAudioMenu() {
        guard storedMenu != nil else { return }
        storedMenu.removeAllItems()
        let entries = AudioVault.entries()
        if entries.isEmpty {
            let none = NSMenuItem(title: "No stored audio", action: nil, keyEquivalent: "")
            none.isEnabled = false
            storedMenu.addItem(none)
            return
        }
        let df = DateFormatter(); df.dateFormat = "MMM d, HH:mm"
        for entry in entries.prefix(12) {
            let secs = Int(entry.durationSeconds)
            let item = NSMenuItem(title: "\(df.string(from: entry.date)) · \(secs / 60):\(String(format: "%02d", secs % 60))",
                                  action: #selector(retranscribeVault(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            storedMenu.addItem(item)
        }
        if entries.count > 12 {
            let more = NSMenuItem(title: "…and \(entries.count - 12) older", action: nil, keyEquivalent: "")
            more.isEnabled = false
            storedMenu.addItem(more)
        }
    }

    @objc func retranscribeVault(_ sender: NSMenuItem) {
        guard ready else { setStatus("Model still loading…"); return }
        guard let url = sender.representedObject as? URL,
              let entry = AudioVault.entries().first(where: { $0.url == url }) else { return }
        guard let samples = AudioVault.samples(entry) else {
            setStatus("Could not read stored audio")
            return
        }
        log("re-transcribing \(entry.url.lastPathComponent) (\(samples.count) samples)")
        setStatus("Re-transcribing…")
        overlay.show(.transcribing)
        _ = transcribeAndDeliver(audio: samples, send: false, secureInput: false,
                                 epoch: nil, saveToVault: false, vaultEntry: entry)
    }

    func rebuildRecents() {
        recentsMenu.removeAllItems()
        let items = Recents.all
        refreshVaultMenu()
        refreshStoredAudioMenu()
        if items.isEmpty {
            let none = NSMenuItem(title: "None yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentsMenu.addItem(none)
            return
        }
        for text in items {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let title = flat.count > 64 ? String(flat.prefix(64)) + "…" : flat
            let item = NSMenuItem(title: title, action: #selector(pasteRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = text
            item.toolTip = text
            recentsMenu.addItem(item)
        }
        recentsMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Recents", action: #selector(clearRecents), keyEquivalent: "")
        clear.target = self
        recentsMenu.addItem(clear)
    }

    /// Re-sends a recent dictation: copy to the clipboard and paste, so Cmd-V also works after.
    /// The small delay lets the menu close and the previous app regain focus first.
    @objc func pasteRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Paster.paste(text.hasSuffix("\n") ? text : text + " ") }
    }

    @objc func clearRecents() { Recents.clear(); rebuildRecents() }

    func setStatus(_ text: String) { log("status: " + text); DispatchQueue.main.async { self.statusLine.title = text } }

    @objc func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { setStatus("Login item: \(error.localizedDescription)") }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func togglePauseMedia(_ item: NSMenuItem) {
        MediaPauser.shared.enabled.toggle()
        item.state = MediaPauser.shared.enabled ? .on : .off
        log("pause media while dictating: \(MediaPauser.shared.enabled)")
    }

    @objc func toggleAutoSend(_ item: NSMenuItem) {
        let on = !autoSendEnter
        UserDefaults.standard.set(on, forKey: "enterAfterDictation")
        hotkey.autoSend = on
        item.state = on ? .on : .off
        log("auto-send enter: \(on)")
        setStatus(readyStatus)
    }

    @objc func toggleAudioVault(_ item: NSMenuItem) {
        AudioVault.isEnabled.toggle()
        item.state = AudioVault.isEnabled ? .on : .off
        log("audio vault enabled: \(AudioVault.isEnabled)")
        refreshVaultMenu()
    }

    @objc func deleteVaultAudio() {
        AudioVault.deleteAll()
        refreshVaultMenu()
        setStatus(AudioVault.entries().isEmpty ? readyStatus : "Some stored audio could not be deleted")
    }

    @objc func openVaultFolder() {
        if FileManager.default.fileExists(atPath: AudioVault.directory.path) {
            NSWorkspace.shared.open(AudioVault.directory)
        } else {
            setStatus("No stored audio yet")
        }
    }

    @objc func editDictionary() {
        Dictionary.seedIfNeeded()
        NSWorkspace.shared.open(Dictionary.file)
    }

    @objc func editSnippets() {
        Snippets.edit()
    }

    @objc func editAppRules() {
        AppRules.edit()
    }

    @MainActor @objc func addSelectionToDictionary() {
        AddToDictionary.prompt(app: self)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
