import FluidAudio
import Foundation

/// Underdog Bark 3.0 Clean via FluidAudio's Core ML pipeline (ANE encoder). The Clean
/// checkpoint drops fillers, false starts and repeated words in-model, so dictated
/// text arrives ready to use. Models are the bundled bark-3.0-clean .mlmodelc set
/// (FluidInference/bark-3.0-coreml), loaded locally: nothing is downloaded at runtime.
final class CleanTranscriber {
    private let asr = AsrManager(config: .default)
    private var decoderLayers = 2

    init(modelsDir: URL) async throws {
        let models = try AsrModels.loadLocal(from: modelsDir, version: .bark3Clean)
        try await asr.loadModels(models)
        decoderLayers = await asr.decoderLayerCount
    }

    /// 16 kHz mono samples in, cleaned text out. A fresh decoder state per dictation.
    func transcribe(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await asr.transcribe(samples, decoderState: &state)
        // Bark emits <unk> where training text had a quotation mark; current FluidAudio drops it,
        // but strip defensively so a tag can never reach the clipboard.
        return result.text
            .replacingOccurrences(of: "<unk>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
