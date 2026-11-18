import Accelerate
import CoreML
import Foundation

/// Bark 3.0: Core ML encoder (fixed 8 s / 15 s windows) + CPU TDT decoder. Port of Bark's bark_coreml.py.
public final class Transcriber {
    public enum Units: String, CaseIterable { case ane, gpu, cpu, all }
    static let pad = 4000  // 0.25 s of lead-in silence, the setting Bark was evaluated with

    let decoder: Decoder
    let frontend: Frontend
    // Window length in seconds -> encoder. The ANE package has 8 s and 15 s functions, the GPU package only 15 s.
    // Each one compiles separately (minutes on a first launch), so the shortest loads first and the rest follow via
    // `loadRemaining()`; until then longer audio is simply cut into shorter pieces.
    private var encoders: [Int: MLModel] = [:]
    private let lock = NSLock()
    private let compiled: URL
    private let config: MLModelConfiguration
    private let allWindows: [Int]
    var windows: [Int] { lock.withLock { encoders.keys.sorted() } }

    /// `models` holds BarkEncoder{ANE,GPU}.mlpackage, decoder.bin/json and vocab.json.
    /// The package is compiled once into `cache`; later launches load the compiled copy directly.
    public init(models: URL, cache: URL, units: Units) async throws {
        decoder = try Decoder(dir: models)
        frontend = Frontend(melFilters: decoder.melFilters)
        let package = models.appendingPathComponent(units == .gpu ? "BarkEncoderGPU.mlpackage" : "BarkEncoderANE.mlpackage")
        compiled = try await Self.compiledModel(package, cache: cache)
        config = MLModelConfiguration()
        config.computeUnits = [.ane: .cpuAndNeuralEngine, .gpu: .cpuAndGPU, .cpu: .cpuOnly, .all: .all][units]!
        allWindows = units == .gpu ? [15] : [8, 15]
        try await load(allWindows[0])
    }

    /// Loads the longer-window encoders after the first one is ready.
    public func loadRemaining() async throws {
        for w in allWindows.dropFirst() where !windows.contains(w) { try await load(w) }
    }

    private func load(_ w: Int) async throws {
        let c = config.copy() as! MLModelConfiguration
        c.functionName = allWindows.count > 1 ? "w\(w)" : nil
        let model = try await MLModel.load(contentsOf: compiled, configuration: c)
        lock.withLock { encoders[w] = model }
    }

    static func compiledModel(_ package: URL, cache: URL) async throws -> URL {
        let weights = package.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
        let size = (try FileManager.default.attributesOfItem(atPath: weights.path)[.size] as? Int) ?? 0
        let target = cache.appendingPathComponent("\(package.deletingPathExtension().lastPathComponent)-\(size).mlmodelc")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let temp = try await MLModel.compileModel(at: package)
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }

    /// 16 kHz mono samples in, text out.
    public func transcribe(_ wave: [Float]) throws -> String {
        try segments(wave).map { try decoder.detokenize(piece($0)) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    func piece(_ audio: [Float]) throws -> [Int] {
        let x = [Float](repeating: 0, count: Self.pad) + audio
        let (feats, frames, valid) = frontend(x)
        let available = lock.withLock { encoders }
        let w = available.keys.sorted().first { x.count <= $0 * Frontend.sampleRate } ?? available.keys.max()!
        let T = w * 100 + 1
        let f = try MLMultiArray(shape: [1, NSNumber(value: T), 128], dataType: .float16)
        let m = try MLMultiArray(shape: [1, NSNumber(value: T)], dataType: .int32)
        let fp = f.dataPointer.assumingMemoryBound(to: Float16.self), mp = m.dataPointer.assumingMemoryBound(to: Int32.self)
        // Bulk Float -> Float16 (vImage rounds to nearest even, identical to scalar Float16());
        // the freshly allocated MLMultiArray is contiguous, as the old linear fill assumed.
        let filled = min(frames, T) * 128
        if filled > 0 {
            feats.withUnsafeBufferPointer { src in
                var sbuf = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress!),
                                          height: 1, width: vImagePixelCount(filled), rowBytes: filled * 4)
                var dbuf = vImage_Buffer(data: UnsafeMutableRawPointer(fp),
                                          height: 1, width: vImagePixelCount(filled), rowBytes: filled * 2)
                _ = vImageConvert_PlanarFtoPlanar16F(&sbuf, &dbuf, vImage_Flags(kvImageNoFlags))
            }
        }
        if filled < T * 128 { (fp + filled).update(repeating: 0, count: T * 128 - filled) }
        let ones = Swift.max(0, Swift.min(valid, T))
        mp.update(repeating: 1, count: ones)
        if ones < T { (mp + ones).update(repeating: 0, count: T - ones) }

        let input = try MLDictionaryFeatureProvider(dictionary: ["features": f, "mask": m])
        let out = try available[w]!.prediction(from: input).featureValue(for: "encoded")!.multiArrayValue!
        let n = Self.encodedLength(valid), H = Decoder.hidden
        var enc = [Float](repeating: 0, count: n * H)
        let s1 = out.strides[1].intValue, s2 = out.strides[2].intValue
        out.withUnsafeBytes { raw in
            if out.dataType == .float16 {
                let p = raw.bindMemory(to: Float16.self)
                if s2 == 1 {  // contiguous rows: one bulk conversion per frame
                    enc.withUnsafeMutableBufferPointer { dst in
                        for t in 0..<n {
                            var sbuf = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: p.baseAddress! + t * s1),
                                                      height: 1, width: vImagePixelCount(H), rowBytes: H * 2)
                            var dbuf = vImage_Buffer(data: UnsafeMutableRawPointer(dst.baseAddress! + t * H),
                                                      height: 1, width: vImagePixelCount(H), rowBytes: H * 4)
                            _ = vImageConvert_Planar16FtoPlanarF(&sbuf, &dbuf, vImage_Flags(kvImageNoFlags))
                        }
                    }
                } else {
                    for t in 0..<n { for j in 0..<H { enc[t * H + j] = Float(p[t * s1 + j * s2]) } }
                }
            } else {
                let p = raw.bindMemory(to: Float.self)
                if s2 == 1 {
                    enc.withUnsafeMutableBufferPointer { dst in
                        for t in 0..<n { (dst.baseAddress! + t * H).update(from: p.baseAddress! + t * s1, count: H) }
                    }
                } else {
                    for t in 0..<n { for j in 0..<H { enc[t * H + j] = p[t * s1 + j * s2] } }
                }
            }
        }
        guard enc.allSatisfy(\.isFinite) else { throw NSError(domain: "Bark", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-finite encoder output"]) }
        return decoder.decode(enc, frames: n)
    }

    static func encodedLength(_ n: Int) -> Int {  // three stride-2 convs, k=3, pad=1
        var n = n
        for _ in 0..<3 { n = (n - 1) / 2 + 1 }
        return n
    }

    /// Audio longer than the largest loaded window (15 s once everything is loaded) is cut in the middle of the quietest
    /// 200 ms within each stretch of a third to a full window, so no word is split.
    func segments(_ x: [Float]) -> [[Float]] { Self.segments(x, longestWindow: windows.max() ?? 15) }

    public static func segments(_ x: [Float], longestWindow longest: Int) -> [[Float]] {
        let maxLen = Int((Double(longest) - 0.25) * Double(Frontend.sampleRate)), minLen = longest * Frontend.sampleRate / 3
        if x.count <= maxLen { return [x] }
        let fr = Frontend.sampleRate / 100
        var e = (0..<(x.count / fr)).map { i in x[(i * fr)..<(i * fr + fr)].reduce(0) { $0 + $1 * $1 } / Float(fr) }
        e = e.indices.map { i in  // 200 ms moving average (divide by the actual count at the edges)
            let lo = max(0, i - 10), hi = min(e.count, i + 10)
            return e[lo..<hi].reduce(0, +) / Float(hi - lo)
        }
        var out: [[Float]] = [], start = 0
        while x.count - start > maxLen {
            let lo = (start + minLen) / fr, hi = (start + maxLen) / fr
            let cut = (lo + (e[lo..<hi].enumerated().min { $0.element < $1.element }!.offset)) * fr + fr / 2
            out.append(Array(x[start..<cut])); start = cut
        }
        out.append(Array(x[start...]))
        return out
    }
}
