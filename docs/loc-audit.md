# LOC audit — Buddadawg v0.2.0 tree (2026-11-12)

All counts are `wc -l` on the working tree as-is. "After" is this change only:
no feature was deleted; bigger cuts are listed as decisions below.
(Parallel v0.2.0 work landed more files while this audit ran; the table is the
tree at measurement time, and the lane files above still match it.)

## Baseline → after

| File | Before | After |
| --- | ---: | ---: |
| Sources/BarkBench/main.swift | 57 | 30 |
| Sources/CleanBench/main.swift | 49 | 29 |
| Sources/BarkCore/WavLoader.swift (new) | — | 36 |
| Sources/BarkCore/Decoder.swift | 130 | 130 |
| Sources/BarkCore/Formatter.swift | 220 | 220 |
| Sources/BarkCore/Frontend.swift | 71 | 71 |
| Sources/BarkCore/PhaseClock.swift | 30 | 30 |
| Sources/BarkCore/Transcriber.swift | 121 | 121 |
| Sources/Buddadawg/ (7 files) | 1058 | 1058 |
| Tests/BarkCoreTests/BarkCoreTests.swift | 92 | 92 |
| **Swift total** | **1828** | **1817** |
| scripts/bundle.sh | 47 | 47 |
| scripts/fetch_models.sh | 44 | 42 |
| scripts/install.sh | 15 | 15 |
| Package.swift | 18 | 18 |

Buddadawg/ detail (unchanged): main.swift 307, Overlay.swift 220,
MediaPauser.swift 174, Recorder.swift 137, Hotkey.swift 129, Paster.swift 63,
CleanTranscriber.swift 28.

## What changed

- The `.f32`/WAV loader (`loadAudio`, 13 lines) was byte-identical in both
  benches, and `footprintMB` (5 lines) was duplicated too; BarkBench also had
  `peakMB`. All three now live once in `Sources/BarkCore/WavLoader.swift` as
  `WavLoader.loadAudio` / `MemoryStats.{peakMB,footprintMB}`, logic copied
  verbatim (including the force-unwrap and `fatalError` — right for a bench).
  47 bench lines removed, one 36-line shared home added: net −11 Swift lines,
  and one copy to fix instead of two.
- `CleanBench` gained a `BarkCore` dependency in Package.swift (same line
  count; every other target/dependency untouched) and an `import BarkCore`.
- `scripts/fetch_models.sh`: the separate metadata.json loop (3 lines) folded
  into the per-component loop as one guarded line (Encoder ships no
  metadata.json). Same final file set; −2 lines. `bundle.sh`/`install.sh`
  were left alone: they hold no internal duplication — bundle's 14-line
  heredoc is the Info.plist itself, and the shared `set -eu` + `cd` prologue
  (2 lines × 3 scripts) would cost a common file plus a `source` line each,
  saving nothing.

Verified: `swift build --scratch-path /tmp/bd-loc-build` for `--target
BarkCore`, `--product BarkBench` and `--product CleanBench` all complete
(pre-existing Accelerate deprecation warnings in Decoder.swift only).

## Decision options (not taken)

### 1. Remove the Bark 3.0 fallback stack — saves ≈ 425 lines + model payload

Clean (FluidAudio) is the default engine; BarkCore's verbatim pipeline is the
fallback (`engine=bark`, or Clean load failure, in Buddadawg/main.swift).
Deletable if it went:

- BarkCore: Decoder.swift 130 + Frontend.swift 71 + Transcriber.swift 121 = 322
- BarkBench whole target: 30 (it exists to bench this stack + `--feats`)
- Tests tied only to Transcriber (`encodedLength`, `segments`): ≈ 22 of 92
- App plumbing in main.swift: fallback load block ≈ 18 lines plus the
  `barkTranscriber` decl/branch ≈ 6 (not in this lane; counted from source)
- fetch_models.sh Models/ block 14, scripts/convert_decoder.py 14,
  bundle.sh Models copy 1 line but the whole ANE package + decoder payload

Not deletable: Formatter.swift (220 — `DictationFormatter` tidies Clean output
too) and PhaseClock.swift (30 — Overlay), so BarkCore would shrink 608 → 286,
not vanish. Tradeoff: no on-device fallback if a FluidAudio/Core ML update
breaks the Clean path, and no verbatim mode; in exchange the bundle drops the
second model set and `--precompile`/first-launch gets simpler. This is the
only option with a three-digit saving.

### 2. Delete or merge the benches — saves 95 (delete) or ≈ 10–15 (merge)

BarkBench 30 + CleanBench 29 + WavLoader 36 (no app users) = 95 lines.
Deleting both loses the warm-timing/RAM regression check and BarkBench's
`--feats` frontend verification. Merging into one bench with an engine flag
saves little: the loops genuinely differ (sync `try` vs async decoder state,
5 warm runs/median index 2 vs 3/1, `--feats` is Bark-only), so a merged file
lands ≈ 45–50 lines against today's 59. Not recommended.

### 3. Remove demo mode — saves 26 lines

`runDemo()` is 25 lines in Buddadawg/main.swift (lines 198–222) plus its
one-line `--demo` call site. It fakes a voice level to loop the overlay
states without a mic. Removing it costs the only no-talking visual check of
the glow overlay; nothing else references it.

### 4. Remove the GPU units path — saves ≈ 3 lines (≈ 8 for ANE-only)

`Transcriber.Units.gpu` touches 4 lines in Transcriber.swift (the case, the
GPU package pick, the compute-units map, the `[15]` windows). Neither
fetch_models.sh nor bundle.sh ships `BarkEncoderGPU.mlpackage`, so in the
shipped app `gpu` is unreachable — only BarkBench with a hand-supplied models
dir can use it. Dropping just `.gpu` saves ≈ 3 lines; dropping `Units`
entirely (ANE-only) saves ≈ 8 across Transcriber.swift, main.swift's
`units` default lookup, and BarkBench's arg parse. Tradeoff: loses the
cpu/gpu comparison runs that justified ANE. Negligible either way while the
fallback stack (option 1) stays.
