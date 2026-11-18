import Foundation

/// Bench audio loading: raw little-endian `.f32` samples, or a 16 kHz mono 16-bit PCM WAV
/// (found via its `data` chunk). Shared by BarkBench and CleanBench; deliberately fatal on
/// bad input, as a bench should be.
public enum WavLoader {
    public static func loadAudio(_ path: String) -> [Float] {
        let data = FileManager.default.contents(atPath: path)!
        if path.hasSuffix(".f32") { return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
        var i = 12
        while i + 8 <= data.count {
            let id = String(data: data[i..<(i + 4)], encoding: .ascii)
            let size = Int(data[(i + 4)..<(i + 8)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            if id == "data" { return data[(i + 8)..<(i + 8 + size)].withUnsafeBytes { $0.bindMemory(to: Int16.self).map { Float($0) / 32768 } } }
            i += 8 + size
        }
        fatalError("no data chunk in \(path)")
    }
}

/// Process memory for bench reporting, in MB.
public enum MemoryStats {
    /// Peak RSS (includes the one-off model-compile spike).
    public static func peakMB() -> Double {
        var info = rusage(); getrusage(RUSAGE_SELF, &info)
        return Double(info.ru_maxrss) / 1_048_576
    }

    /// Current physical footprint (what Activity Monitor shows as Memory), not the compile peak.
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return Double(info.phys_footprint) / 1_048_576
    }
}
