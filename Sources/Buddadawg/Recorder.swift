import AVFoundation
import CoreAudio

/// Captures the default mic as 16 kHz mono floats while recording, and exposes a live level for the overlay.
/// A fresh AVAudioEngine is built for every dictation so a wedged input route can never poison
/// the next recording (the old shared engine could end up capturing zero samples until relaunch).
final class Recorder {
    struct Stats {
        var buffers = 0
        var samples = 0
        var clampedSamples = 0   // samples outside -1...1, clamped before they reach the model
        var convertErrors = 0
        var peak: Float = 0
    }

    private var engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false
    /// 0...1, smoothed RMS of the latest buffer; read from the main thread for animation.
    private(set) var level: Float = 0
    private var noiseFloor: Float = -60  // dB; learned background noise (fans, hum) so only your voice moves the overlay
    private var freshPress = false       // the first buffer after fn goes down is usually just the room, so it seeds the floor
    private var startedAt: Date?
    private(set) var lastStats = Stats()
    private(set) var lastHeldSeconds: Double = 0
    private var stats = Stats()

    init() {
        // The engine stops itself when the audio route changes; restart it so an in-flight
        // dictation survives a device switch instead of recording silence.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            guard let self, self.isRecording else { return }
            log("audio configuration changed mid-recording; restarting engine")
            do { try self.engine.start() } catch { log("engine restart failed: \(error.localizedDescription)") }
        }
    }

    func start() throws {
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Buddadawg", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input available"])
        }
        guard let conv = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "Buddadawg", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not convert mic format \(format)"])
        }
        converter = conv
        log("recorder start: \(Self.defaultInputDeviceName()), \(format.channelCount)ch @ \(Int(format.sampleRate)) Hz")
        lock.withLock { samples.removeAll(keepingCapacity: true); stats = Stats() }
        level = 0
        freshPress = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.append(buffer) }
        engine.prepare()
        try engine.start()
        startedAt = Date()
        isRecording = true
    }

    /// Stops the mic and returns everything captured since `start`.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        lastHeldSeconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        return lock.withLock { lastStats = stats; return samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var convError: NSError?
        converter.convert(to: out, error: &convError) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        let raw = UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
        var clamped = 0
        var peak: Float = 0
        let chunk = raw.map { v -> Float in
            peak = max(peak, abs(v))
            if v > 1 || v < -1 { clamped += 1 }
            return min(max(v, -1), 1)
        }
        let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1))).squareRoot()
        // Loudness in decibels, mapped -55 dB (room tone) ... -15 dB (loud speech) onto 0...1, so normal talking already
        // moves the overlay a lot; raw RMS barely registers for speech.
        let db = 20 * log10(max(rms, 1e-6))
        // Track the background noise floor: drop to quiet moments quickly, creep up slowly (~1 dB/s at 46 buffers/s)
        // so speech itself doesn't raise it. Only sound clearly above the floor counts, with a soft ramp, not a cut-off.
        if freshPress { noiseFloor = db; freshPress = false }
        noiseFloor = db < noiseFloor ? noiseFloor + (db - noiseFloor) * 0.3 : noiseFloor + 0.02
        let above = db - (noiseFloor + 6)
        level = level * 0.6 + min(max(above / 30, 0), 1) * 0.4
        lock.withLock {
            samples.append(contentsOf: chunk)
            stats.buffers += 1
            stats.samples += chunk.count
            stats.clampedSamples += clamped
            stats.peak = max(stats.peak, peak)
            if convError != nil {
                stats.convertErrors += 1
                if stats.convertErrors == 1 { log("converter error: \(convError!.localizedDescription)") }
            }
        }
    }

    private static func defaultInputDeviceName() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return "unknown input"
        }
        var name: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioObjectPropertyName
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (name as String) : "unknown input"
    }
}
