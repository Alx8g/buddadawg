import BarkCore
import Foundation

// barkbench <models dir> <units: ane|gpu|cpu|all> <audio.f32 | audio.wav>... [--feats ref.f32]
// Transcribes each clip, times it, and reports peak memory. With --feats, checks the frontend against a reference.

func loadAudio(_ path: String) -> [Float] {
    let data = FileManager.default.contents(atPath: path)!
    if path.hasSuffix(".f32") { return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
    // 16 kHz mono 16-bit PCM WAV: find the "data" chunk.
    var i = 12
    while i + 8 <= data.count {
        let id = String(data: data[i..<(i + 4)], encoding: .ascii)
        let size = Int(data[(i + 4)..<(i + 8)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        if id == "data" { return data[(i + 8)..<(i + 8 + size)].withUnsafeBytes { $0.bindMemory(to: Int16.self).map { Float($0) / 32768 } } }
        i += 8 + size
    }
    fatalError("no data chunk in \(path)")
}

func peakMB() -> Double {
    var info = rusage(); getrusage(RUSAGE_SELF, &info)
    return Double(info.ru_maxrss) / 1_048_576
}

/// Current physical footprint (what Activity Monitor shows as Memory), not the one-off compile peak.
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Double(info.phys_footprint) / 1_048_576
}

let args = CommandLine.arguments
let models = URL(fileURLWithPath: args[1]), units = Transcriber.Units(rawValue: args[2])!
let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BarkDictate")

if let i = args.firstIndex(of: "--feats") {
    let audio = loadAudio(args[3]), ref = loadAudio(args[i + 1])
    let d = try Decoder(dir: models)
    let (feats, frames, valid) = Frontend(melFilters: d.melFilters)([Float](repeating: 0, count: 4000) + audio)
    let maxErr = zip(feats, ref).map { abs($0 - $1) }.max()!
    print("frontend: \(frames) frames, \(valid) valid, ref \(ref.count / 128) frames, max abs diff \(maxErr)")
    exit(0)
}

var t0 = Date()
let tr = try await Transcriber(models: models, cache: cache, units: units)
print(String(format: "\(units.rawValue): load %.2f s", Date().timeIntervalSince(t0)))
for path in args.dropFirst(3) {
    let audio = loadAudio(path)
    t0 = Date(); let text = try tr.transcribe(audio); let first = Date().timeIntervalSince(t0)
    var times: [Double] = []
    for _ in 0..<5 { t0 = Date(); _ = try tr.transcribe(audio); times.append(Date().timeIntervalSince(t0)) }
    print(String(format: "  %.1f s clip | first %.0f ms | warm %.0f ms | RAM now %.0f MB (peak %.0f)", Double(audio.count) / 16000, first * 1000, times.sorted()[2] * 1000, footprintMB(), peakMB()))
    print("  \(text)")
}
