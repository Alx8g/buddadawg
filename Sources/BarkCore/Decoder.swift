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
            let rows = q.shape[0], cols = q.shape.dropFirst().reduce(1, *)
            var out = [Float](repeating: 0, count: codes.count)
            // Int8 -> Float is exact and the per-row scale is one singly-rounded multiply,
            // so the vectorised dequant matches the scalar loop bit for bit.
            codes.withUnsafeBufferPointer { cp in
                out.withUnsafeMutableBufferPointer { op in
                    for r in 0..<rows {
                        var s = Float(scales[r])
                        let off = r * cols
                        vDSP_vflt8(cp.baseAddress! + off, 1, op.baseAddress! + off, 1, vDSP_Length(cols))
                        vDSP_vsmul(op.baseAddress! + off, 1, &s, op.baseAddress! + off, 1, vDSP_Length(cols))
                    }
                }
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

    /// Reusable buffers for one decode() call, so the per-frame / per-token loop allocates
    /// nothing. Created per call and never stored on self: concurrent decode() calls on one
    /// Decoder each get their own, exactly as the old per-step locals behaved.
    private final class Scratch {
        var g: [Float], x: [Float], dec: [Float], joint: [Float], logits: [Float]
        var h: [[Float]], c: [[Float]]

        init(logitCount: Int) {
            let H = Decoder.hidden
            g = [Float](repeating: 0, count: 4 * H)
            x = [Float](repeating: 0, count: H)
            dec = [Float](repeating: 0, count: H)
            joint = [Float](repeating: 0, count: H)
            logits = [Float](repeating: 0, count: logitCount)
            h = [[Float](repeating: 0, count: H), [Float](repeating: 0, count: H)]
            c = [[Float](repeating: 0, count: H), [Float](repeating: 0, count: H)]
        }
    }

    /// y = W x + b, W row-major [rows, cols], written into `y` (which must hold `rows` floats).
    private func gemv(_ W: [Float], _ x: [Float], _ b: [Float], rows: Int, into y: inout [Float]) {
        y.withUnsafeMutableBufferPointer { dst in
            b.withUnsafeBufferPointer { src in dst.baseAddress!.update(from: src.baseAddress!, count: rows) }
        }
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(x.count), 1, W, Int32(x.count), x, 1, 1, &y, 1)
    }

    /// One prediction-network step: advances the LSTM state in `s` and leaves the projected
    /// output in `s.dec`. Gate arithmetic is unchanged (libm exp/tanh, same order per lane);
    /// only bounds checks and per-step allocations are gone.
    private func step(_ tok: Int, _ s: Scratch) {
        let H = Self.hidden
        s.x.withUnsafeMutableBufferPointer { dst in
            emb.withUnsafeBufferPointer { src in dst.baseAddress!.update(from: src.baseAddress! + tok * H, count: H) }
        }
        var input = s.x
        for l in 0..<2 {
            gemv(lstm[l].wi, input, lstm[l].b, rows: 4 * H, into: &s.g)
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(4 * H), Int32(H), 1, lstm[l].wh, Int32(H), s.h[l], 1, 1, &s.g, 1)
            s.g.withUnsafeBufferPointer { g in
                s.h[l].withUnsafeMutableBufferPointer { h in
                    s.c[l].withUnsafeMutableBufferPointer { c in
                        for j in 0..<H {  // gates in torch order: input, forget, cell, output
                            let i = 1 / (1 + exp(-g[j])), f = 1 / (1 + exp(-g[H + j])), o = 1 / (1 + exp(-g[3 * H + j]))
                            c[j] = f * c[j] + i * tanh(g[2 * H + j])
                            h[j] = o * tanh(c[j])
                        }
                    }
                }
            }
            input = s.h[l]
        }
        gemv(projW, input, projB, rows: H, into: &s.dec)
    }

    /// enc: [T * 640] projected encoder frames.
    public func decode(_ enc: [Float], frames T: Int) -> [Int] {
        let H = Self.hidden, outRows = headB.count
        let s = Scratch(logitCount: outRows)
        step(blank, s)
        var t = 0, sym = 0, out: [Int] = []
        while t < T {
            enc.withUnsafeBufferPointer { e in
                s.dec.withUnsafeBufferPointer { d in
                    s.joint.withUnsafeMutableBufferPointer { jn in
                        let base = t * H
                        for j in 0..<H { jn[j] = max(e[base + j] + d[j], 0) }
                    }
                }
            }
            gemv(headW, s.joint, headB, rows: outRows, into: &s.logits)
            let tok = argmax(s.logits, 0, vocabSize)
            var d = durations[argmax(s.logits, vocabSize, outRows) - vocabSize]
            if tok == blank {
                t += max(d, 1); sym = 0
            } else {
                out.append(tok); step(tok, s); sym += 1
                if d == 0 && sym >= maxSymbols { d = 1 }
                if d > 0 { sym = 0 }
                t += d
            }
        }
        return out
    }

    private func argmax(_ a: [Float], _ lo: Int, _ hi: Int) -> Int {
        a.withUnsafeBufferPointer { p in
            var best = lo
            for i in (lo + 1)..<hi where p[i] > p[best] { best = i }
            return best
        }
    }

    public func detokenize(_ ids: [Int]) -> String {
        // Drop specials and every <|...|> control piece (emo tags, pnc/itn prompts, <unk> for quotes):
        // the model's control vocabulary must never reach the clipboard literally.
        ids.filter { !special.contains($0) && $0 < pieces.count && !pieces[$0].hasPrefix("<|") && pieces[$0] != "<unk>" }
            .map { pieces[$0] }.joined()
            .replacingOccurrences(of: "▁", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
