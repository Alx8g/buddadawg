import Accelerate
import Foundation

/// decoder.bin + decoder.json (written by scripts/convert_decoder.py): raw arrays with dtype/shape/offset.
struct Weights {
    struct Entry: Decodable { let dtype: String; let shape: [Int]; let offset: Int }
    let blob: Data
    let index: [String: Entry]

    init(dir: URL) throws {
        blob = try Data(contentsOf: dir.appendingPathComponent("decoder.bin"), options: .alwaysMapped)
        index = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: dir.appendingPathComponent("decoder.json")))
    }

    private func raw<T>(_ name: String, _ type: T.Type) -> [T] {
        let e = index[name]!
        let count = e.shape.reduce(1, *)
        return blob.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: e.offset).assumingMemoryBound(to: T.self), count: count)) }
    }

    /// A float32 tensor: either stored as fp16/fp32, or as int8 rows `name.q` with per-row fp16 scales `name.s`.
    func float(_ name: String) -> [Float] {
        if let q = index[name + ".q"] {
            let codes = raw(name + ".q", Int8.self), scales = raw(name + ".s", Float16.self)
            let cols = q.shape.dropFirst().reduce(1, *)
            var out = [Float](repeating: 0, count: codes.count)
            for r in 0..<q.shape[0] {
                let s = Float(scales[r])
                for c in 0..<cols { out[r * cols + c] = Float(codes[r * cols + c]) * s }
            }
            return out
        }
        return index[name]!.dtype == "float16" ? raw(name, Float16.self).map(Float.init) : raw(name, Float.self)
    }
}

/// Greedy TDT decoding on the CPU, a port of Bark's numpy Decoder (= transformers' ParakeetForTDT.generate, batch 1).
public final class Decoder {
    public static let hidden = 640
    let emb, projW, projB, headW, headB: [Float]
    let lstm: [(wi: [Float], wh: [Float], b: [Float])]
    let vocabSize, blank, maxSymbols: Int
    let durations: [Int]
    let pieces: [String]
    let special: Set<Int>
    public let melFilters: [Float]

    struct Vocab: Decodable {
        let pieces: [String]; let special_ids: [Int]; let blank_id: Int; let vocab_size: Int
        let durations: [Int]; let max_symbols_per_step: Int
    }

    public init(dir: URL) throws {
        let w = try Weights(dir: dir)
        emb = w.float("decoder.embedding.weight")
        lstm = (0..<2).map { i in
            (w.float("decoder.lstm.weight_ih_l\(i)"), w.float("decoder.lstm.weight_hh_l\(i)"),
             vDSP.add(w.float("decoder.lstm.bias_ih_l\(i)"), w.float("decoder.lstm.bias_hh_l\(i)")))
        }
        projW = w.float("decoder.decoder_projector.weight"); projB = w.float("decoder.decoder_projector.bias")
        headW = w.float("joint.head.weight"); headB = w.float("joint.head.bias")
        melFilters = w.float("mel_filters")
        let v = try JSONDecoder().decode(Vocab.self, from: Data(contentsOf: dir.appendingPathComponent("vocab.json")))
        pieces = v.pieces; special = Set(v.special_ids); blank = v.blank_id; vocabSize = v.vocab_size
        durations = v.durations; maxSymbols = v.max_symbols_per_step
    }

    /// y = W x + b, W row-major [rows, cols].
    private func gemv(_ W: [Float], _ x: [Float], _ b: [Float], rows: Int) -> [Float] {
        var y = b
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(x.count), 1, W, Int32(x.count), x, 1, 1, &y, 1)
        return y
    }

    private func step(_ tok: Int, _ state: inout [(h: [Float], c: [Float])]) -> [Float] {
        let H = Self.hidden
        var x = Array(emb[(tok * H)..<(tok * H + H)])
        for l in 0..<2 {
            var g = gemv(lstm[l].wi, x, lstm[l].b, rows: 4 * H)
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(4 * H), Int32(H), 1, lstm[l].wh, Int32(H), state[l].h, 1, 1, &g, 1)
            var h = [Float](repeating: 0, count: H), c = state[l].c
            for j in 0..<H {  // gates in torch order: input, forget, cell, output
                let i = 1 / (1 + exp(-g[j])), f = 1 / (1 + exp(-g[H + j])), o = 1 / (1 + exp(-g[3 * H + j]))
                c[j] = f * c[j] + i * tanh(g[2 * H + j])
                h[j] = o * tanh(c[j])
            }
            state[l] = (h, c)
            x = h
        }
        return gemv(projW, x, projB, rows: H)
    }

    /// enc: [T * 640] projected encoder frames.
    public func decode(_ enc: [Float], frames T: Int) -> [Int] {
        let H = Self.hidden, outRows = headB.count
        var state = [(h: [Float], c: [Float])](repeating: ([Float](repeating: 0, count: H), [Float](repeating: 0, count: H)), count: 2)
        var dec = step(blank, &state)
        var t = 0, sym = 0, out: [Int] = []
        var joint = [Float](repeating: 0, count: H)
        while t < T {
            for j in 0..<H { joint[j] = max(enc[t * H + j] + dec[j], 0) }
            let logits = gemv(headW, joint, headB, rows: outRows)
            let tok = argmax(logits, 0, vocabSize)
            var d = durations[argmax(logits, vocabSize, outRows) - vocabSize]
            if tok == blank {
                t += max(d, 1); sym = 0
            } else {
                out.append(tok); dec = step(tok, &state); sym += 1
                if d == 0 && sym >= maxSymbols { d = 1 }
                if d > 0 { sym = 0 }
                t += d
            }
        }
        return out
    }

    private func argmax(_ a: [Float], _ lo: Int, _ hi: Int) -> Int {
        var best = lo
        for i in (lo + 1)..<hi where a[i] > a[best] { best = i }
        return best
    }

    public func detokenize(_ ids: [Int]) -> String {
        ids.filter { !special.contains($0) && $0 < pieces.count }.map { pieces[$0] }.joined()
            .replacingOccurrences(of: "▁", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
