# Features next: wiring the vault + spoken commands, and what follows

Status: `Sources/Buddadawg/AudioVault.swift` and `Sources/BarkCore/SpokenCommands.swift`
(+ `Tests/BarkCoreTests/SpokenCommandsTests.swift`) are written but **not wired in**.
This doc is the wiring spec, so the `main.swift` changes stay a small, reviewable diff.
Line numbers drift; call sites are named by function, which is stable.

## 1. Spoken commands (`SpokenCommands`, BarkCore)

API: `SpokenCommands.parse(_:) -> Result { text, actions, shouldDiscard }`.
Rules (conservative, like `DictationFormatter`): whole-utterance "scratch that" discards;
trailing/standalone "new line" / "new paragraph" insert `\n` / `\n\n`; leading
"bullet point" prefixes `• `. Nothing mid-sentence ever triggers. When nothing matches,
`text` is the input unchanged.

### Call site: `App.finish()` (main.swift), inside the transcription `Task`

Order matters. `DictationFormatter.format` collapses `\s+` to a single space, which would
erase breaks the parser inserted — so parse **after** formatting, not before:

```swift
// existing:
let text = DictationFormatter.format(Dictionary.apply(raw))
// new:
let parsed = SpokenCommands.parse(text)
let text = parsed.text
```

Matching is case- and attached-punctuation-insensitive, so `format`'s capitalisation
("Scratch that") still matches. Known cosmetic consequence: "bullet point buy milk"
formats before the bullet is split off, so the item keeps its original case
("• buy milk") instead of gaining a capital. Acceptable for v1; fixing it properly means
teaching `DictationFormatter.format` to preserve `\n` and moving `parse` before it.

Then, in the same `MainActor.run` block that follows:

- `if parsed.shouldDiscard` → skip `Recents.add` and `Paster.paste`, call
  `overlay.show(.cancelled)` (same feedback as the hotkey cancel path), still resume
  paused media via `MediaPauser.shared.resumeIfPausedByUs(session:)`, and `return`.
  Note the existing empty-text check (`if text.isEmpty { overlay.show(.hidden); return }`)
  would already skip the paste for a discard, since discard text is `""` — the explicit
  branch exists for the `.cancelled` feedback and to log
  `log("discarded by spoken command")` (never the text).
- Paste spacing: the current call is `Paster.paste(text + " ")`. When `text` ends with
  `"\n"` (a trailing break command, or a standalone break utterance where `text` is only
  `"\n"`/`"\n\n"`), paste `text` as-is — a trailing space after a paragraph break reads
  as a stray indent in editors. `Paster.paste(text.hasSuffix("\n") ? text : text + " ")`.
- Standalone breaks and `text` beginning with `"\n"` are non-empty, so they flow through
  the existing path with no other change.

### Call site: `App.rebuildRecents()` (main.swift)

`Recents.add(text)` stores break-carrying text verbatim (correct for re-paste via
`pasteRecent(_:)`), but `rebuildRecents()` puts up to 64 chars of it in an `NSMenuItem`
title. Flatten for display only: build the title from
`text.replacingOccurrences(of: "\n", with: " ")`; `representedObject` and `toolTip` keep
the real text. `pasteRecent(_:)` applies the same no-trailing-space rule as `finish()`.

No other files change: `Recorder`, `Hotkey`, `Overlay`, `Paster` are untouched.
Verification: `swift test --filter SpokenCommands` plus a by-ear pass (positives and
"a new line of work") once wired.

## 2. Audio vault (`AudioVault`, Buddadawg target)

API: `save(_ samples:) -> URL?`, `entries()` (newest first), `prune()`,
`totalSizeBytes()`, `delete(_:)`, `deleteAll()`, `isEnabled`.
WAVs (16 kHz, 16-bit mono — `Recorder`'s output, unchanged) land in
`~/Library/Application Support/Buddadawg/Vault/` as `yyyyMMdd-HHmmss-SSS.wav`.

### Privacy defaults (the non-negotiables)

- **Off by default.** `isEnabled` reads the `audioVaultEnabled` UserDefaults key;
  unset is `false`. `save` itself checks the flag and writes nothing when off, so a
  careless call site cannot create a hidden archive. No audio is written for a fresh
  install, ever.
- **Bounded when on:** newest 20 files, max age 7 days (`prune` runs after every save).
  At 32 kB/s that is ~1.9 MB per minute of dictation, so 20 typical 5–30 s dictations
  are ~3–10 MB — but 20 long double-tap-locked recordings are unbounded per file
  (a 10 min lock is ~19 MB; 20 of them ~385 MB). If that matters, add a byte cap to
  `AudioVault` beside `maxEntries`; `totalSizeBytes()` exists so the UI can show usage
  before it becomes a surprise.
- Directory mode 0700, files 0600. Logs carry file names and sample counts only
  (same rule as `log()` today: never the transcribed text).
- Turning the setting **off does not delete** existing files — surprising data loss is
  its own kind of bad. Instead the menu (below) shows the stored count/size and a
  "Delete Stored Audio" item next to the toggle, so the user wipes explicitly.
- `deleteAll()` logs `removed n/m`; the menu should re-read `entries()` after calling
  it and only report "deleted" if the vault is actually empty.

### Call site: `App.finish()` (main.swift)

One line, immediately after the empty/short-audio guards, i.e. once
`guard audio.count > 1600, ready` has passed, where `audio` came from `recorder.stop()`:

```swift
AudioVault.save(audio)   // no-op unless the user opted in; never throws
```

Save **before** transcription, not on success: the vault's whole purpose is surviving a
failed or garbled transcription, and the `catch` path in `finish()` is exactly when the
audio is needed. `save` does synchronous file I/O; `finish()` already runs off the paste
critical path here (pre-`Task`), but to keep the overlay snappy do it as the first line
inside the existing chained `Task`, before the engine call — order versus transcription
does not otherwise matter. Never save on the `hotkey.onCancel` path or from
`Recorder.stop()` itself: cancelled dictations were explicitly thrown away.

### Call sites: `App.buildMenu()` + two actions (main.swift)

Mirror the existing `togglePauseMedia(_:)` / `MediaPauser.shared.enabled` pattern,
directly below the "Pause Media While Dictating" item in `buildMenu()`:

- "Keep Audio for Recovery (7 days)" toggle → new `@objc func toggleAudioVault(_:)`
  flips `AudioVault.isEnabled`, updates `item.state`, logs the new value.
- "Delete Stored Audio" → new `@objc func deleteVaultAudio()` calls
  `AudioVault.deleteAll()`, then `setStatus(...)` with the post-wipe `entries().count`.
  Show `entries().count` + `totalSizeBytes()` in its title or a tooltip when non-zero
  (`ByteCountFormatter`); hide or disable it when the vault is empty. Menu titles are
  set once in `buildMenu()`, so refresh this one wherever `rebuildRecents()` is called,
  or accept a stale count until relaunch — refresh is three lines, do the refresh.
- Optional v1: "Open Vault Folder" (`NSWorkspace.shared.open(AudioVault.directory)`,
  same idiom as `editDictionary()`) so a WAV can be replayed in QuickTime by hand.
  This is the recovery path until re-transcription (§3.1) lands; without it, saved
  audio is write-only.

### Call site: `App.applicationDidFinishLaunching(_:)` (main.swift)

One line near `Dictionary.seedIfNeeded()`: `AudioVault.prune()`. Saves already prune,
but a vault left idle past 7 days (or disabled with files still in it) should still
expire on next launch rather than waiting for the next save.

## 3. Ranked next features

Ranking is value ÷ (effort + risk). Each item names the functions it touches.

### 3.1 Re-transcribe a vault recording (Clean or Verbatim) — do first

The payoff that justifies the vault existing at all: pick a stored WAV, run it through
either engine, paste the result. **Effort: medium. Risk: low.**

- Needs a `[Float]` loader for our own WAVs (44-byte header, 16-bit LE). BarkCore's
  `WavLoader.loadAudio(_:)` already parses exactly this format, but it is bench code —
  `fatalError` on bad input — so either harden it into a throwing/optional variant for
  app use or use `AVAudioFile` in the app target (which also tolerates foreign WAVs
  dropped in the folder). Do not call the bench version in the app as-is.
- UI: a "Stored Audio" submenu from `buildMenu()`, populated like `rebuildRecents()`
  from `AudioVault.entries()` (date + `durationSeconds` as the title — no transcript
  is stored, so there is nothing more identifying to show; that is a privacy plus).
- Action runs the same engine selection as `finish()`
  (`cleanTranscriber.transcribe(_:)` / `barkTranscriber.transcribe(_:)` in a detached
  task), then `Dictionary.apply` → `DictationFormatter.format` → `SpokenCommands.parse`
  → `Recents.add` → `Paster.paste`. Factor that tail of `finish()` into one helper
  both paths call instead of copying it — this is the only real refactor.
- "Clean vs Verbatim" choice: two submenu items per entry, or one item that uses the
  non-current engine when both are loaded. Note `loadModel()` today loads Clean **or**
  falls back to Bark, not both (`return` after Clean succeeds) — offering a genuine
  choice means lazily loading the other engine on first request, with `setStatus`
  feedback while it loads. That lazy-load is the bulk of the risk; ship
  "re-transcribe with the loaded engine" first if time-boxed.
- Same ordering rule as `finish()`: chain behind `transcriptionTail` so a re-paste
  cannot overtake a live dictation.

### 3.2 Add-to-dictionary from selection — do second

Misheard jargon is the daily friction; today fixing it means hand-editing
`~/.config/buddadawg/dictionary` via `editDictionary()`. Let the user select the
correctly-spelled word anywhere, hit a menu item, type/pick the heard form.
**Effort: small–medium. Risk: medium (all of it in the interaction, none in storage).**

- Reading another app's selection needs Accessibility (`AXUIElementCopyAttributeValue`
  `kAXSelectedTextAttribute` on `kAXFocusedUIElementAttribute`) — the app is already
  Accessibility-trusted for the event tap, so no new permission. But AX selection is
  flaky in Electron apps and terminals; the robust fallback is synthesize Cmd-C
  (tagged like `Paster.sendPasteKeystroke()` so `Hotkey` ignores it) and read
  `NSPasteboard` — which clobbers the clipboard, a real regression against the
  clipboard-stays design. Decide explicitly: AX first, Cmd-C only with a status-line
  warning and pasteboard save/restore around it.
- UI needs the "heard => written" pair, but only the written side comes from the
  selection. Cheapest honest flow: menu item "Add Selection to Dictionary…" opens a
  small panel pre-filled `<heard> => <selection>`, defaulting `heard` to the most
  recent `Recents.all` entry's matching mishearing is *not* derivable automatically —
  don't fake it; leave the field empty for the user to type what they said.
- Storage is trivial: append one line to `Dictionary.file` (validate: no `=>` or
  newline in either side, skip exact duplicates). `Dictionary.apply` re-reads the file
  per dictation already, so entries take effect immediately — verify that in review,
  it is what the current code does.

### 3.3 Per-app profiles — do third

Different behaviour per frontmost app: e.g. verbatim in a terminal, Clean in Mail,
no trailing space in code editors, vault forced off in password fields.
**Effort: large. Risk: medium.**

- `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` captured in
  `hotkey.onStart` (the app that will receive the paste is the one frontmost at fn-down;
  by `finish()` the menu/overlay must not be allowed to change the answer). Thread that
  bundle id through to `finish()` beside `mediaSession`.
- A profile is only worth building if it has ≥2 real knobs (engine choice, trailing
  space, `SpokenCommands` on/off). Config as a plain-text file beside the dictionary
  fits the existing idiom; a settings UI does not (there is no window code at all).
- Engine-per-app hits the same both-engines-loaded wall as §3.1 — land that lazy-load
  there first, then profiles reuse it. Password-field detection
  (`kAXSubroleAttribute` == `kAXSecureTextFieldSubrole`) is a separate, genuinely
  valuable slice: suppress `Recents.add` + vault save there. Consider shipping just
  that guard early, ahead of the general profile machinery.

### 3.4 Live preview — do last

Streaming partial transcript (in the overlay or inserted at the cursor) while speaking.
**Effort: large. Risk: high — recommend deferring until 3.1–3.3 are in.**

- Neither engine path streams today: `CleanTranscriber.transcribe(_:)` and
  `Transcriber.transcribe(_:)` are one-shot over a finished `[Float]`, and BarkCore's
  `segments` windowing is tuned for complete utterances. Preview means re-running the
  model over a growing buffer every ~300–500 ms (cost, ANE contention with the final
  pass) or a real streaming decoder — a research item, not a wiring item.
- Displaying in the `Overlay` (currently a text-free Metal glow, `State`:
  hidden/listening/transcribing/pasted/cancelled) needs a text surface beside the
  shader — doable, but it changes the overlay's whole character; decide that as a
  product question first, not as an implementation detail.
- Inserting provisional text at the cursor and revising it (select + re-paste) fights
  every host app differently (undo stacks, IMEs, collaborative editors) and risks
  leaving wrong text behind if the final pass disagrees. If preview ever ships,
  overlay-only, never in-document.
- `Recorder` already exposes everything needed (`level`, the accumulated samples are
  one accessor away), so the capture side is not the blocker — the model side is.

## 4. Deliberately not specified here

- A vault byte cap (noted in §2 as an option, not a default).
- Mid-utterance commands ("… new paragraph next thought …" in one hold). The parser's
  trailing-only rule is what keeps false positives at bay; revisit only with evidence
  from real use, and extend `SpokenCommandsTests` first.
- Any sync/backup of the vault or Recents. Local-only is the product's premise.
