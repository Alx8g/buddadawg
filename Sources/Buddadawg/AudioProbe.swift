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
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            log("probe: AudioHardwareCreateProcessTap failed (\(tapStatus))")
            return nil
        }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        guard let aggregateID = makeAggregate(tapUUID: tapDescription.uuid) else {
            log("probe: aggregate device creation failed")
            return nil
        }
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
        let procStatus = AudioDeviceCreateIOProcID(aggregateID, ioProc, context, &ioProcID)
        let startStatus = procStatus == noErr ? AudioDeviceStart(aggregateID, ioProcID) : procStatus
        guard procStatus == noErr, startStatus == noErr else {
            log("probe: IOProc create/start failed (\(procStatus)/\(startStatus))")
            return nil
        }
        Thread.sleep(forTimeInterval: duration)
        AudioDeviceStop(aggregateID, ioProcID)
        if let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
        return box.peak
    }

    /// Tap-only aggregate device: taps join by UUID through the tap list. No physical
    /// sub-device, so a duplex output's microphone can't be measured as playback.
    private static func makeAggregate(tapUUID: UUID) -> AudioObjectID? {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "buddadawg-probe",
            kAudioAggregateDeviceUIDKey: "buddadawg-probe-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: 1,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr else { return nil }
        return aggregateID
    }

    /// IOProc callbacks arrive on a HAL realtime thread; a class box avoids atomics.
    private final class PeakBox { var peak: Float = 0 }
}
