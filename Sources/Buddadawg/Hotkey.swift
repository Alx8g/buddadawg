import AppKit
import CoreGraphics
import Foundation

/// Tap-fn dictation with a listen-only event tap:
/// - Tap fn once: start recording. Tap again: stop, transcribe, paste (no Enter).
/// - Double-tap fn while recording (two quick taps): stop, transcribe, paste AND press Enter.
/// - `autoSend` (the App's "Auto-Send" menu toggle): every stop sends — no double-tap
///   deferral, so transcription starts ~0.5 s sooner. fn presses are then suppressed for
///   one double-tap window after a finish, so a habitual second tap can't start a new
///   dictation by accident.
/// - A long press still works as push-to-talk: hold fn, release to finish.
/// - Double-tap fn within a few seconds after a paste re-sends the last dictation + Enter
///   (the App decides; the hotkey just reports the gesture via the send flag).
/// - Another key while fn is HELD cancels (fn + key is a shortcut, not dictation);
///   typing after a tap does not.
/// - If macOS switches the tap off it is re-enabled, and a 4 Hz watchdog finishes a held
///   recording whose fn release was swallowed (never while awaiting a confirming tap).
/// - Buddadawg's own synthetic keystrokes are tagged and ignored here.
final class Hotkey {
    var onStart: () -> Void = {}
    var onFinish: (Bool) -> Void = { _ in }  // send = the finishing gesture was a double-tap
    var onCancel: () -> Void = {}
    var autoSend = false
    /// Command Mode: the App started a capture itself (menu item, not fn). While true,
    /// the next fn press arms a finish instead of starting a new dictation — fnDown marks
    /// the press as a stop-press and fnUp reports it through onFinish like a normal tap.
    var externalCapture = false
    private(set) var active = false
    private var tap: CFMachPort?
    private var pressDownAt: Date?        // non-nil while a press is logically down
    private var presses = 0               // fn presses since recording started (1 = the starter tap)
    private var pressWasDoubleTap = false // this press's fnDown landed within doubleTapWindow of the last fnUp
    private var awaitingSecondTap = false // a stop-tap is deferred; a confirming tap turns it into send
    private var pendingFinishWasArmed = false  // a pendingFinish is scheduled; next fnDown confirms the double-tap
    private var pendingFinish: DispatchWorkItem?
    private var lastUpAt: Date?
    private var suppressUntil: Date?      // autoSend: swallow presses briefly after a finish
    private static let fnKeycode: Int64 = 63
    private static let globeKeycode: Int64 = 179  // keyDown macOS synthesises for a short fn/Globe tap; long holds never emit it
    private static let tapMax: TimeInterval = 0.45   // release sooner = tap; later = hold (push-to-talk)
    private static let doubleTapWindow = max(NSEvent.doubleClickInterval, 0.5)
    static let syntheticUserData: Int64 = 0x4244_4157  // "BDAW"

    /// Returns false if the tap couldn't be created (Accessibility permission missing).
    func install() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            // Only a press still logically down can have a swallowed release; after a starter
            // tap's fnUp, fn is legitimately up while recording continues (tap model).
            guard let self, self.active, self.pressDownAt != nil, self.pendingFinish == nil, !Self.fnHeld() else { return }
            log("watchdog: fn release was missed, finishing")
            self.finishNow(send: false)
        }
        return true
    }

    static func fnHeld() -> Bool { CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log("event tap disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown where event.getIntegerValueField(.eventSourceUserData) == Self.syntheticUserData:
            break  // our own paste/Return keystrokes, never a cancel
        case .keyDown where [Self.fnKeycode, Self.globeKeycode].contains(event.getIntegerValueField(.keyboardEventKeycode)):
            break  // fn itself, and the Globe tap event (179) macOS emits when fn is tapped, are not "another key"
        case .keyDown where active && pressDownAt != nil:
            // Only while fn is physically held: fn+key is a shortcut, not dictation.
            // After a starter tap, fn is up while recording continues — typing then is
            // normal work and must not cancel.
            log("cancel keyDown: keycode \(event.getIntegerValueField(.keyboardEventKeycode)), flags \(event.flags.rawValue), userData \(event.getIntegerValueField(.eventSourceUserData))")
            cancelNow()
        case .flagsChanged where event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeycode:
            if event.flags.contains(.maskSecondaryFn) { fnDown() } else { fnUp() }
        default:
            break
        }
    }

    private func fnDown() {
        if let until = suppressUntil {
            if Date() < until { return }  // autoSend cooldown: swallow the stray second tap
            suppressUntil = nil
        }
        pendingFinish?.cancel(); pendingFinish = nil
        pressDownAt = Date()
        pressWasDoubleTap = lastUpAt.map { Date().timeIntervalSince($0) < Self.doubleTapWindow } ?? false
        if !active, externalCapture {
            // Command Mode stop tap: behave like a second press so fnUp finishes,
            // but don't fire onStart — the App already started this capture.
            presses = 2
            active = true
            return
        }
        if active {
            presses += 1
            if pendingFinishWasArmed { awaitingSecondTap = true }
            return
        }
        presses = 1
        active = true
        onStart()
    }

    private func fnUp() {
        guard active, let downAt = pressDownAt else { return }
        pressDownAt = nil
        lastUpAt = Date()
        let held = Date().timeIntervalSince(downAt)
        if awaitingSecondTap {
            awaitingSecondTap = false
            finishNow(send: held < Self.tapMax)
            return
        }
        if presses == 1 {
            // The starter tap's release does NOT stop recording (tap model). A long first
            // press is push-to-talk: its release finishes.
            if held >= Self.tapMax { finishNow(send: false) }
            return
        }
        // A later press: long hold = plain stop; short tap = stop candidate, deferred so a
        // confirming tap (double-tap) can still turn it into paste+Enter — unless autoSend,
        // where every stop sends and there is nothing to wait for.
        if held >= Self.tapMax {
            finishNow(send: false)
        } else if autoSend {
            finishNow(send: true)
        } else {
            pendingFinishWasArmed = true
            let send = pressWasDoubleTap
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.active else { return }
                self.pendingFinish = nil
                self.pendingFinishWasArmed = false
                self.finishNow(send: send)
            }
            pendingFinish = work
            // Match the user's system double-click pace (at least 0.45 s): a shorter window
            // is faster than many people's second tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapWindow, execute: work)
        }
    }

    private func finishNow(send: Bool) {
        pendingFinish?.cancel(); pendingFinish = nil
        pendingFinishWasArmed = false
        awaitingSecondTap = false
        pressDownAt = nil
        presses = 0
        active = false
        if autoSend { suppressUntil = Date().addingTimeInterval(Self.doubleTapWindow) }
        onFinish(send)
    }

    private func cancelNow() {
        pendingFinish?.cancel(); pendingFinish = nil
        pendingFinishWasArmed = false
        awaitingSecondTap = false
        pressDownAt = nil
        presses = 0
        active = false
        onCancel()
    }
}
