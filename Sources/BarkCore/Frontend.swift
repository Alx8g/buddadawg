import Accelerate

/// Log-mel features, a port of Bark's numpy Frontend (itself transformers' ParakeetFeatureExtractor):
/// pre-emphasis, centred 512-point STFT with a 400-sample Hann window, slaney mel, log, per-utterance normalisation.
public struct Frontend {
    public static let sampleRate = 16000, hop = 160, nfft = 512, win = 400, bins = 257, mels = 128

    let mel: [Float]          // [128 * 257], row-major
    let window: [Float]       // [512], Hann(400) centred
    let fft: vDSP.FFT<DSPSplitComplex>

    public init(melFilters: [Float]) {
        mel = melFilters
        var w = [Float](repeating: 0, count: Self.nfft)
        let off = (Self.nfft - Self.win) / 2
        for i in 0..<Self.win {  // symmetric Hann, as numpy's np.hanning
            w[off + i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(Self.win - 1)))
        }
        window = w
        fft = vDSP.FFT(log2n: 9, radix: .radix2, ofType: DSPSplitComplex.self)!
    }

    /// Returns (features [frames * 128], frames, valid frames).
    public func callAsFunction(_ x: [Float]) -> (feats: [Float], frames: Int, valid: Int) {
        let L = x.count, half = Self.nfft / 2
        var xp = [Float](repeating: 0, count: L + Self.nfft)
        xp[half] = x[0]
        if L > 1 {
            // Pre-emphasis xp[half + i] = x[i] - 0.97 * x[i - 1] as a scale then a subtract:
            // each elementwise op is singly rounded, exactly like the scalar loop it replaces.
            var scaled = [Float](repeating: 0, count: L - 1)
            x.withUnsafeBufferPointer { src in
                scaled.withUnsafeMutableBufferPointer { tmp in
                    var coeff: Float = 0.97
                    vDSP_vsmul(src.baseAddress!, 1, &coeff, tmp.baseAddress!, 1, vDSP_Length(L - 1))
                    xp.withUnsafeMutableBufferPointer { dst in
                        vDSP_vsub(tmp.baseAddress!, 1, src.baseAddress! + 1, 1, dst.baseAddress! + half + 1, 1, vDSP_Length(L - 1))  // B - A
                    }
                }
            }
        }
        let n = 1 + (xp.count - Self.nfft) / Self.hop

        var power = [Float](repeating: 0, count: n * Self.bins)
        var frame = [Float](repeating: 0, count: Self.nfft)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var reSq = [Float](repeating: 0, count: half), imSq = [Float](repeating: 0, count: half)
        for f in 0..<n {
            xp.withUnsafeBufferPointer { src in
                vDSP.multiply(UnsafeBufferPointer(rebasing: src[(f * Self.hop)..<(f * Self.hop + Self.nfft)]), window, result: &frame)
            }
            re.withUnsafeMutableBufferPointer { r in
                im.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    frame.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half)) }
                    fft.forward(input: split, output: &split)
                }
            }
            // vDSP's real FFT is scaled by 2 and packs Nyquist into im[0].
            let base = f * Self.bins
            power[base] = (re[0] * 0.5) * (re[0] * 0.5)
            power[base + half] = (im[0] * 0.5) * (im[0] * 0.5)
            // power[base + k] = (re[k]^2 + im[k]^2) * 0.25 for 1..<half: square, add, scale,
            // the same singly-rounded ops in the same order as the scalar loop.
            re.withUnsafeBufferPointer { r in
                im.withUnsafeBufferPointer { i in
                    reSq.withUnsafeMutableBufferPointer { rs in
                        imSq.withUnsafeMutableBufferPointer { iq in
                            vDSP_vsq(r.baseAddress!, 1, rs.baseAddress!, 1, vDSP_Length(half))
                            vDSP_vsq(i.baseAddress!, 1, iq.baseAddress!, 1, vDSP_Length(half))
                            vDSP_vadd(rs.baseAddress! + 1, 1, iq.baseAddress! + 1, 1, rs.baseAddress! + 1, 1, vDSP_Length(half - 1))
                            power.withUnsafeMutableBufferPointer { p in
                                var scale: Float = 0.25
                                vDSP_vsmul(rs.baseAddress! + 1, 1, &scale, p.baseAddress! + base + 1, 1, vDSP_Length(half - 1))
                            }
                        }
                    }
                }
            }
        }

        // feats[n, 128] = log(power[n, 257] @ mel.T + 2^-24)
        var feats = [Float](repeating: 0, count: n * Self.mels)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(n), Int32(Self.mels), Int32(Self.bins),
                    1, power, Int32(Self.bins), mel, Int32(Self.bins), 0, &feats, Int32(Self.mels))
        vDSP.add(Float(0x1p-24), feats, result: &feats)
        vForce.log(feats, result: &feats)

        let valid = min(L / Self.hop, n)
        // Per-mel mean / std (ddof 1) over valid frames. Row-major accumulation keeps each
        // mel's additions in frame order, so the sums are bit-identical to the old
        // column-at-a-time loop, without its stride-128 access pattern.
        var means = [Float](repeating: 0, count: Self.mels)
        var stds = [Float](repeating: 0, count: Self.mels)
        feats.withUnsafeMutableBufferPointer { f in
            means.withUnsafeMutableBufferPointer { mn in
                for t in 0..<valid {
                    let base = t * Self.mels
                    for m in 0..<Self.mels { mn[m] += f[base + m] }
                }
                let denom = Float(max(valid, 1))
                for m in 0..<Self.mels { mn[m] /= denom }
                stds.withUnsafeMutableBufferPointer { sd in
                    for t in 0..<valid {
                        let base = t * Self.mels
                        for m in 0..<Self.mels { let d = f[base + m] - mn[m]; sd[m] += d * d }
                    }
                    let sdenom = Float(max(1, valid - 1))
                    for m in 0..<Self.mels { sd[m] = (sd[m] / sdenom).squareRoot() + 1e-5 }
                    for t in 0..<n {
                        let base = t * Self.mels
                        if t < valid {
                            for m in 0..<Self.mels { f[base + m] = (f[base + m] - mn[m]) / sd[m] }
                        } else {
                            for m in 0..<Self.mels { f[base + m] = 0 }
                        }
                    }
                }
            }
        }
        return (feats, n, valid)
    }
}
