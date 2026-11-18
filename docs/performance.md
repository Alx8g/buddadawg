# Performance — BarkCore dictation path

Scope of this pass: output-identical optimisations in `Sources/BarkCore/Formatter.swift`,
`Frontend.swift`, `Decoder.swift` and `Transcriber.swift` only. "Identical" here means
bit-for-bit where the code is numeric (features, dequantised weights, tokens) and byte-for-byte
for formatter text. Anything that would merely be *close* (vForce sigmoid/tanh in the LSTM gates,
quantised GEMV, reassociated reductions) was deliberately not done; see "Not done" notes.

All measurements on the development M1 Pro. Micro-numbers come from a same-process
original-vs-new harness compiled `-O` (sources lived in `/tmp/bd-perf-harness`, not committed);
end-to-end numbers from `BarkBench` built before/after into private scratch paths
(`/tmp/bd-perf-before`, `/tmp/bd-perf-after`). Micro runs are single runs under a loaded machine
(parallel work in the same checkout): treat percentages as indicative, not exact.

## Baseline

BarkBench (Bark 3.0 engine, `ane` units, `Models/`), warm = median-of-5 as printed by the bench:

| Clip | Baseline (supplied) | Baseline (re-measured this pass) | After this pass |
| --- | --- | --- | --- |
| `t1_short.wav`, 2.2 s | ~89–102 ms warm | 86 ms warm | 86 ms warm |
| `t4_long.wav` | 134 s clip: ~2.8 s warm | file on disk is 23.0 s: 485 ms warm | 484 ms warm |
| `t2_numbers.wav`, 8.5 s | — | 232 ms warm | 233 ms warm |
| Clean engine (FluidAudio, other lane) | 134 s in ~0.72 s | not re-measured | — |
| `Transcriber` init ("load", bench process) | — | 175 s | 157 s |

Transcripts for t1/t2/t4 are byte-identical before vs after (diff-clean). The 134 s figure could
not be re-measured: `/tmp/buddadawg-tests/t4_long.wav` currently contains 23.0 s of audio.

Headline: **end-to-end warm latency is unchanged within ±1 ms noise.** That is expected — the
warm path is dominated by the CoreML encoder and by the decoder re-reading its LSTM weights
from memory for every emitted token (worked estimate: 2 layers × 2 matrices of 2560×640 Float
≈ 26 MB streamed per token step, before the joint head). The wins below are real but small at
clip scale; they mostly buy launch time, frontend CPU (battery/thermal headroom on the fallback
engine), and headroom that adds up over long multi-piece dictations.

## Changes

### Formatter.swift — compile regexes once, stop rebuilding helpers per call

- The three regular expressions (`\s+`, ` +([.,!?;:%])`, the lone-`i` lookaround) were compiled
  on every `format()` call via `replacingOccurrences(options: .regularExpression)`. They are now
  `static let NSRegularExpression`s applied through `stringByReplacingMatches`. Same patterns,
  same templates; `NSRegularExpression` is immutable and thread-safe.
- `core()` built a fresh `CharacterSet` per token; it is now a static. `suffix()` reversed the
  token twice; it is now one backward scan. `capitalise()` reserves capacity once.
- Risk: negligible. No pattern or grammar change.
- Measured: 283-char paragraph, 30 000 calls in one process: **103 → 93 µs/call (−9 %)**.
  `convertNumbers` (tokenising + dictionary lookups) dominates what is left; it was not touched
  because its allocation profile is also its correctness surface.
- Verified: identical output to the original on 46 strings (every `BarkCoreTests` formatter case
  plus edge cases: empty, tabs/newlines, contractions, `a. m.` merges, unicode), and
  `swift test --filter BarkCoreTests` passes 22/22 in a private scratch path.

### Frontend.swift — vectorise with the same rounding order, fix the stride-128 normalisation

- Pre-emphasis: scalar loop replaced by `vDSP_vsmul` + `vDSP_vsub` (scale, then subtract — two
  singly-rounded ops, exactly the scalar order; **no** fused multiply-subtract).
- Power spectrum: `(re² + im²) · 0.25` via `vDSP_vsq`/`vDSP_vadd`/`vDSP_vsmul` into reused
  scratch — same ops, same order, per element.
- `Float(pow(2.0, -24.0))` (a libm call per utterance) replaced by the exact constant `0x1p-24`.
- Per-mel mean/std: was column-at-a-time with stride-128 access over the whole feature matrix
  (three full passes thrashing cache). Now row-major accumulation into 128-wide mean/std arrays,
  then one row-major apply pass. Each mel's additions still happen in frame order, so sums are
  bit-identical; divisions and the `ddof 1` denominator are unchanged, including the
  `valid == 0` edge. Inner loops run on buffer pointers (no bounds checks).
- Risk: the claim "elementwise vDSP op == scalar op bit-for-bit" — verified empirically rather
  than assumed: features compared by `bitPattern` against the original implementation for input
  lengths 1, 2, 159, 160, 4000, 39 200 and 240 000 with randomised mel filters and audio: all
  bit-identical (192 128 feature values at 15 s).
- Measured: 15 s of audio per call, 30 calls: **1.72 → 0.98 ms/call (−43 %)**. Per 15 s piece
  that is ~0.74 ms saved; on a hypothetical 134 s dictation (~9 pieces) ~7 ms of CPU.
- Not done: `vDSP_measqv`-style energy reductions or prefix sums anywhere — they reassociate
  floating-point additions and would break bit-identity.

### Decoder.swift — kill per-step allocations, vectorise dequant; leave gate math alone

- int8 dequantisation in `Weights.float` was a scalar double loop over every LSTM weight at
  load. Now `vDSP_vflt8` (exact Int8→Float) + per-row `vDSP_vsmul` (one singly-rounded multiply
  — same value as the scalar code). Mel filters compared bit-identical after the change.
  Measured `Decoder.init` (file IO + JSON + dequant), warm repeats in one process:
  **16.5 → 13.8 ms**; a first-in-process reversed-order pair gave 29.6 → 21.1 ms. Report as
  roughly **−15…−30 % of decoder init** (page-cache makes this one noisy; it is a launch-path
  saving, part of app start).
- `decode()` previously allocated constantly: each `gemv` copied its bias vector into a fresh
  array (10 KB ×2 layers per token step), each `step()` allocated the embedding slice, fresh
  `h`, a copy-on-write copy of `c`, and the projection; each frame allocated a fresh logits
  array. All buffers now live in a `Scratch` object created **once per `decode()` call** and
  never stored on `self`, so concurrent `decode()` calls keep the old semantics (previously
  per-call locals) — this is the main correctness risk of the change and it is deliberate that
  the scratch is not shared instance state.
- LSTM state is updated in place: the gate loop's recurrence is per-lane (`c[j]` depends only on
  old `c[j]`), so in-place update is exact. Gate arithmetic itself is unchanged — still libm
  `exp`/`tanh`, same expression order; only bounds checks and allocations were removed (buffer
  pointers). `argmax` keeps the strict-`>` first-maximum tie behaviour (no `vDSP` max-index,
  whose tie behaviour is not something to lean on).
- Measured: decode of 188 random encoder frames ×20: **59.7 → 58.4 ms/decode (−2 %)**. Honest
  read: allocations were never the bottleneck here; streaming ~26 MB of weights per token is.
  (Random encoder outputs mostly decode as blanks, so this understates the token-step path; the
  end-to-end clips exercise it and are also within noise.)
- Verified: token-identical (and detokenised-text-identical) vs the original decoder on random
  encoder outputs across seeds/scales, including token-emitting cases (up to 43 tokens), plus
  zero-input and T=1 edges, plus byte-identical BarkBench transcripts.
- Not done (would break bit-identity): `vForce.exp`/`tanh` sigmoid gates. They are a poor trade
  anyway — 3840 transcendental evaluations per token are minor next to the weight streaming.

### Transcriber.swift — bulk Float↔Float16 at the CoreML boundary

- Filling the encoder input converted up to 1501×128 floats scalar-by-scalar with a branch per
  element. Now one `vImageConvert_PlanarFtoPlanar16F` over the valid region and a bulk zero-fill
  of the tail; the mask is two bulk fills (ones/zeros) instead of a per-element ternary.
- Reading the encoder output was a scalar strided double loop. When the output rows are
  contiguous (`strides[2] == 1`) it is now one bulk `vImageConvert_Planar16FtoPlanarF` (or a
  `memcpy`-class `update(from:count:)`) per frame; non-contiguous layouts keep the original
  scalar loop verbatim as a fallback.
- Risk: two assumptions, both checked. (1) vImage half conversion rounds like scalar
  `Float16(_:)` — probed before adopting: 3 992 065 values (random bit patterns, denormal and
  tie cases, infinities) with **0 mismatches**, and all 65 536 Float16 patterns in the reverse
  direction with **0 mismatches**. (2) A freshly allocated `MLMultiArray` is contiguous — the
  old code already relied on this by linear-indexing `dataPointer`; the new code relies on it
  no more than the old did. (The output fast path does *not* assume: it checks the stride.)
- Measured: **unmeasured in isolation** — the end-to-end delta is inside the ±1 ms noise above.
  Expected value is sub-millisecond per piece (~192 k conversions); the change mainly removes a
  branchy scalar loop from a latency-critical path at zero risk given the probe.
- Not touched: `segments()` energy/moving-average. Vectorising its reductions
  (`vDSP_measqv`, prefix sums) would reorder additions and could move a cut point; its cost is
  also trivial next to inference.

## What dominates now (for the next pass, whoever owns it)

Warm dictation ≈ ANE encoder + decoder weight streaming; everything changed here is second-order
by comparison. Cold start is dominated by encoder load (next item). The Clean engine's
0.72 s-vs-2.8 s gap on long audio is structural (parallel encoder/decoder design), not something
micro-optimisation of this decoder will close.

## Next 5 opportunities — outside this lane, proposals only

1. **App launch / encoder load (app + CoreML configuration).** Bench `Transcriber` init measured
   157–175 s for the ANE multi-function package in a fresh process, despite the `.mlmodelc`
   cache. First job is instrumentation: does the app pay ANE specialisation per launch, and
   where (compile vs `MLModel.load` vs first prediction)? Then compare against the GPU package's
   load, consider warming with a silent prediction, and confirm the 8 s-first progressive load
   actually unblocks dictation as intended. This dwarfs every number in this document if it
   reproduces in the app.
2. **Clean engine first-dictation latency (Buddadawg/FluidAudio lane).** The default engine is
   FluidAudio; its model load + first-call warm-up is what users feel on their first dictation of
   a session. Measure cold vs warm on the Clean path the way BarkBench does for Bark, and warm
   it behind the recording UI if needed.
3. **Overlay frame cost (Metal view lane).** The bottom-edge glow presumably renders on a
   display-linked loop. Profile GPU/CPU per frame and wakeups at 120 Hz ProMotion, and check
   that it draws nothing when hidden, idle, or when the level has not changed. Battery, not
   latency — but it runs for every second of every dictation.
4. **Recorder hot path (capture lane).** Capture → resample to 16 kHz mono runs for the whole
   recording. Check per-buffer allocations and converter settings in the render callback path;
   a preallocated ring buffer avoids allocator traffic while the user is talking (and while the
   decoder wants the CPU right after).
5. **Paste round-trip (app lane).** Clipboard write + synthetic paste + clipboard restore adds a
   fixed cost to *every* dictation, however short. Signpost format→paste→restore latency; if
   the restore waits on a timer, that is user-visible latency on the shortest, most common
   dictations where the engines themselves take <100 ms.

One in-lane item parked deliberately, because it needs a numerics decision rather than an
output-identical change: running the decoder GEMVs against the int8 weights directly (or in
Float16) would cut the ~26 MB/token weight stream by ~4×/2× and is the only lever that plausibly
moves Bark's long-clip time by a large factor. It will not be bit-identical, so it needs a
WER-style comparison harness before adoption, not just a timer.

## Verification summary

- `swift build -c release --product BarkBench` clean (before: `/tmp/bd-perf-before`, after:
  `/tmp/bd-perf-after` — shared `.build` untouched).
- `swift test --scratch-path /tmp/bd-perf-after --filter BarkCoreTests`: 22/22 pass.
- Original-vs-new harness: Frontend bit-identical (7 lengths × random data); Decoder
  token-identical (random encoder outputs incl. token-emitting scales, zero input, T=1);
  Formatter identical on 46 cases.
- vImage half-conversion probe: 0 rounding mismatches vs scalar conversion (3 992 065 values
  forward, all 65 536 patterns backward).
- BarkBench on t1/t2/t4 before/after: transcripts byte-identical; warm times 86→86 ms,
  232→233 ms, 485→484 ms (noise).
