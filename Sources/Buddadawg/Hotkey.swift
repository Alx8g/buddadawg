import CoreGraphics
import Foundation

/// Hold-fn detection with a listen-only event tap.
/// - fn down starts, fn up finishes; any other key while fn is held cancels (fn + key is a shortcut, not dictation).
/// - If macOS switches the tap off it is re-enabled, and a 4 Hz watchdog finishes a recording whose fn release was swallowed.
final class Hotkey {
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}
    private(set) var active = false
    private var tap: CFMachPort?
    private static let fnKeycode: Int64 = 63

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
            guard let self, self.active, !Self.fnHeld() else { return }
            self.active = false
            self.onFinish()
        }
        return true
    }

    static func fnHeld() -> Bool { CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown where active:
            active = false
            onCancel()
        case .flagsChanged where event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeycode:
            let down = event.flags.contains(.maskSecondaryFn)
            if down && !active { active = true; onStart() }
            else if !down && active { active = false; onFinish() }
        default:
            break
        }
    }
}
