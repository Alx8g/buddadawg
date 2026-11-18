import AppKit
import CoreAudio
import Darwin
import Foundation

/// Pauses whatever is playing (Music, Spotify, a browser's Now Playing session such as
/// YouTube) while you dictate, then resumes it afterwards — but only playback it paused.
///
/// Detection is layered because macOS restricts Now Playing details for unentitled apps:
/// on macOS 27 MediaRemote's IsPlaying/PID queries answer false/0 even during real playback
/// (observed live with IINA playing), so the working signal is the CoreAudio HAL process
/// list, which names every process currently running output audio IO. Commands prefer
/// MediaRemote's explicit Pause/Play (harmless when already in that state) over the
/// play/pause media key toggle. Every decision is logged with its signals.
final class MediaPauser {
    static let shared = MediaPauser()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "pauseMediaWhileDictating") == nil
            ? true : UserDefaults.standard.bool(forKey: "pauseMediaWhileDictating") }
        set { UserDefaults.standard.set(newValue, forKey: "pauseMediaWhileDictating") }
    }

    private enum Method { case mediaRemote, mediaKey }
    private var pausedByUs = false
    private var method: Method = .mediaRemote
    private var browserPausedByUs = false  // browser video has no Now Playing session; toggled via media key
    private var session = 0  // pause ownership: a resume only counts for the session that paused
    private let lock = NSLock()

    // MediaRemote (private framework, resolved at runtime so nothing breaks if it moves).
    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias PidFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int, Any?) -> Bool
    private lazy var handle: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private lazy var isPlayingFn: IsPlayingFn? = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
    private lazy var pidFn: PidFn? = symbol("MRMediaRemoteGetNowPlayingApplicationPID")
    private lazy var sendCommandFn: SendCommandFn? = symbol("MRMediaRemoteSendCommand")

    private func symbol<T>(_ name: String) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// Queries playback state (bounded to ~0.35 s), pauses if something is playing, then calls
    /// completion with a session token: pass it back to `resumeIfPausedByUs(session:)` so a
    /// slow transcription can't resume playback into the next dictation's microphone.
    func pauseIfPlaying(completion: @escaping (Int) -> Void) {
        let mine: Int = lock.withLock { session += 1; return session }
        guard enabled else { completion(mine); return }
        let done = NSLock()
        var finished = false
        var isPlaying: Bool?
        var pid: Int32?
        func finishOnce() {
            done.lock()
            guard !finished else { done.unlock(); return }
            finished = true
            let (playingNow, pidNow) = (isPlaying, pid)
            done.unlock()
            let outputRunning = Self.outputIsRunning()
            let hal = Self.outputProcesses()
            let halDesc = hal.map { "\($0.bundle):\($0.pid)" }.joined(separator: ",")
            // "Playing" needs a real signal: MediaRemote's isPlaying, a live now-playing app
            // that isn't explicitly paused, or a known media player holding output audio.
            // Any-process-with-output (rustdesk, browser helpers, etc.) does NOT count —
            // treating it as playback sent a Play command after every dictation, which
            // could launch Music.app.
            let halMedia = hal.contains { Self.isMediaBundle($0.bundle) }
            let playing = (playingNow ?? false)
                || ((pidNow ?? 0) > 0 && outputRunning && playingNow != false)
                || (halMedia && outputRunning)
            if playing {
                var used: Method = .mediaKey
                var sent: Bool?
                if let send = self.sendCommandFn {
                    sent = send(1, nil)  // kMRPause
                    if sent == true { used = .mediaRemote }
                }
                if used == .mediaKey { Self.postPlayPauseKey() }
                self.lock.withLock { self.pausedByUs = true; self.method = used }
                log("media: paused (isPlaying=\(String(describing: playingNow)), pid=\(String(describing: pidNow)), outputRunning=\(outputRunning), hal=[\(halDesc)], via \(used), sendResult=\(String(describing: sent)))")
            } else if (pidNow ?? 0) > 0 || playingNow != nil || halMedia {
                log("media: not playing (isPlaying=\(String(describing: playingNow)), pid=\(String(describing: pidNow)), outputRunning=\(outputRunning), hal=[\(halDesc)]); leaving playback alone")
            }
            // Browser video (e.g. Frame.io in Helium) registers no Now Playing session, so
            // MediaRemote stays empty — but the browser's helper process holds output audio
            // while a video actually plays. The media-key toggle is the only control that
            // reaches it; sent once here and once on resume.
            // Veto: a browser that DOES publish a Now Playing session (Chrome+YouTube)
            // can say "not playing" outright — trust that over the laggy HAL signal.
            // Helium/Frame.io publish nothing, so pid==0 there and the HAL path stays.
            var npPausedBrowser = false
            if let npPid = pidNow, npPid > 0, playingNow == false,
               let app = NSRunningApplication(processIdentifier: pid_t(npPid)),
               let bid = app.bundleIdentifier {
                npPausedBrowser = Self.browserBundles.contains { bid.hasPrefix($0) }
            }
            if !playing, !npPausedBrowser, Self.browserVideoLikelyPlaying() {
                Self.postPlayPauseKey()
                self.lock.withLock { self.browserPausedByUs = true }
                log("media: browser video toggle-pause (hal=[\(halDesc)])")
            } else if !playing, npPausedBrowser {
                log("media: browser helper output present but vetoed (npPausedBrowser=true)")
            }
            completion(mine)
        }
        let group = DispatchGroup()
        if let isPlayingFn {
            group.enter()
            isPlayingFn(DispatchQueue.global()) { v in done.lock(); isPlaying = v; done.unlock(); group.leave() }
        }
        if let pidFn {
            group.enter()
            pidFn(DispatchQueue.global()) { v in done.lock(); pid = v; done.unlock(); group.leave() }
        }
        group.notify(queue: .global()) { finishOnce() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { finishOnce() }
    }

    /// Resumes playback if (and only if) this session paused it and no newer dictation
    /// has started since. Safe to call repeatedly.
    func resumeIfPausedByUs(session mine: Int) {
        var didBrowser = false
        let (wasPaused, via): (Bool, Method) = lock.withLock {
            if browserPausedByUs, session == mine { browserPausedByUs = false; didBrowser = true }
            guard pausedByUs, session == mine else { return (false, method) }
            let v = (pausedByUs, method); pausedByUs = false; return v
        }
        if didBrowser {
            Self.postPlayPauseKey()
            log("media: browser video toggle-resume")
        }
        guard wasPaused else { return }
        switch via {
        case .mediaRemote:
            if let send = sendCommandFn, send(0, nil) {  // kMRPlay: harmless if already playing
                log("media: resumed via MediaRemote")
            } else if !Self.outputIsRunning() {
                Self.postPlayPauseKey()
                log("media: resumed via media key (MediaRemote play failed)")
            }
        case .mediaKey:
            if !Self.outputIsRunning() {
                Self.postPlayPauseKey()
                log("media: resumed via media key")
            } else {
                log("media: output already running; not toggling playPause")
            }
        }
    }

    /// Bundle-id prefixes of apps that plausibly play media. Used only as the HAL fallback:
    /// MediaRemote's Now Playing queries are gated on recent macOS, so players that don't
    /// publish Now Playing info (IINA, VLC, mpv…) are detected by holding output audio.
    /// Calls (FaceTime, Zoom, Teams) are deliberately absent — dictating shouldn't pause them.
    private static let mediaBundlePrefixes = [
        "com.apple.Music", "com.apple.TV", "com.apple.podcasts",
        "com.spotify.client", "tv.plex.plexamp",
        "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.Orion",
        "net.imput.helium", "company.thebrowser.Browser", "company.diabrowser",
        "com.apple.Safari", "com.colliderli.iina", "org.videolan.vlc", "com.movist.Movist",
        "io.mpv", "com.amazon.Lassen", "com.netflix.Netflix", "com.disney.disneyplus",
    ]

    /// A known browser's process (main or .helper — Chromium runs media audio through helper
    /// processes) is running output audio while nothing else claims playback. Browser video
    /// registers no Now Playing session, so this audio-output signal is the only tell. The
    /// helper's output lags real playback by ~10s, so a just-paused video can still read as
    /// "playing" for a moment; the toggle pair self-corrects on resume. Deliberately not
    /// gated on the browser being frontmost — dictating into another app shouldn't leave
    /// the video blaring.
    private static func browserVideoLikelyPlaying() -> Bool {
        outputProcesses().contains { proc in
            let bundle = resolvedBundle(pid: proc.pid, bundle: proc.bundle)
            return browserBundles.contains { base in
                bundle == base || bundle.hasPrefix(base + ".helper")
            }
        }
    }

    /// WebKit browsers (Safari, ZigZag, Orion…) play media audio through shared
    /// `com.apple.WebKit.*` XPC services spawned by launchd, so neither the HAL
    /// bundle id nor the process tree names the browser. `responsibility_get_pid_
    /// responsible_for_pid` returns the app that owns the XPC service — resolve it
    /// and non-browser WKWebView hosts (Slack, Mail…) stay excluded.
    // Signature is pid_t f(pid_t) — returns the responsible pid, 0 on failure.
    private typealias ResponsiblePidFn = @convention(c) (pid_t) -> pid_t
    private static let responsiblePidFn: ResponsiblePidFn? = {
        guard let p = dlsym(dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(p, to: ResponsiblePidFn.self)
    }()

    private static func resolvedBundle(pid: pid_t, bundle: String) -> String {
        guard bundle.hasPrefix("com.apple.WebKit."), let fn = responsiblePidFn else { return bundle }
        let responsible = fn(pid)
        guard responsible > 1,
              let app = NSRunningApplication(processIdentifier: responsible),
              let bid = app.bundleIdentifier, !bid.isEmpty else { return bundle }
        return bid
    }

    private static let browserBundles = [
        "net.imput.helium", "com.google.Chrome", "company.thebrowser.Browser",
        "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "company.diabrowser", "com.kagi.Orion",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "wang.zigao.zigzag",
    ]

    private static func isMediaBundle(_ bundle: String) -> Bool {
        // ".helper"/".helper.*" processes (browser helpers, rustdesk-style agents) hold audio
        // streams without playing media — they must not count.
        if bundle.contains(".helper") { return false }
        return mediaBundlePrefixes.contains { bundle.hasPrefix($0) }
    }

    /// Processes currently running output audio IO, per the HAL process object list.
    /// This is the reliable "something is playing" signal on macOS versions that gate
    /// MediaRemote queries. Our own process never counts (it only records input).
    private static func outputProcesses() -> [(pid: pid_t, bundle: String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        func uint(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
            var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var v: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(obj, &a, 0, nil, &s, &v)
            return v
        }
        var out: [(pid: pid_t, bundle: String)] = []
        for id in ids where uint(id, kAudioProcessPropertyIsRunningOutput) != 0 {
            let pid = pid_t(bitPattern: uint(id, kAudioProcessPropertyPID))
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bid: CFString = "" as CFString
            var s = UInt32(MemoryLayout<CFString>.size)
            _ = withUnsafeMutablePointer(to: &bid) { AudioObjectGetPropertyData(id, &a, 0, nil, &s, $0) }
            let bundle = bid as String
            if bundle == "co.alex.buddadawg" { continue }
            out.append((pid: pid, bundle: bundle))
        }
        return out
    }

    private static func outputIsRunning() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func postPlayPauseKey() {
        let nxKeytypePlay = 16
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (nxKeytypePlay << 16) | ((down ? 0xa : 0xb) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
