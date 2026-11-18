import CoreAudio
import Foundation

/// Ground-truth probe for "is this process actually emitting audio right now?"
///
/// `kAudioProcessPropertyIsRunningOutput` stays true while a player merely holds the
/// output device open — a paused browser video keeps its WebKit helper flagged, which
/// made pause/resume guess wrong in both directions. A Core Audio process tap mixes
/// the candidate processes' output and measures the real PCM peak, so a paused stream
/// reads as silence and a playing one doesn't.
///
/// Returns nil whenever the tap can't be set up (older OS, missing permission, HAL
/// error) — callers must treat nil as "unknown" and fall back to heuristics.
enum AudioProbe {
    /// Peak absolute sample across `processObjectIDs`' mixed output over ~0.35 s.
    /// Process object IDs come from `kAudioHardwarePropertyProcessObjectList`.
    static func outputPeak(processObjectIDs: [AudioObjectID], duration: TimeInterval = 0.35) -> Float? {
        guard #available(macOS 14.2, *), !processObjectIDs.isEmpty else { return nil }
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.name = "buddadawg-probe"
        tapDescription.isPrivate = true
        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr, tapID != kAudioObjectUnknown else {
            return nil
        }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        guard let aggregateID = makeAggregate(tapID: tapID) else { return nil }
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }

        let box = PeakBox()
        var ioProcID: AudioDeviceIOProcID?
        let ioProc: AudioDeviceIOProc = { _, _, inputData, _, _, _, refCon in
            guard let refCon else { return noErr }
            let box = Unmanaged<PeakBox>.fromOpaque(refCon).takeUnretainedValue()
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            for buffer in buffers {
                guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    let v = abs(samples[i])
                    if v > box.peak { box.peak = v }
                }
            }
            return noErr
        }
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard AudioDeviceCreateIOProcID(aggregateID, ioProc, context, &ioProcID) == noErr,
              AudioDeviceStart(aggregateID, ioProcID) == noErr else { return nil }
        Thread.sleep(forTimeInterval: duration)
        AudioDeviceStop(aggregateID, ioProcID)
        if let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
        return box.peak
    }

    /// Aggregate device wrapping the tap, mirroring Apple's process-tap recipe.
    private static func makeAggregate(tapID: AudioObjectID) -> AudioObjectID? {
        var defaultOutput = AudioDeviceID(kAudioObjectUnknown)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultOutput) == noErr else { return nil }
        var uid: CFString = "" as CFString
        addr.mSelector = kAudioDevicePropertyDeviceUID
        size = UInt32(MemoryLayout<CFString>.size)
        guard withUnsafeMutablePointer(to: &uid, { AudioObjectGetPropertyData(defaultOutput, &addr, 0, nil, &size, $0) }) == noErr else { return nil }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "buddadawg-probe",
            kAudioAggregateDeviceUIDKey: "buddadawg-probe-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [tapID],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr else { return nil }
        return aggregateID
    }

    /// IOProc callbacks arrive on a HAL realtime thread; a class box avoids atomics.
    private final class PeakBox { var peak: Float = 0 }
}
