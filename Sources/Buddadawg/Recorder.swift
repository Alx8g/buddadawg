import AVFoundation

/// Captures the default mic as 16 kHz mono floats while recording, and exposes a live level for the overlay.
final class Recorder {
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false
    /// 0...1, smoothed RMS of the latest buffer; read from the main thread for animation.
    private(set) var level: Float = 0
    private var noiseFloor: Float = -60  // dB; learned background noise (fans, hum) so only your voice moves the overlay
    private var freshPress = false       // the first buffer after fn goes down is usually just the room, so it seeds the floor

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: format, to: target)
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        level = 0
        freshPress = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.append(buffer) }
        try engine.start()
        isRecording = true
    }

    /// Stops the mic and returns everything captured since `start`.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        let chunk = UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
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
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
