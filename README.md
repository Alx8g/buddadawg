# Buddadawg 🧈🐶

<p align="center"><img src="https://media.tenor.com/Esbsny0YGXoAAAAM/butta-dawg-dog-with-the-butta.gif" alt="The dog with the butter on him" width="260"></p>

Hold **fn**, speak, let go: your words are transcribed on-device and pasted at the cursor, in any app. A grainy light
rises from the bottom of the screen while you talk and follows your voice.

Native Swift, no Python and no network. It uses [Bark 3.0](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0)
(Conway Research's 163 MB English model built from NVIDIA Parakeet TDT 0.6B v3), with the encoder running on the Apple
Neural Engine.

## Numbers (M1 Pro, 32 GB)

| | Buddadawg (Swift, Neural Engine) | Earlier Python/MLX version |
|---|---|---|
| RAM while idle | **~115–160 MB** | ~840 MB |
| Launch to ready | **0.5 s** (after the one-time compile) | ~4.5 s |
| 3 s clip → text | ~100 ms | ~70 ms |
| 15 s clip → text | ~350 ms | ~240 ms |
| Real dictation | 1.4 s of speech pasted in 166 ms | |

The text output matches Bark's Python reference implementation word for word, and the Swift log-mel frontend matches
the numpy reference to within 6e-5.

On held-out English test sets Bark 3.0 averages 4.94% word error rate, the same as Parakeet TDT 0.6B v3 at 1/15 the
size, and in our own tests it made about half as many mistakes as Whisper base.en, which Parrot and similar apps
default to.

## Install

Needs macOS 15+, Apple Silicon and Xcode Command Line Tools (`xcode-select --install`). Xcode itself is not needed.

```sh
git clone <this repo> && cd buddadawg
./scripts/install.sh
```

The install script does four things:
1. Downloads the model from Hugging Face (~200 MB).
2. Builds the app and signs it with a local self-signed identity, so macOS keeps its permissions across rebuilds.
3. Installs it to `/Applications`.
4. Pre-compiles the encoder for the Neural Engine, which takes about 5 minutes the first time.

On first launch, allow **Microphone** and **Accessibility** when asked. Accessibility is needed to see the fn key and
to paste. If fn opens the emoji picker, go to System Settings → Keyboard and set "Press 🌐 key to" to **Do Nothing**.

## Use

- **Hold fn** to record. Release to transcribe and paste. Your clipboard is put back afterwards.
- **fn + any other key** cancels, so fn shortcuts still work.
- **Menu bar (waveform icon):** shows status, Launch at Login (on by default), and Edit Dictionary… (one
  `heard => written` fix per line, for example `tail scale => Tailscale`).
- **`--demo`:** loops the overlay with fake speech. Run `open "/Applications/Buddadawg.app" --args --demo`.
- **Log:** `~/Library/Logs/Buddadawg.log` records timings and state, never what you said.

## How it works

```
Sources/
  BarkCore/        engine (Accelerate + Core ML, no dependencies)
    Frontend       log-mel features: pre-emphasis, 512-pt vDSP FFT, slaney mel, per-utterance norm
    Transcriber    Core ML encoder (8 s and 15 s windows) with compiled-model cache; long audio split at pauses
    Decoder        TDT greedy decoding (2-layer LSTM + joint) with cblas, int8 weights expanded at load
  Buddadawg/       menu bar app
    Hotkey         listen-only CGEventTap on fn; re-enables itself, 4 Hz watchdog for missed releases
    Recorder       AVAudioEngine → 16 kHz mono; dB level with an adaptive noise floor (fans don't move it)
    Overlay        full-width click-through panel, Metal shader, renders only while visible
    Paster         clipboard + ⌘V, previous clipboard restored; dictionary replacements
  BarkBench/       CLI: speed, RAM and frontend-accuracy checks against Python reference dumps
scripts/           fetch_models, convert_decoder (npz → raw blob for Swift), bundle, install
```

Notes and gotchas:
- **First-compile time.** Core ML compiles the encoder for the Neural Engine on first load, which takes minutes. The
  result is cached per app and survives rebuilds, but a macOS update clears it.
  - The 8 s encoder loads first, so dictation works while the 15 s one compiles in the background.
  - The CPU path isn't usable as a fallback, because the fp16 encoder overflows there.
- **GPU vs Neural Engine.** The GPU package also works, but it only has a 15 s window, so short clips are slower. On
  first use it briefly spikes to about 10 GB of RAM.
- **Signing.** The bundle script pins the designated requirement to the bundle id and the certificate. A self-signed
  identity otherwise falls back to a cdhash requirement, so every rebuild would lose the Accessibility grant.

## Credits

- Speech model: **Underdog Bark 3.0** by Conway Research, licensed CC-BY-4.0 (see `NOTICE`, fetched with the model).
  It is derived from NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0).
- The engine is a Swift port of Bark's own Core ML reference script (`bark_coreml.py`).
