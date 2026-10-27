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
        for i in 1..<L { xp[half + i] = x[i] - 0.97 * x[i - 1] }
        let n = 1 + (xp.count - Self.nfft) / Self.hop

        var power = [Float](repeating: 0, count: n * Self.bins)
        var frame = [Float](repeating: 0, count: Self.nfft)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
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
            for k in 1..<half { power[base + k] = (re[k] * re[k] + im[k] * im[k]) * 0.25 }
        }

        // feats[n, 128] = log(power[n, 257] @ mel.T + 2^-24)
        var feats = [Float](repeating: 0, count: n * Self.mels)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(n), Int32(Self.mels), Int32(Self.bins),
                    1, power, Int32(Self.bins), mel, Int32(Self.bins), 0, &feats, Int32(Self.mels))
        vDSP.add(Float(pow(2.0, -24.0)), feats, result: &feats)
        vForce.log(feats, result: &feats)

        let valid = min(L / Self.hop, n)
        for m in 0..<Self.mels {  // per-mel mean / std (ddof 1) over valid frames
            var mean: Float = 0
            for t in 0..<valid { mean += feats[t * Self.mels + m] }
            mean /= Float(max(valid, 1))
            var ss: Float = 0
            for t in 0..<valid { let d = feats[t * Self.mels + m] - mean; ss += d * d }
            let std = (ss / Float(max(1, valid - 1))).squareRoot() + 1e-5
            for t in 0..<n { feats[t * Self.mels + m] = t < valid ? (feats[t * Self.mels + m] - mean) / std : 0 }
        }
        return (feats, n, valid)
    }
}
