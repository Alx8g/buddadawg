# Buddadawg 0.3 — integrated roadmap (parallel sprint)

Status: integration plan for the seven parallel lanes of 2026-11-12 (features,
performance, LOC reduction, visual language, launch video, OSS release, critic).
This document is the parent's single ordered checklist. It changes no code:
everything under "Integration order" is still to do unless marked done.
Lane source docs stay authoritative for detail — `docs/features-next.md`,
`docs/performance.md`, `docs/loc-audit.md`, `docs/design/visual-language.md`,
`docs/launch-video-spec.md`, `docs/oss-release-plan.md`.

## 1. Differentiation position

**Buddadawg is the fully-OSS dictation app that pauses your media, never
loses a take, and never rewrites you.**

Each clause maps to a shipped or 0.3 mechanism, and each is stated no
stronger than the mechanism:

| Clause | Mechanism (on disk) | Honest limit |
|---|---|---|
| Fully OSS | Own code to be released under an OSS `LICENSE` (choice still open, `docs/oss-release-plan.md` §1); FluidAudio is Apache-2.0 | Model weights are **not** under the app licence: bundled `NOTICE`s state CC-BY-4.0 while Conway's current model cards render CC-BY-NC-4.0 (see §5, gate G1). Public copy must say "free and open source (code); models under their own licences — see notices" until Conway answers |
| Pauses your media | `Sources/Buddadawg/MediaPauser.swift` (MRMediaRemote), toggle in `App.buildMenu()` / `togglePauseMedia(_:)` (`Sources/Buddadawg/main.swift:239,291`) | Reliability varies by source app; only tested sources may be claimed/filmed (`docs/launch-video-spec.md` §6) |
| Never loses a take | `Sources/Buddadawg/AudioVault.swift`: opt-in local WAV vault (newest 20, 7-day expiry, dir 0700 / files 0600), saved *before* transcription so a failed or garbled pass still leaves the audio | Only true when the user opts in — vault is **off by default** (`audioVaultEnabled` unset = false, checked inside `save`). Public copy: "opt-in audio vault", never an unconditional promise. Full payoff (re-transcribe) is 0.3 work, §3.1 of `docs/features-next.md` |
| Never rewrites you | `DictationFormatter` + `SpokenCommands` are conservative by design: input returned byte-for-byte when nothing matches, nothing mid-sentence triggers, verbatim (Bark) engine remains available | Clean mode does edit ums/false starts by user choice; position is "no silent LLM rewrite of your words", not "no cleanup option" |

What Buddadawg does **not** compete on yet: accuracy/WER comparisons
(no benchmark exists — explicitly banned from launch copy,
`docs/launch-video-spec.md` §6), streaming live preview, cloud sync,
or a paid tier (blocked by the Conway licence state, §5).

Local-only is the premise underneath all four clauses: on-device
engines, no network at runtime (to be evidence-checked before it is
claimed publicly), Recents/vault/dictionary all local files.

## 2. What the sprint produced (inventory)

All lane file sets are pairwise disjoint and compile together
(critic-verified combined build + 22/22 tests, see §2.2). Nothing is
committed: HEAD is `8b09429` and the entire v0.2.0 tree plus all lane
work sits modified/untracked in the working tree.

### 2.1 Lane artifacts

**Features** (new files only, nothing wired into the app yet)

- `Sources/BarkCore/SpokenCommands.swift` (116 lines) — public
  `SpokenCommands.parse(_:) -> Result{text, actions, shouldDiscard}`;
  whole-utterance "scratch that", trailing/standalone "new line" /
  "new paragraph" with noun-phrase guard, leading "bullet point".
- `Tests/BarkCoreTests/SpokenCommandsTests.swift` (114 lines) — 10
  Swift Testing `@Test`s incl. false positives ("a new line of work",
  "scratch that itch").
- `Sources/Buddadawg/AudioVault.swift` (160 lines) — `save` / `entries`
  / `prune` / `totalSizeBytes` / `delete` / `deleteAll`, 16 kHz 16-bit
  WAV, default-OFF, 0700/0600, no force unwraps.
- `docs/features-next.md` (233 lines by `wc -l`) — exact wiring spec
  (§3 below) + ranked follow-ups (re-transcribe, add-to-dictionary,
  per-app profiles, live preview).

**Performance** (edits in place, output-preserving)

- `Sources/BarkCore/Formatter.swift` (now 238 lines) — cached static
  regexes/`CharacterSet`; −9%/call measured, identical on 46 cases.
- `Sources/BarkCore/Frontend.swift` (123) — vDSP with scalar rounding
  order preserved; −43%/piece, bit-identical features at 7 lengths.
- `Sources/BarkCore/Decoder.swift` (176) — per-call `Scratch`, no
  per-step allocation; init −15…−30%, decode −2%, token-identical.
- `Sources/BarkCore/Transcriber.swift` (154) — bulk vImage
  Float↔Float16 (0 mismatches over 3,992,065 values); `segments()`
  deliberately untouched.
- `docs/performance.md` — honest headline: warm end-to-end latency
  unchanged within ±1 ms (86→86, 232→233, 485→484 ms); ANE encoder +
  ~26 MB/token decoder weight streaming dominate. Five outside-lane
  proposals (§4.2).

**LOC reduction** (dedupe only, no feature deleted)

- `Sources/BarkCore/WavLoader.swift` (36, new) — shared
  `WavLoader.loadAudio` + `MemoryStats`, verbatim move from benches.
  ⚠️ Still bench-fatal (`fatalError`/force-unwrap): must be hardened
  before any app call site (§3, step 5).
- `Sources/BarkBench/main.swift` 57→30, `Sources/CleanBench/main.swift`
  49→29; `Package.swift:13` CleanBench gained the `BarkCore` dep.
- `scripts/fetch_models.sh` 44→42 (guarded metadata line);
  `scripts/bundle.sh` / `scripts/install.sh` unchanged.
- `docs/loc-audit.md` (104) — decision options, none taken: Bark
  fallback-stack removal (was ≈425 lines at lane snapshot; **≈556
  now** after perf/visual growth per critic), benches delete 95 /
  merge ≈10–15, demo mode 26, GPU-units path ≈3 (≈8 ANE-only).

**Visual language**

- `Sources/Buddadawg/Overlay.swift` (now 252) — butter tint
  (creamEdge `#FFF1CF` → butterMid `#FFC94D` → amberCore `#FF9E2C`),
  correct premultiplied output `float4(tint*alpha, alpha)` (old
  `float4(G,G,G,G*.85)` had rgb>alpha), Reduced Motion support
  (`reduceMotion`, `reducedPhaseScale=0.15`, `Uniforms.reduce`,
  grain .3→.04). `Sources/BarkCore/PhaseClock.swift` untouched.
- `Brand/icon-concept.png` (1336×1280 raster concept, generated) —
  concept only, needs vector redraw + iconset (§4.1).
- `docs/design/visual-language.md` — palette, motion timings, state
  colour semantics, menu-bar per-state glyph *proposal* (not built).

**Launch video** (docs only)

- `docs/launch-video-spec.md` (380 lines) — 11-shot 40 s hero
  ("This film was dictated", no studio VO), 15 s cutdown, 6 s loop,
  protected 90–110 s uncut proof cut, 9-row claims register (§6),
  posting variants + thread, alt-text plan.

**OSS release** (docs only)

- `docs/oss-release-plan.md` (840 lines) — measured current state
  (646 MB app, self-signed, `spctl` rejected, no Developer ID),
  12-row licence table, bundled-vs-download decision (bundle for
  launch), signing/notarisation, onboarding, Sparkle 2, privacy,
  CI, Homebrew, beta cohort, benchmarks, gates G1–G11 (§5 below).

**Critic** (no edits)

- Ran the combined check no single lane could: full build + test of
  the integrated tree (§2.2); verified disjoint file sets, target
  placement, doc-vs-code spot checks; raised attribution, stale-doc,
  WavLoader-placement, and by-eye risks (all in Unresolved).

### 2.2 Combined verification already on record

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --scratch-path /tmp/bd-critic-scratch2   # 22/22 passed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --scratch-path /tmp/bd-critic-scratch2  # Build complete (all products)
```

22 = 12 pre-existing `BarkCoreTests` + 10 `SpokenCommandsTests`
(incl. `commandsComposeWithTheFormatter`, proving perf-lane Formatter
and features-lane parser compose). Bare CLT `swift test` fails on the
TestingMacros plugin — environment, not code; always set
`DEVELOPER_DIR` (runbook in `README.md` + `docs/oss-release-plan.md`).
No lane installed or launched the app; shared `.build` untouched.
Current `Package.swift` (18 lines): targets `BarkCore`, `BarkBench`,
`CleanBench` (BarkCore + FluidAudio), `Buddadawg` (BarkCore +
FluidAudio), `BarkCoreTests` (BarkCore); macOS 15+, Swift 5 mode.

## 3. Integration order (parent checklist)

Do these in order. Steps 1–2 make the tree attributable; 3–4 are the
only behaviour changes; 5 unblocks the vault payoff; 6–7 verify by
ear and eye what no lane could; 8 fixes doc drift. Line numbers are
for the current `Sources/Buddadawg/main.swift` (307 lines) and will
drift — function names are the stable anchor.

### Step 0 — Re-verify the integrated tree (no edits)

```sh
cd /Users/alex/buddadawg
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test  --scratch-path /tmp/bd-roadmap-check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --scratch-path /tmp/bd-roadmap-check
sh -n scripts/bundle.sh scripts/fetch_models.sh scripts/install.sh
```

Expect 22/22 and Build complete for all products (`Buddadawg`
incl. `AudioVault` + butter `Overlay`, `BarkBench`, `CleanBench`).
This reproduces the critic result before any new edit lands on it.

### Step 1 — Commit the v0.2.0 baseline, then the sprint, in reviewable slices

HEAD (`8b09429`) predates v0.2.0, so today `git diff` mixes
pre-existing work with lane edits and per-lane attribution is not
provable from history (critic). Before any further parallel work:

1. Commit + tag v0.2.0 as-is, including tracking `Package.resolved`
   (FluidAudio 0.18.3) and `Tests/` (release gate G3).
2. Then land the sprint as separate commits per lane file set in
   §2.1 (perf, LOC, visual, features-unwired, docs), so each stays
   revertible. Do not squash the wiring (steps 3–4) into these.

### Step 2 — Keep, untouched: perf + LOC + visual code

No wiring needed — already in the shipped paths:

- Perf edits in `Sources/BarkCore/{Formatter,Frontend,Decoder,Transcriber}.swift`
  are output-identical by construction and test. Accept the honest
  headline (warm latency ±1 ms); do not market the micro numbers.
- LOC dedupe (`WavLoader`, bench rewrites, `Package.swift:13`,
  `fetch_models.sh`) is compile-verified; runtime equivalence of
  the benches against real models is still unobserved (Unresolved)
  — run both benches once here (models already on disk):

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    swift build -c release --scratch-path /tmp/bd-roadmap-check \
      --product BarkBench --product CleanBench
  # then run each against a known clip + models dir and diff the
  # transcript against the pre-sprint output if available
  ```

- Butter `Overlay` compiles and passes offscreen premultiply /
  saturation / grain checks; it still needs the by-eye pass in
  step 7 before it is called done.

### Step 3 — Wire `SpokenCommands` (`main.swift` only)

Per `docs/features-next.md` §1. No other file changes.

1. In `App.finish()` (main.swift:149), inside the transcription
   `Task`, parse **after** formatting — `DictationFormatter.format`
   collapses `\s+` and would erase inserted breaks:

   ```swift
   // existing main.swift:175
   let text = DictationFormatter.format(Dictionary.apply(raw))
   // new
   let parsed = SpokenCommands.parse(text)
   let text = parsed.text
   ```

2. In the following `MainActor.run` block: `if parsed.shouldDiscard`
   → skip `Recents.add` (main.swift:180) and `Paster.paste` (:182),
   `overlay.show(.cancelled)`, still resume media via
   `MediaPauser.shared.resumeIfPausedByUs(session:)`,
   `log("discarded by spoken command")` (never the text), `return`.
3. Paste spacing: replace `Paster.paste(text + " ")` with
   `Paster.paste(text.hasSuffix("\n") ? text : text + " ")` — no
   trailing space after a spoken break.
4. In `App.rebuildRecents()` (main.swift:250): menu title from
   `text.replacingOccurrences(of: "\n", with: " ")`;
   `representedObject`/`toolTip` keep the real text.
   `pasteRecent(_:)` (paste at main.swift:277) gets the same
   no-trailing-space rule.
5. Verify: `swift test --filter SpokenCommands` (with
   `DEVELOPER_DIR` as above), then the by-ear pass in step 6.

### Step 4 — Wire `AudioVault` (`main.swift` only)

Per `docs/features-next.md` §2. Privacy non-negotiables travel with
this step: off by default, 20 files / 7 days, 0700/0600, toggling
off never deletes, logs never carry transcript text.

1. In `App.finish()`: one line `AudioVault.save(audio)` as the first
   line inside the existing chained `Task`, after the
   `guard audio.count > 1600, ready` guards and **before** the
   engine call — the vault exists to survive failed transcription.
   Never save on the `hotkey.onCancel` path or in `Recorder.stop()`.
2. In `App.buildMenu()` (main.swift:224), directly below "Pause
   Media While Dictating" (:239), mirror `togglePauseMedia(_:)`
   (:291): "Keep Audio for Recovery (7 days)" →
   `@objc func toggleAudioVault(_:)` flipping `AudioVault.isEnabled`;
   "Delete Stored Audio" → `@objc func deleteVaultAudio()` calling
   `deleteAll()` then reporting the post-wipe `entries().count`
   (show count + `totalSizeBytes()` via `ByteCountFormatter`,
   refreshed wherever `rebuildRecents()` is called; disabled when
   empty); optional "Open Vault Folder"
   (`NSWorkspace.shared.open(AudioVault.directory)`) — the manual
   recovery path until re-transcribe lands, without which the
   vault is write-only.
3. In `App.applicationDidFinishLaunching(_:)` (main.swift:49), one
   line near `Dictionary.seedIfNeeded()`: `AudioVault.prune()`.
4. Manual check with the toggle **off**: dictate, confirm no
   `~/Library/Application Support/Buddadawg/Vault/` is created.
   Toggle on: dictate, confirm one 0600 WAV appears; cancel a
   dictation, confirm none is added.

### Step 5 — Harden the WAV loader before any app use

`WavLoader.loadAudio` (`Sources/BarkCore/WavLoader.swift:8,17`)
force-unwraps and `fatalError`s — fine for benches, forbidden in the
app, and now linked into the app via BarkCore (dead code today).
Before re-transcribe (step 6 of §4.1) either add a throwing/optional
variant for app use or load vault WAVs with `AVAudioFile` in the app
target; longer term, move bench support out of BarkCore into a
bench-only target (critic). Do not call the bench version from
`main.swift` as-is.

### Step 6 — By-ear pass (features on real model output)

Parser behaviour on real Clean/Bark transcripts (punctuation/casing
beyond `DictationFormatter.format` output, hyphenated "new-line")
is untested. With steps 3–4 wired, dictate the test matrix from
`SpokenCommandsTests` through both engines: positives, plus
"a new line of work", "add a new line", "scratch that itch".
Extend `SpokenCommandsTests` first if a rule needs to change.

### Step 7 — By-eye pass (overlay in the running app)

No lane launched the app. One `--demo` / on-screen pass must check:
butter tint vs the old grayscale brightness (premultiply fix makes
output ~15% dimmer before tint; cancelled a further 12% —
`Overlay.swift:248`), all five states, and Reduced Motion
(`dt*0.15` damping at `Overlay.swift:133`; `PhaseClock` wrap
threshold is reached ~6.7× slower in phase-time). Keep demo mode
(`runDemo()`, main.swift:199, `--demo` at :66) at least until this
pass and the launch film are done — deleting it is LOC option 3,
deferred (§4.2).

### Step 8 — Fix stale cross-lane doc numbers

- `docs/loc-audit.md`: refresh to current counts (Decoder 176,
  Frontend 123, Transcriber 154, Formatter 238, Overlay 252;
  Bark-stack removal ≈556 lines, not 425; repo Swift total is no
  longer 1817).
- `docs/oss-release-plan.md:25`: 12 tests → 22.
- `docs/features-next.md`: claimed 231 lines, actual 233 (cosmetic).
- Re-run `wc -l` over `Sources/**/*.swift` and record the new
  baseline in `docs/loc-audit.md` so the next sprint starts clean.

## 4. Sequencing: 0.3 public beta vs later

### 4.1 In 0.3 (public beta scope)

Product code, in dependency order:

1. §3 steps 0–4: baseline commits, `SpokenCommands` + `AudioVault`
   wiring. This is the user-visible 0.3 delta: spoken structure
   commands and the opt-in recovery vault behind §1's position.
2. §3 step 5 (loader hardening) + **re-transcribe a vault recording
   with the loaded engine** (`docs/features-next.md` §3.1, ranked
   first): "Stored Audio" submenu from `AudioVault.entries()`,
   shared `finish()` tail helper (`Dictionary.apply` → format →
   parse → `Recents.add` → paste, chained behind
   `transcriptionTail`). Ship loaded-engine only; the Clean-vs-
   Verbatim choice needs lazy-loading the second engine — that part
   may slip to 0.4 without breaking the story. Without this item
   the vault is write-only except via "Open Vault Folder", so it is
   the minimum that makes "never loses a take" usable.
3. Password-field guard slice from `docs/features-next.md` §3.3
   (suppress `Recents.add` + vault save on
   `kAXSecureTextFieldSubrole`) — small, and it is a privacy
   correctness item once the vault exists, ahead of general
   per-app profiles.
4. Committed `AudioVault` tests: move the vault to a library target
   or add a `BuddadawgTests` target (today `Buddadawg` is an
   `executableTarget`, not importable; behaviour rests on a
   throwaway `/tmp` probe). Decide the vault byte-cap question at
   the same time (20 × 10 min locks ≈ 385 MB worst case;
   `totalSizeBytes()` already exists for UI display).
5. App-launch / encoder-load instrumentation
   (`docs/performance.md` proposal 1): bench `Transcriber` init
   measured 157–175 s for the ANE package in a fresh process.
   Whether the app pays ANE specialisation per launch must be
   known before onboarding is timed (gate G6) and benchmarks are
   published (gate G9) — this measurement, not micro-optimisation,
   is the 0.3 performance work. Clean-path cold-vs-warm
   (proposal 2) rides along.
6. Icon: vector redraw of `Brand/icon-concept.png` normalised to
   the `docs/design/visual-language.md` palette, Apple icon grid /
   safe margins, iconset export, wired into `scripts/bundle.sh`.
   A public beta cannot ship the clipped raster concept.

Release work (all of §5's gates) and launch-film evidence (§6) are
also 0.3 scope — they define "public", not the feature set.

Explicitly **not** required for 0.3: menu-bar per-state glyphs
(proposal in `docs/design/visual-language.md`; needs `main.swift`,
ship if cheap during step 4 but do not gate on it), Homebrew
homebrew-cask proper (custom tap first, gate G10), any paid tier.

### 4.2 Later (0.4+, in ranked order)

1. **Add-to-dictionary from selection** (`docs/features-next.md`
   §3.2, ranked second): AX-first selection read, Cmd-C fallback
   only with pasteboard save/restore + warning; honest two-field
   panel, no faked "heard" side.
2. **Re-transcribe engine choice**: lazy-load the non-current
   engine (Clean *and* Bark resident on demand) — the shared
   prerequisite that also unblocks per-app engine profiles.
3. **Per-app profiles** (§3.3): bundle-id captured at fn-down,
   plain-text config beside the dictionary, ≥2 real knobs
   (engine, trailing space, spoken commands on/off).
4. **Performance proposals 3–5** (`docs/performance.md`): overlay
   frame cost at 120 Hz, recorder hot-path allocations, paste
   round-trip signposting. Plus the parked numerics decision:
   int8/Float16 decoder GEMV (~4×/2× weight-stream cut) — needs a
   WER-style harness before adoption, never a timer alone. Also
   re-measure the missing baselines: a real ~134 s clip and the
   Clean 0.72 s figure on the current tree.
5. **LOC decisions** (`docs/loc-audit.md`, refreshed numbers):
   Bark fallback-stack removal (≈556 lines + 199 MB model payload;
   loses verbatim fallback and the `engine=bark` hatch that gate
   G10 documents — decide only with beta evidence that Clean is
   reliable alone), benches delete/merge (not recommended while
   they are the regression check), demo-mode removal (26 lines;
   only after the film and by-eye passes no longer need it),
   GPU-units path (≈3–8 lines, negligible). Move `WavLoader` to a
   bench-support target when next touching `Package.swift`.
6. **Live preview** (`docs/features-next.md` §3.4, ranked last):
   research item; if ever shipped, overlay-only, never
   in-document. Requires a product decision on giving the
   text-free glow a text surface first.
7. Vault byte cap / mid-utterance commands / bullet capitalisation
   (needs `DictationFormatter` to preserve `\n`) — only with
   evidence from real use, tests first (`docs/features-next.md` §4).

## 5. Release gates (from `docs/oss-release-plan.md` §12)

Public beta requires **all** of G1–G11 green; "mostly" is a no-go.
Copy the checklist into the release issue and tick with evidence
links. Summary (plan §12 is the full text):

**Licence**

- G1. Conway Q1–Q4 answered in writing, *or* documented good-faith
  attempt + waiting period + explicit README/site disclosure of the
  CC-BY (bundled NOTICEs) vs CC-BY-NC-4.0 (current cards, dated
  2026-11-05 by trackers) conflict and free-noncommercial
  positioning. Silence-and-hope is a no-go. **Paid anything stays
  blocked while this stands** (plan §11); FluidAudio/Parakeet/own
  code are not the blocker.
- G2. App-code `LICENSE` committed; `THIRD-PARTY-NOTICES.md` ships
  inside the `.app`; README Tenor GIF replaced with an owned asset;
  LuxTTS GPL-3.0/CC-BY-SA data-absence check performed on the
  release build (full strings/resource audit, not just `otool -L`)
  and recorded.

**Build & signing**

- G3. v0.2.0 committed + tagged (§3 step 1); `Package.resolved` +
  `Tests/` tracked; CI green on `main` (`swift test` with Xcode
  `DEVELOPER_DIR` + release compile, macos-15/macos-26 runners).
- G4. Developer ID + hardened runtime + notarised + stapled,
  verified on a machine without dev certs (`spctl` = Notarized
  Developer ID). Zero-exception start, then prove
  MediaRemote/event-tap/CoreML-ANE under hardened runtime.
  Today: self-signed "Buddadawg Local Signing", no Developer ID
  identity exists yet — enrolment is on the critical path.
- G5. Model fetch revision-pinned + SHA-256-verified; artefact
  checksums published; Sparkle 2 EdDSA appcast with a real
  N→N+1 update (incl. delta size) tested. Distribution decision:
  **bundle both engines (646 MB) for beta/launch**; first-run
  download is the fallback if Conway objects to bundling
  (re-run G5–G6 — a schedule event, not a stopper).

**First-run & privacy**

- G6. Onboarding (mic + Accessibility + ANE compile) implemented
  and timed on a fresh account + base-M1 hardware (needs §4.1
  item 5's measurements; README/install "minute or two" vs
  "~5 minute" claims are currently unmeasured).
- G7. `PRIVACY.md` with data inventory (UserDefaults recents,
  vault, dictionary, clipboard-manager exposure);
  network-silence check run on the release candidate and linked.

**Quality & ops**

- G8. Private-beta exit criteria met; troubleshooting + known
  issues published (English-only, Apple-silicon-only, macOS 15+).
- G9. `docs/benchmarks.md` core table for the shipped build:
  cold prepare, fn-release→paste p50/p95 at 5/30/120 s, idle
  CPU/memory, paste-by-app-category. No cherry-picked numbers —
  this table is also the launch film's only allowed source (§6).
- G10. Repo hygiene: issue/PR templates with transcript-safety
  warnings, `SECURITY.md`, branch protection, `CHANGELOG.md`;
  custom Homebrew tap pointing only at the notarised artefact;
  rollback build + `engine=bark` hatch documented.
- G11. Paid-blocker firewall: no pricing/waitlist/Pro language
  anywhere in launch material; "free" claims use the accurate
  code-vs-models wording from §1.

## 6. Launch-film gates (from `docs/launch-video-spec.md`)

The film shoots **after** §3 steps 3–4 + 6–7 (it must show the real
0.3 build, butter overlay included) and after G9 exists. Nothing
from the §6 claims register may appear in burned-in text, post
copy, or replies until its evidence is captured and archived:

1. **Speed claim**: the brief-supplied "46.7 s → 432 ms · M1 Pro"
   is unverified. On the shoot Mac: 5× `CleanBench` median (state
   chip/RAM/macOS) + end-to-end fn-release→paste timing; the film
   uses the measured number and says what was measured.
2. **Hero take integrity**: archive `take.wav` + verbatim `.txt` +
   Clean `.txt`; captions/strikethroughs match the Clean file
   character-for-character; disclose the Shot-5 1.6× speed ramp in
   the thread. Rehearse the manifesto script through Clean first
   (fn rendering, um/false-start removal, dictionary state).
3. **"Neural Engine"** wording only with compute-unit evidence;
   until then "Bark 3.0 Clean · on-device".
4. **"No network at runtime"** only with the G7 capture, scoped:
   models download once at install (~640 MB bundled/download size
   per G5 outcome).
5. **Media pause/resume**: shoot-day matrix (Music.app, Spotify,
   YouTube in Safari/Chrome); film only a source that works, list
   tested sources in replies.
6. **"Works in any app"** → thread qualifier "any app that takes a
   paste"; state macOS 15+ / Apple Silicon floor in copy + alt text.
7. **No accuracy comparisons** (Siri/Whisper/Wispr) until a
   reproducible bench ships. Compete on local/free/feel.
8. Deliverables: 40 s hero + 15 s cutdown (16:9 and 9:16) + 6 s
   loop + 90–110 s uncut proof cut (the small-account data favours
   1–4 min; the proof cut is the reply/Day-2 asset), SRTs, posters,
   alt text + transcript. Re-verify any cited X example's direct
   URL and live view count on X before public citation (6/8 were
   not captured at spec time).
9. Overlay on camera follows `docs/design/visual-language.md`
   (premultiplied-comp guidance, `--demo` for repeatable states)
   and the by-eye pass (§3 step 7) must already be green — the
   film is not the place to discover the tint is wrong.

## Unresolved

Every unresolved item from all seven lane submissions, carried
forward verbatim, grouped by lane. Nothing here is closed by this
roadmap; §3–§6 say where each gets addressed.

### Features (prior result 5)

- Nothing is wired into main.swift, by design: SpokenCommands and AudioVault have no call sites yet (docs/features-next.md is the wiring spec); app was not installed or launched
- AudioVault has no committed unit tests: Buddadawg is an executableTarget not importable by BarkCoreTests, so behavior was verified only by the throwaway /tmp/vaultprobe harness (and its directory line differed, as recorded); a committed test would need the vault moved to a library target or a BuddadawgTests target
- No by-ear verification against real Clean/Bark transcripts: parser behavior on actual model output punctuation/casing beyond DictationFormatter.format output is untested; hyphenated commands (new-line as one token) do not trigger
- Vault has count/age bounds only, no byte cap: 20 long double-tap-locked recordings could reach ~385 MB at 10 min each (computed 32 kB/s); flagged in docs as a deliberate non-default
- Cosmetic: because parse must run after DictationFormatter.format, bullet items keep original case ('bullet point buy milk' -> '• buy milk', no capital); fixing needs Formatter to preserve newlines - noted in docs

### Performance (prior result 6)

- Brief's 134s clip (~2.8s) not re-measured: /tmp/buddadawg-tests/t4_long.wav on disk is 23.0s (485ms warm before, 484ms after). Long-clip delta projected from per-piece micro numbers only (~0.74ms Frontend saving per 15s piece).
- Transcriber vImage bulk fills unmeasured in isolation; their end-to-end effect is inside +-1ms BarkBench noise.
- Micro-benchmarks are single runs in one process under parallel-agent machine load; Decoder.init delta is page-cache sensitive (reported as -15..-30% range from two orderings). Before/after BarkBench binaries were built ~15 min apart from a tree other lanes were editing, so non-lane BarkCore changes between builds could add noise to end-to-end timings (transcripts still byte-identical; RAM-now differed 133-136MB vs 211-213MB, peak identical 466MB, not explained by this lane's ~50KB scratch).
- Bench 'load' (Transcriber init) of 157-175s for the ANE package was observed twice but not profiled (CoreML compile/load/specialisation is outside this lane); whether the app pays the same per launch needs app-side instrumentation - listed as proposal 1 in docs/performance.md.
- Decoder decode micro-timing uses random encoder outputs that mostly decode as blanks, understating the token-step path; token-emitting correctness was verified but its isolated timing delta was not (end-to-end clips cover it, within noise).

### LOC reduction (prior result 1)

- Benches verified by compile/link only, not executed against real models/audio (loader logic is a verbatim move, but runtime output equivalence was not observed)
- Parallel agents added files during this run (e.g. BarkCore/SpokenCommands.swift, Buddadawg/AudioVault.swift, Tests SpokenCommandsTests.swift 114 lines), so repo-wide Swift total at handoff is 2239, not the 1817 measured for this lane's tree snapshot; lane-file counts re-verified unchanged and the discrepancy is footnoted in docs/loc-audit.md
- fetch_models.sh change verified by sh -n and inspection only; not executed (would download models / the already-present guard would short-circuit)

### Visual language (prior result 3)

- On-screen look in the running app not verified: app was not installed/launched per instructions; evidence is offscreen Metal renders + typecheck only
- Whole-package swift build/test not run (shared .build with parallel agents per instructions); only private-scratch typecheck of Overlay.swift against a PhaseClock-only BarkCore module
- Brand/icon-concept.png is a raster concept (generated 1920x1280, icon square slightly clipped at raster top/bottom, cropped to 1336x1280) — needs vector redraw normalised to palette, Apple icon grid/safe margins, and iconset export before shipping
- Menu-bar icon per-state glyphs are a documented proposal only — implementing them requires main.swift, which is outside this lane

### Launch video (prior result 2)

- X video files themselves were not frame-decoded (no playback available): hook/motion/sound per example are inferred from inspected written breakdowns except Wispr premise/post-copy (inspected) — each example labelled Inspected vs Snippet+inferred in doc §1.0-1.1
- Direct X URLs for 6/8 examples not captured in inspected text (only Doomers directory paths; Wispr URL exact). Direct links and live view counts must be re-verified on X before public citation
- Brief-supplied 46.7s→432ms M1 Pro number unverified (no bench run per lane rules); §6 requires 5x CleanBench median + end-to-end timing on shoot Mac, film must use measured number
- Neural Engine utilisation, no-network-at-runtime, app-vs-model licence split, and MediaPauser reliability per source app unverified; evidence steps specified in §6 claims register
- Clean behaviour on the exact manifesto script (fn rendering, um/false-start removal) untested on real build; rehearsal take + dictionary check required before shoot (§4, §10)

### OSS release (prior result 4)

- Conway has not been contacted: whether pre-2026-11-05 CC-BY copies remain redistributable, whether free bundling vs first-run download is permitted under CC-BY-NC, workplace-use line, and commercial licence terms are unanswered — plan §1.1 lists the exact 8 questions and gates paid (blocked) and free (disclosure required) differently
- 2026-11-05 relicensing date comes from independent model trackers found via web search, not from a Conway statement; plan marks it 'to be confirmed by Conway Q1'
- LuxTTS G2P GPL-3.0 data absence from the shipped binary was argued from otool -L + bundle file listing but not exhaustively proven (no full strings/resource audit); plan §1 row 4 + gate G2 assign this as a release-build verification
- No Developer ID build exists to verify hardened-runtime compatibility (MediaRemote/MediaPauser, event tap, Core ML/ANE) or Sparkle delta sizes — plan specifies zero-exception start + measurements still to take, incl. base-M1 ANE compile time ('minute or two' vs '~5 minute' claims in README/install.sh unmeasured)
- Apple Developer enrolment, notarisation round-trip, CI workflow, onboarding UI, LICENSE choice, and Homebrew notability are specified as checklists for owning lanes/future work, not implemented or tested in this docs-only lane; parallel agents added Brand/icon-concept.png during the session (noted, untouched)

### Critic (prior result 7)

- ATTRIBUTION LIMIT (affects checks 1/3/5): HEAD predates v0.2.0, so git diff vs HEAD mixes pre-existing v0.2 work with lane edits — Package.swift diff also shows FluidAudio dep + CleanBench target + testTarget (pre-existing), fetch_models.sh diff is +42/-lines of v0.2 Clean support not just LOC's -2, and Formatter.swift/PhaseClock.swift/CleanBench/Tests are entirely untracked. 'No two lanes edited same file', 'Package only gained BarkCore', 'PhaseClock untouched' are therefore verified as consistent-with-claims + disjoint claimed sets, NOT independently provable from git history. Parent should commit v0.2.0 baseline before further parallel lanes
- STALE DOC NUMBERS from parallel drift: docs/loc-audit.md table (Decoder 130, Frontend 71, Transcriber 121, Formatter 220, Overlay 220, Swift total 1817, Bark-stack removal ~425/BarkCore 608->286) is superseded by perf+visual growth — actual now Decoder 176, Frontend 123, Transcriber 154, Formatter 238, Overlay 252 (removal option is now ~556 lines, not 425); docs/oss-release-plan.md:25 says 12 tests, actual 22 after features lane; features lane claimed docs/features-next.md 231 lines, wc -l = 233 (minor, unexplained). None block code, all mislead a reader
- WAVLOADER PLACEMENT RISK (loc x features interaction): LOC moved force-unwrap/fatalError bench code into BarkCore, which the shipped Buddadawg app links — dead code today, but features-next retranscribe plan wants to reuse WavLoader.loadAudio for vault WAVs; it must be hardened (throwing) before any app call site, as features doc itself flags. Cleaner long-term: bench-support target instead of BarkCore
- VISUAL BEHAVIOUR DELTAS beyond tint, unverified by eye (no lane launched the app): premultiply fix changes displayed brightness (rgb was G, now tint*G*.85 => ~15% dimmer before tint, cancelled a further 12% at Overlay:248) while visual-language.md:37/157 says 'same coverage' (true for alpha except cancelled); under Reduced Motion PhaseClock *effective* advance IS altered (dt damped in Overlay, file untouched) incl. wrapIfNeeded 7200s threshold now reached ~6.7x slower in phase-time; pipeline sets no blending (Overlay:64-68) so correctness relies on layer premultiplied compositing exactly as before. Needs one --demo/on-screen pass
- PERF x LOC measurement contamination admitted but unresolved: perf before/after BarkBench binaries built ~15min apart while LOC rewrote the benches/other lanes edited BarkCore; RAM-now differed 133-136MB vs 211-213MB unexplained (peak identical 466MB); Transcriber init 175s->157s and all micro deltas (Frontend -43%, Formatter -9%, Decoder init -15..-30%, decode -2%) rest on uncommitted /tmp harnesses — critic verified code+doc honesty and transcript-preserving test suite, did NOT re-run benches (157-175s ANE load per run); 134s long-clip and Clean 0.72s figures remain unmeasured on current tree
- UNWIRED FEATURES: SpokenCommands + AudioVault compile and test green but do nothing in the app (no main.swift call sites, no menu toggle, AudioVault.prune never called at launch); AudioVault has no committed tests (executableTarget not importable; only /tmp probe with altered directory line) and no byte cap (~385MB worst case per features doc); wiring per docs/features-next.md is future work requiring main.swift edits no lane was allowed
- DOC-ONLY LANES carry their own flagged gaps parent must not lose: launch-video 6/8 X examples lack direct URLs and videos were not frame-decoded, manifesto script untested through Clean; oss-release Conway CC-BY vs CC-BY-NC conflict unanswered (paid blocked, free needs disclosure gate G1), no Developer ID/notarisation/CI exists, LuxTTS GPL data-absence unproven; Brand/icon-concept.png is a clipped raster concept needing vector redraw + iconset before use





