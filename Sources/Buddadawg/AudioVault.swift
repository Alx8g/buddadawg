import AVFoundation
import Foundation

/// Rolling local recovery vault for dictation audio: if a paste is lost or a transcription
/// looks wrong, the last few recordings survive on disk so they can be replayed or
/// re-transcribed later. Nothing here ever leaves the machine.
///
/// Privacy-first, and gated inside the vault itself rather than trusting call sites:
/// - `save` writes **nothing** unless `isEnabled` is true. The UserDefaults key defaults
///   to false when unset, so the feature is OFF until the user opts in, and the app may
///   call `save` unconditionally without risking a silent recording archive.
/// - Retention is bounded both ways: at most `maxEntries` files, none older than `maxAge`.
/// - The directory is mode 0700 and files 0600, and logs carry file names/sizes only —
///   never transcripts (there is no transcript here at all, by design).
/// Listing, pruning and `deleteAll` work whether or not the vault is enabled, so turning
/// it off can always be paired with wiping what is already stored.
enum AudioVault {
    /// One stored recording. `date` is the file's modification date (its save time).
    struct Entry: Equatable {
        let url: URL
        let date: Date
        let sizeBytes: Int64
        /// Playback length implied by the WAV payload (16-bit mono at `sampleRate`).
        var durationSeconds: Double {
            Double(max(0, sizeBytes - 44)) / 2 / Double(AudioVault.sampleRate)
        }
    }

    static let sampleRate = 16000            // Recorder's output format; WAVs are written in it verbatim
    static let maxEntries = 20
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxTotalBytes: Int64 = 250 * 1024 * 1024

    /// UserDefaults opt-in. Unset reads as false: the vault is off until explicitly enabled.
    static let enabledKey = "audioVaultEnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// ~/Library/Application Support/Buddadawg/Vault
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Buddadawg/Vault")
    }()

    private static let lock = NSLock()
    private static let nameFormatter: DateFormatter = {  // sortable, file-name safe; only used under `lock`
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    /// Saves one dictation's samples as a WAV and prunes. Returns the file URL, or nil when
    /// the vault is disabled, the audio is empty, or the write failed (logged, never thrown:
    /// a recovery nicety must not break the dictation that produced the audio). File I/O is
    /// synchronous — call from a background context, not the main thread.
    @discardableResult
    static func save(_ samples: [Float], at date: Date = Date()) -> URL? {
        guard isEnabled, !samples.isEmpty else { return nil }
        return lock.withLock {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                var url = directory.appendingPathComponent(nameFormatter.string(from: date) + ".wav")
                var n = 2
                while fm.fileExists(atPath: url.path) {  // same-millisecond back-to-back dictations
                    url = directory.appendingPathComponent(nameFormatter.string(from: date) + "-\(n).wav")
                    n += 1
                }
                try wavData(samples).write(to: url, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                log("vault: saved \(url.lastPathComponent) (\(samples.count) samples)")
                pruneLocked(now: date)
                return url
            } catch {
                log("vault: save failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// All stored recordings, newest first. A missing directory is simply an empty vault.
    static func entries() -> [Entry] { lock.withLock { entriesLocked() } }

    /// Total bytes currently held by the vault, for a menu/settings readout.
    static func totalSizeBytes() -> Int64 { entries().reduce(0) { $0 + $1.sizeBytes } }

    /// Reads a stored WAV back into the recorder's form: [Float] mono at `sampleRate`.
    /// AVAudioFile + AVAudioConverter tolerate foreign WAVs dropped in the folder
    /// (other rates/channel counts), not just our canonical 16-bit files. Returns nil
    /// on anything unreadable — callers treat that as "cannot re-transcribe".
    static func samples(_ entry: Entry) -> [Float]? {
        samples(at: entry.url)
    }

    static func samples(at url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let src = file.processingFormat
        guard let dst = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Double(sampleRate), channels: 1,
                                      interleaved: false),
              let converter = AVAudioConverter(from: src, to: dst) else { return nil }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src,
                                           frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: inBuf)) != nil else { return nil }
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * dst.sampleRate / src.sampleRate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: cap) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .endOfStream; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error, let ch = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }

    /// Enforces the retention bounds: drop anything older than `maxAge`, then all but the
    /// newest `maxEntries`. Runs automatically after every `save`; safe to call any time.
    static func prune(now: Date = Date()) { lock.withLock { pruneLocked(now: now) } }

    /// Removes one entry (e.g. after a successful re-transcription). Failures are logged.
    static func delete(_ entry: Entry) {
        lock.withLock {
            do { try FileManager.default.removeItem(at: entry.url) }
            catch { log("vault: delete \(entry.url.lastPathComponent) failed: \(error.localizedDescription)") }
        }
    }

    /// Removes every stored recording. Files that fail to delete stay listed by `entries()`
    /// afterwards, so callers can tell the wipe was incomplete instead of claiming success.
    static func deleteAll() {
        lock.withLock {
            let stored = entriesLocked()
            var removed = 0
            for entry in stored {
                do { try FileManager.default.removeItem(at: entry.url); removed += 1 }
                catch { log("vault: deleteAll could not remove \(entry.url.lastPathComponent): \(error.localizedDescription)") }
            }
            log("vault: deleteAll removed \(removed)/\(stored.count) files")
        }
    }

    // MARK: - Locked internals (call only with `lock` held)

    private static func entriesLocked() -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "wav" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Entry(url: url,
                             date: values?.contentModificationDate ?? values?.creationDate ?? .distantPast,
                             sizeBytes: Int64(values?.fileSize ?? 0))
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    private static func pruneLocked(now: Date) {
        // Newest first: keep entries inside all three bounds; the newest file is
        // always kept even if it alone exceeds the byte cap.
        var keptCount = 0
        var keptBytes: Int64 = 0
        for entry in entriesLocked() {
            let expired = entry.date < now.addingTimeInterval(-maxAge)
            let overBytes = keptCount > 0 && keptBytes + entry.sizeBytes > maxTotalBytes
            guard !expired, keptCount < maxEntries, !overBytes else {
                do { try FileManager.default.removeItem(at: entry.url) }
                catch { log("vault: prune could not remove \(entry.url.lastPathComponent): \(error.localizedDescription)") }
                continue
            }
            keptCount += 1
            keptBytes += entry.sizeBytes
        }
    }

    // MARK: - WAV encoding (canonical 44-byte header, 16-bit LE PCM, mono)

    private static func wavData(_ samples: [Float]) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func tag(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { for i in 0..<4 { data.append(UInt8((v >> (8 * i)) & 0xff)) } }
        func u16(_ v: UInt16) { data.append(UInt8(v & 0xff)); data.append(UInt8(v >> 8)) }
        let dataSize = UInt32(truncatingIfNeeded: samples.count * 2)
        tag("RIFF"); u32(36 + dataSize); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(1)                    // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2))    // rate, byte rate
        u16(2); u16(16)                                         // block align, bits/sample
        tag("data"); u32(dataSize)
        for sample in samples {
            let clamped = sample.isFinite ? min(max(sample, -1), 1) : 0
            u16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return data
    }
}
