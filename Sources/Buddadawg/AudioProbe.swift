import CoreAudio
import Foundation

/// Ground-truth probe for "is this process actually emitting audio right now?"
///
/// `kAudioProcessPropertyIsRunningOutput` stays true while a player merely holds the
/// output device open — a paused video keeps its WebKit helper flagged, which made
/// pause/resume guess wrong in both directions. A Core Audio process tap mixes the
/// candidate processes' output and measures the real PCM peak, so a paused stream reads
/// as silence and a playing one doesn't.
///
/// Returns nil whenever the tap can't be set up (older OS, HAL error) — callers must
/// treat nil as "unknown" and never as "playing": a blind media toggle is exactly what
/// unpauses a video the user paused themselves.
///
/// macOS only hands a process tap real samples when the bundle declares
/// `NSAudioCaptureUsageDescription` (see scripts/bundle.sh). Without it the tap starts
/// without error and every sample arrives as zero, which would read as "nothing is
/// playing" and quietly disable pausing instead of failing loudly.
enum AudioProbe {
    /// Peak absolute sample across `processObjectIDs`' mixed output over ~0.35 s.
    /// Process object IDs come from `kAudioHardwarePropertyProcessObjectList`.
    static func outputPeak(processObjectIDs: [AudioObjectID], duration: TimeInterval = 0.35) -> Float? {
        guard #available(macOS 14.2, *), !processObjectIDs.isEmpty else { return nil }
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.name = "buddadawg-probe"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            log("probe: AudioHardwareCreateProcessTap failed (\(describe(tapStatus)))")
            return nil
        }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        // Tap-only aggregate: the tap joins by UUID through the tap list, and with no
        // physical sub-device a duplex output's microphone can't be measured as playback.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "buddadawg-probe",
            kAudioAggregateDeviceUIDKey: "buddadawg-probe-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: 1,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            log("probe: aggregate device creation failed (\(describe(aggregateStatus)))")
            return nil
        }
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }

        let box = PeakBox()
        var ioProcID: AudioDeviceIOProcID?
        let ioProc: AudioDeviceIOProc = { _, _, inputData, _, _, _, refCon in
            guard let refCon else { return noErr }
            let box = Unmanaged<PeakBox>.fromOpaque(refCon).takeUnretainedValue()
            box.callbacks += 1
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
        guard procStatus == noErr, let ioProcID else {
            log("probe: IOProc creation failed (\(describe(procStatus)))")
            return nil
        }
        // An auto-started tap can already have the aggregate running; starting it again is
        // an illegal operation ('nope'), but an IOProc attached while running receives data
        // without an explicit start.
        let alreadyRunning = deviceIsRunning(aggregateID)
        if !alreadyRunning {
            let startStatus = AudioDeviceStart(aggregateID, ioProcID)
            guard startStatus == noErr else {
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
                log("probe: start failed (\(describe(startStatus)))")
                return nil
            }
        }
        Thread.sleep(forTimeInterval: duration)
        if !alreadyRunning { AudioDeviceStop(aggregateID, ioProcID) }
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        log("probe: callbacks=\(box.callbacks) peak=\(String(format: "%.4f", box.peak))")
        return box.peak
    }

    private static func deviceIsRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunning,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return running != 0
    }

    /// OSStatus rendered as number plus FourCC — 'nope' says far more about a HAL failure
    /// than the decimal alone.
    private static func describe(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                     UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        let text = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? "\(status)" : "\(status) '\(text)'"
    }

    /// IOProc callbacks arrive on a HAL realtime thread; a class box avoids atomics.
    private final class PeakBox { var peak: Float = 0; var callbacks = 0 }
}
