# Buddadawg 🧈🐶

<p align="center"><img src="https://media.tenor.com/Esbsny0YGXoAAAAM/butta-dawg-dog-with-the-butta.gif" alt="The dog with the butter on him" width="260"></p>

Tap **fn**, talk, tap **fn** again. It types what you said — cleaned of ums and false starts — on-device, in any app.

- [Bark 3.0 Clean](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Clean) on the Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio) Core ML; original [Bark 3.0](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0) stays as a verbatim fallback
- Native Swift, no Python, no network at runtime (models are bundled)
- The transcript stays on your clipboard after it pastes, so a plain **⌘V** re-sends it anywhere

## Install

macOS 15+, Apple Silicon, Command Line Tools.

```sh
./scripts/install.sh
```

The install downloads ~640 MB of models and pre-compiles them for the Neural Engine
(first compile can take a minute or two). Allow Mic and Accessibility when asked.

## Use

- **Tap fn** to start recording, **tap again** to stop. With **Auto-Send Dictation** on (the default), the text is cleaned, pasted at the cursor, and **Enter is pressed automatically**. Turn Auto-Send off in the menu for paste-only — then **double-tap fn** while recording stops and sends.
- **Hold fn** still works as push-to-talk: hold, talk, release to finish.
- Double-tap **fn** within a few seconds after a paste re-sends the last dictation + Enter.
- **Smart Dictation** runs the transcript through an on-device cleanup pass before pasting. Two ways in: **fn + Control** (either order — tap them together while idle) or **three quick taps of fn** while idle (the fallback, and it only fires if the clip between the taps was silence). Needs Apple Intelligence; without it the gesture just dictates normally.
- **Command Mode**: select text in any app, then menu bar → **Command Selection… (Apple Intelligence)**, dictate what you want done ("make this shorter", "fix the grammar"), tap **fn** to finish — the rewrite replaces your selection. Needs Apple Intelligence.
- **Snippets**: dictate exactly `snippet <trigger>` to paste canned text — `~/.config/buddadawg/snippets`, `trigger => text` per line, `\n` for line breaks. Edit via **Edit Snippets…**.
- Spoken edits while dictating: **"scratch that"** (alone) discards the utterance, **"new paragraph"** / **"new line"** at the end of a phrase insert breaks, **"bullet point …"** at the start prefixes a bullet, and words like **"comma"**, **"question mark"**, **"open quote"** insert punctuation.
- While you talk, a floating HUD shows a live partial transcript (re-decoded ~every 2 s); the final pass on fn release is still authoritative.
- Dictating music pauses it while you talk — **Music, Spotify, and browser video** (including WebKit browsers, via the media key) — and resumes it after; only playback Buddadawg paused is resumed. Toggle with **Pause Media While Dictating**.
- **Keep Audio for Recovery** (menu bar, off by default) stores the last dictations as local WAVs for 7 days. **Stored Audio** re-transcribes one through the loaded engine and pastes it — the file is only deleted on success. **Delete Stored Audio** wipes the vault.
- Fix words two ways: select the correct spelling in any app → **Add Selection to Dictionary…**, or edit `~/.config/buddadawg/dictionary` directly via **Edit Dictionary…** (`tail scale => Tailscale`), seeded on first launch.
- Menu bar → **Recent Dictations** re-pastes a recent result (handy when a paste missed).
- Any other key while fn is held cancels (fn + key is a shortcut, not dictation); typing after a tap does not.
- Easter egg: dictate the Butter Dog meme phrase ("put the butter on him" and friends, or just "buddadawg") and the dog plays bottom-centre for a few seconds.
- Escape hatch: `defaults write co.alex.buddadawg engine bark` forces the verbatim engine.

## Test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # formatter, overlay phase clock, segmentation
.build/release/BarkBench Models ane clip.wav                          # Bark 3.0 (verbatim)
.build/release/CleanBench ModelsClean clip.wav                        # Bark 3.0 Clean
```

Models: Bark 3.0 / Bark 3.0 Clean by Conway Research (see `NOTICE` and `ModelsClean/NOTICE`),
derived from NVIDIA Parakeet TDT 0.6B v3.
