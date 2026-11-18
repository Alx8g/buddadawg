import BarkCore
import FluidAudio
import Foundation

// cleanbench <models dir> <audio.wav>...
// Transcribes each clip with Bark 3.0 Clean (FluidAudio Core ML), times it, reports peak memory.

let args = CommandLine.arguments
let modelsDir = URL(fileURLWithPath: args[1])

var t0 = Date()
let models = try AsrModels.loadLocal(from: modelsDir, version: .bark3Clean)
let asr = AsrManager(config: .default)
try await asr.loadModels(models)
let layers = await asr.decoderLayerCount
print(String(format: "clean: load %.2f s", Date().timeIntervalSince(t0)))

for path in args.dropFirst(2) {
    let audio = WavLoader.loadAudio(path)
    func once() async throws -> String {
        var state = TdtDecoderState.make(decoderLayers: layers)
        return try await asr.transcribe(audio, decoderState: &state).text
    }
    t0 = Date(); let text = try await once(); let first = Date().timeIntervalSince(t0)
    var times: [Double] = []
    for _ in 0..<3 { t0 = Date(); _ = try await once(); times.append(Date().timeIntervalSince(t0)) }
    print(String(format: "  %.1f s clip | first %.0f ms | warm %.0f ms | RAM now %.0f MB", Double(audio.count) / 16000, first * 1000, times.sorted()[1] * 1000, MemoryStats.footprintMB()))
    print("  \(text)")
}
