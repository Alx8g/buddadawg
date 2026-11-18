# Buddadawg — Launch Film Spec

**Date:** 12 Nov 2026 · **Repo state:** working tree as on disk (SwiftPM macOS app, Bark 3.0 Clean via FluidAudio default + BarkCore Bark 3.0 fallback, Metal bottom-edge glow, clipboard-stays paste, menu-bar recents, media auto-pause). Facts below were checked against `README.md`, `Package.swift`, and `Sources/Buddadawg/` (`main.swift`, `Hotkey.swift`, `MediaPauser.swift`, `Overlay.swift`) on disk. No build/run was performed for this doc.

**Deliverables this spec covers:** 40s hero (primary X post) · 15s cutdown (quote/post reply + vertical) · 6s silent loop (landing hero / pinned GIF-style asset). All cuts share one shoot + one screen-capture session.

> **Read this first — length tension with the data.** The best 2026 X data says accounts under 10k followers do best at **1–4 minutes** (median 546k views at 2–4 min vs 151k at 30–60s; n=1,550, §1.0). This brief mandates a 40s hero. The spec honours that (40s is tight, loop-friendly, and safe for non-Premium 140s limits), but **shoot and protect a 90–110s “proof cut” from the same material** (Shot 7 extended, uncut) and A/B it as the pinned reply or a Day-2 post. Do not discard the longer take. That longer cut is the single highest-leverage insurance in this document.

---

## 1. Research: what actually travelled on X in 2026

### 1.0 Method and honesty note

Primary sources directly inspected for this doc (full-text fetch):

- [Doomers AI — Best Product Launch Videos of 2026, Ranked by Views](https://doomers.ai/guides/product-launch-videos) — 1,550 video posts, 1,050 accounts, 7 Jan–19 Oct 2026; views from X public counts, length from file. This is the quantitative backbone below.
- [Doomers AI — Every AI Launch Video Looks the Same Now](https://doomers.ai/guides/launch-video-templates) — qualitative template analysis.
- [LaunchVideo.com / Atomik Growth — Startup Launch Video Strategy for X: 2026 Guide](https://www.launchvideo.com/blog/x-launch-video-strategy-guide-for-2026-specs-to-strategy) — specs, hook/caption practice (agency source; claims cross-checked where possible).
- [PiunikaWeb — “Give her the Porsche”: Wispr Flow viral challenge video](https://piunikaweb.com/2026/02/25/give-her-the-porsche-wispr-flow/) — contemporaneous reporting + embedded post (23 Feb 2026) for the closest dictation competitor.

**What “inspected” means here.** I read the full text of the four pages above, including their tables, embedded post copy, and linked directory entries. I did **not** frame-by-frame decode the X video files themselves (no direct X video playback was available in this session). Therefore:

- *Length, views, follower counts, post copy, dates* = **inspected** (directory/reporting data).
- *Hook, camera/motion, sound design* = **inferred** from written breakdowns, post text, thumbnails/descriptions, and the genre analysis — **except** where a source describes the opening explicitly (Wispr) or the template piece describes the shared visual language. Each example is labelled **Inspected / Snippet+inferred** so you know what to trust.
- **Do not quote any view count in public copy without re-checking it on X on posting day** — counts move and both directories note skew toward “launches people noticed.”

Key dataset facts (Doomers, inspected):

| Video length | Median views (all) | Median views, accounts <10k |
|---|---|---|
| 15–30s | 808k | 237k |
| 30–60s | 579k | 151k |
| 1–2 min | 620k | 289k |
| **2–4 min** | **782k** | **546k** |

- Median launch video overall: **61s**; middle half 36–94s. 93% landscape; 92% of launches carry video. 90% ≤140s (standard-account cap; Premium lifts to 4h on web/iOS).
- Square/vertical medians look higher (1.02M / 1.25M) but on tiny samples (n=72 / 32) — *not* a basis to master vertical-first for X. Pattern: landscape master on X, vertical derivative for TikTok/Reels/LinkedIn.
- Three repeating habits in top small-account videos: (1) one plain claim in the post, video as proof; (2) posted by a **person** (7/10), usually the founder, not a brand handle; (3) long enough to see the product work (8/10 >60s, median 1:34).
- LaunchVideo guide (snippet-level, agency): face in opening frames aids retention; hardcode captions for sound-off; keep tweet copy minimal; first frame must work as thumbnail. Treat “7× vertical” / “10× video” multiples as vendor-cited, not verified here.

### 1.1 Eight concrete examples (last ~9 months; all posted on X in 2026)

#### 1. xAI — Voice Cloning demo · 1 May 2026 · 0:32 · 204M views · 2.1M followers
- **Link:** via [Doomers directory entry](https://doomers.ai/guides/product-launch-videos) → `/launches/spacexai-voice-cloning` (open there for the live X post; direct X URL not captured in inspected text — verify before citing).
- **Evidence level:** Snippet+inferred for craft; inspected for numbers.
- **Hook (0–2s):** Single impossibility claim proved instantly — a cloned voice saying something it never said. The proof *is* the hook; no logo, no preamble.
- **Camera/motion:** Micro-demo grammar: static UI/waveform, hard cuts between source voice → clone, kinetic captions synced to speech. No screen-in-3D-space needed; the audio swap is the effect.
- **Sound:** Voice-first; music (if any) mixed under intelligibility. Caption strategy is word-by-word burn-in so the “did it really say that?” check works muted.
- **Loop/end:** Short enough to replay as verification (“watch again to check”). Minimal end-card.
- **Takeaway for Buddadawg:** Voice products win when the *audio transformation itself* is visible in 2s. Our equivalent: messy spoken audio → clean text, with the glow as the visual waveform. Do not open on branding.

#### 2. OpenAI — GPT-6 “Astra” film · 3 Sep 2026 · 2:43 · 137M views · 5.3M followers
- **Link:** via Doomers `/launches/openai-gpt-6-astra`.
- **Evidence level:** Snippet+inferred for craft; inspected for numbers + post claim (“can do anything you can do on a computer,” per Doomers summary).
- **Hook:** Maximal claim in post copy; film opens in medias res on the computer being used autonomously. Doubt drives watch time.
- **Camera/motion:** The “cinematic template” executed at frontier budget: dark UI, slow push-ins, one-word text cards on the beat, abstract geometry intercut with real task screens. Speed is *shown* via task completion, not stated.
- **Sound/captions:** Near-whisper VO + ambient synth rise (template traits); full burn-in captions.
- **Loop/end:** Resolves to logo/tagline; too long to loop — built for saves/bookmarks, not replays.
- **Takeaway:** The template works *once you already have 5M followers*. For an unknown OSS Mac app, copying this shape triggers skip-by-recognition in ~2s (see §1.2). Steal only the structure: **one sentence claim, then proof**.

#### 3. Anthropic — Claude computer use · 23 Mar 2026 · 1:13 · 78.4M views · 1.9M followers
- **Link:** via Doomers `/launches/claude-enable-computer-complete`.
- **Evidence level:** Snippet+inferred for craft; inspected for numbers + post claim (“can now use your computer to complete tasks”).
- **Hook:** Cursor moving with no hands in the first seconds. Viewer question forms instantly: “who is driving?”
- **Camera/motion:** Mostly honest screen recording with push/punch-ins on the active element; match cuts between intent text → UI action. Minimal 3D dressing; legibility prioritised.
- **Sound/captions:** Restrained music bed, task narration via captions; UI sounds retained just enough to feel real.
- **Loop/end:** Task-complete payoff, then held end state (screenshot-able proof frame).
- **Takeaway:** Closest big-lab analogue to Buddadawg’s job: make an invisible capability (agent/dictation) legible by keeping the *real screen* centre-frame and letting one anomalous motion (self-driving cursor / voice-driven glow) carry the wonder.

#### 4. Cursor — Origin (code hosting) · 17 Aug 2026 · 0:31 · 26.3M views · 486k followers
- **Links:** [cursor-origin.dev](https://cursor-origin.dev/) (describes the 17 Aug launch video + Codebase tab); Doomers `/launches/cursor-origin-code-hosting`; indexed at [What Ships — Developer tools](https://whatships.com/videos/category/developer-tools/3/).
- **Evidence level:** Snippet+inferred (product/date corroborated by search results + VentureBeat via Slashdot summary; shot language inferred from Cursor’s established product-film style and the 31s runtime — **verify against the live post before copying any specific move**).
- **Hook:** Category provocation (“GitHub optional” in coverage) + product surface filling frame immediately. Developers stay to check whether repos/PRs really live inside the editor.
- **Camera/motion:** Screen-in-3D-space: editor window tilted in a dark void, whip/push between Repo → PR → Agent panes, speed-ramped cursor, kinetic labels. Cuts on action, not on VO.
- **Sound/captions:** Percussive electronic bed, UI clicks designed louder than real; sparse burn-in labels rather than full subtitles (no spoken VO to caption).
- **Loop/end:** Ends on the unified workspace hero state; short runtime invites replay.
- **Takeaway:** Dev-tool polish benchmark. Buddadawg should borrow the *rhythm* (cut on paste-landings, one idea per shot) but **not** the void/3D tilt — our differentiator is physical (fn key, real desk, real voice). Grounding beats floating UI for a dictation story.

#### 5. TypeSafe AI — “Jev” · 15 Sep 2026 · 2:56 · 40M views · 1,500 followers (~27,000× following)
- **Link:** via Doomers `/launches/typesafe-ai` + [case study](https://doomers.ai/work/typesafe-ai-case-study) (150k waitlist signups in 24h claimed there).
- **Evidence level:** Inspected for numbers/outcome claims; inferred for craft (case-study body not fetched in this session — treat craft notes as hypotheses to verify).
- **Hook:** Unknown-account outlier: a near-3-minute film that still travelled. That length only works if the first seconds pose a concrete, checkable problem and the demo keeps resolving it. Founder-posted.
- **Camera/motion (inferred):** Sustained product-working footage over montage; the length *is* the signal that there is a real system, not a teaser.
- **Sound/captions:** Assume full captions (long technical demo cannot survive muted without them).
- **Takeaway:** Small accounts need *more proof time*, not less. This is the strongest single argument for protecting Buddadawg’s 90–110s proof cut even though the hero is 40s.

#### 6. Pine Computer · 9 Oct 2026 · 1:43 · 24.3M views · ~1,200 followers
- **Link:** via Doomers `/launches/pine-computer`.
- **Evidence level:** Inspected for numbers; inferred for craft.
- **Hook/motion:** Second Doomers-run small-account outlier at 1:43. Reinforces the pattern: person-posted, >60s, one claim proved at length.
- **Takeaway:** Buddadawg’s natural duration for “hold fn → think out loud → clean paragraph → paste everywhere” is 60–100s uncut. The 40s hero must therefore *compress* (speed-ramp the middle, §3) rather than *omit* the proof.

#### 7. Wispr Flow — Android launch “Porsche challenge” · 23 Feb 2026 · founder post (@tankots)
- **Links:** [X post 2025981424470479008](https://twitter.com/tankots/status/2025981424470479008) (from inspected article); [PiunikaWeb report](https://piunikaweb.com/2026/02/25/give-her-the-porsche-wispr-flow/); separate 5 Aug 2026 Wispr Flow launch logged at 19.7M views / 33,977 followers in [Atomik Growth directory summary](https://www.atomikgrowth.com/blog/launch-on-x-vs-product-hunt-vs-linkedin) (snippet; verify on X).
- **Evidence level:** **Inspected** for premise, post copy, and failure mode (article quotes the post verbatim and timestamps the error); snippet for engagement totals.
- **Hook (0–2s):** Founder to camera with a wager: *“We offered 5 people a Porsche 911 GT3 RS if they could get @WisprFlow to make a mistake.”* Human face + stakes + falsifiable claim in one breath. Exactly the LaunchVideo “face + 3s outcome hook” pattern.
- **Structure:** Five challengers speak fast / code-switch / use fillers and odd names; on-screen transcription appears perfect. Post copy adds “3× more accurate than ChatGPT, Claude, or Siri” + Android download + 6 months Pro free.
- **Camera/motion:** Street/challenge coverage — handheld mediums, jump cuts per challenger, phone/screen inserts with captions large enough to audit. Polish is in casting and stakes, not VFX.
- **Sound/captions:** Location voice is the product; burn-in transcription doubles as caption track. **That is also where it broke:** viewers frame-checked ~1:32 and found dropped Hindi morphology (*“hu”* dropped; *“le ana” → “lana”*). A breakout quote-post (“Give her the Porsche,” 200k+ views per report) hijacked the launch narrative.
- **Loop/end:** Giveaway CTA end; replay driven by dispute, not design.
- **Takeaways for Buddadawg (directly load-bearing):**
  1. A dictation launch will be **audited word-by-word**. Any “cleaned” transcript shown must be a real, unretouched output, and the raw audio must be kept as evidence (see §6).
  2. Never wager perfection. Buddadawg’s claim is *character* (thinking out loud, local, free), not infallibility. Wispr bought attention with a claim its own video disproved.
  3. Founder face + wager outperforms brand film for dictation because trust is the product. Buddadawg’s equivalent stake is honest: **dictate the launch post itself, live, including its ums — then show what Clean kept and cut.**

#### 8. OpenBrand (open-source brand-asset puller) · 13 Mar 2026 · 0:16 · 7.7M views · 700 followers
- **Link:** via Doomers `/launches/ethan-jiang`.
- **Evidence level:** Inspected for numbers + one-line product description; inferred for craft.
- **Hook/motion:** The only sub-20s video in the small-account top 10. It works because *one action shows the whole product*: paste URL → logos/colours appear. Single speed-ramped screen capture, no VO needed.
- **Sound/captions:** Minimal; the transformation is self-captioning.
- **Loop:** Perfect loop by construction (empty → full → empty).
- **Takeaway:** This is the template for Buddadawg’s **6s loop**: one fn hold, one sentence, one paste. If the single action is not legible muted in 6s, the loop fails — test it first, before shooting the 40s.

### 1.2 Distilled rules for Buddadawg (and one anti-rule)

1. **Post = one plain claim; video = proof.** Buddadawg claim candidate: “Hold fn. Think out loud. It types the cleaned version — locally, free.” Every shot must verify a clause of that sentence.
2. **Face + key in 2s, product working by 4s.** No dark-void logo open. The template piece is blunt: viewers pattern-match genre in ~2s and skip before any claim lands. Our opening shape (macro fn key, room tone, real voice) must *not* read as “AI launch film.”
3. **Real captures beat renders for technical trust.** Doomers explicitly notes screen recordings often outperform produced films for technical products. Polish for Buddadawg = lighting, sound, edit rhythm, and honest captures — not 3D UI.
4. **Captions are the audit surface.** Burn in the *dictated* words and show Clean’s edits as visible strikes/highlights. Muted viewers get the story; sound-on viewers get proof. QC every word (Wispr lesson).
5. **Person-post it.** Launch from the maker’s personal X account; brand/repo account quote-posts. 7/10 small-account winners were personal posts.
6. **Anti-rule — do not use:** ambient-synth slow reveal, particles/wireframe globe, one-word text cards (“Think. Speak. Ship.”), whisper VO, white-out logo resolve. Each is individually fine and collectively fatal for an unknown product in 2026.

---

## 2. Buddadawg film: concept and voice decision

### 2.1 Concept — “This film was dictated.”

A maker at a real desk holds **fn**, thinks out loud for one unbroken breath-group, and lets go. The messy thought lands as clean text. The film then *uses* that text: the same clipboard payload pastes into three different apps with three plain ⌘V hits, while music that auto-paused for the dictation resumes underneath. The manifesto is not narration *about* dictation. It is dictation, caught in the act, ums and restarts included — and the edit shows Bark 3.0 Clean doing the tidying that the voiceover describes.

Why this wins for Buddadawg specifically:

- It proves every differentiator without listing features: hold-to-talk (finger visible), glow-follows-voice (bottom edge alive only while speaking), media auto-pause/resume (audible), clipboard-stays (same text, three pastes, no re-dictation), menu recents (recovery beat), local/free (end-card + post copy, not VFX).
- It is un-copyable by Wispr-style cloud dictation without conceding the local/OSS point, and un-fakeable in the way that burned Wispr: the raw take and the shipped transcript must match, because the audience hears both.
- Tone matches the product name and README voice (🧈🐶, “dog with the butter on him”): warm, deadpan, zero “future of work” language. Butter appears once, physically, as a joke with restraint (prop note in §7). No mascot animation.

### 2.2 VO vs dictated-live: decision

**Dictated-live is the hero track. There is no separate studio VO in the 40s or 15s.**

- Record the manifesto *through Buddadawg itself* on the hero Mac (same mic chain the audience sees), in 3–5 full takes. Pick one complete take for picture; do not comp syllables. Keep room tone, breaths, and one genuine restart (“— no wait —”) because Clean removing it on screen is the demo.
- The on-screen transcript shown in Shots 5–7 must be that take’s actual Buddadawg output (paste the real clipboard result into the demo apps during capture; never retype it in the editor). Save the take’s `.wav`, the verbatim Bark output, and the Clean output side-by-side as evidence files (§6).
- If intelligibility needs help, fix it with mic placement and a quieter room, not ADR. One exception: the final tag line (see script) may be re-recorded as a cleaner button *through the same chain* if the hero take’s ending is ragged — disclose nothing, because it is still product audio, but do not sweeten it into announcer voice.
- Rationale: a polished VO would contradict the film’s thesis (“dictation never feels like typing”) and read as the generic template. The slight roughness *is* the credibility signal, exactly as raw screen recording beats rendered film for technical launches.

### 2.3 Script (hero take — dictate verbatim, including the marked stumble)

Target: ~95–110 spoken words ≈ 38–44s at natural pace. Bracketed notes are performance direction, not spoken. The film speed-ramps the middle dictation (§3) so the *heard* duration is shorter than wall-clock; the un-ramped audio is preserved for the 90s+ proof cut.

> [Holding fn. Music playing quietly from the Mac. It ducks/pauses as recording starts.]
>
> “The thing about dictation is — it never really feels like typing. You think out loud, and the sentences come out longer, and messier, and — no wait, that’s the point, actually. You get the thought down before you’ve, um, edited it into something smaller. So I just — hold fn, say the whole thing, and let it clean up after me. And this? This whole launch post was dictated. Locally. For free.”
>
> [Release fn. Beat. Paste lands. Music resumes.]

**What Clean should visibly do to this take** (verify on the actual build; if the real output differs, show the real output and adjust captions — never fake the cleanup):

- Drop “um” and the false start “— no wait, that’s the point, actually” → either removed or folded, per real Clean behaviour.
- Normalise capitalisation/punctuation; preserve “fn” correctly (dictionary entry — confirm `tail scale => Tailscale`-style seeding handles “fn”; if Clean emits “eff en” or “fun,” add the dictionary fix *before* the shoot and show the dictionary beat honestly, or rephrase to “hold the fn key” and test again).
- The struck-through words appear briefly in captions (§4) so muted viewers see the edit, then resolve to the clean line.

**Number beat (on-screen only, not spoken):** during Shot 8, lower-third: `46.7s spoken → 432ms transcribed · M1 Pro`. Do not speak benchmarks; numbers read better and screenshot better. This claim requires evidence before use (§6).

## 3. Shot-by-shot — 40s hero (master 16:9; protect 9:16 centre)

**Master specs:** 16:9, 2560×1440 capture / 1920×1080 export (H.264, AAC-LC), 30fps (60fps capture for ramp/slow-mo options), burned-in captions + separate `.srt` sidecar. Shoot camera 4K for punch-ins. Keep all critical action inside a centre 9:16-safe column (fn key, mouth, caret, glow) so the vertical derivative is a reframe, not a reshoot. Total: **40.0s**. Timecodes are edit targets (±0.3s).

| # | TC | Dur | Shot / lens / movement | Picture + exact on-screen text | Sound | Transition in |
|---|---|---|---|---|---|---|
| 1 | 0:00–0:02 | 2.0s | Macro, 100mm equiv., locked-off, shallow focus | Finger comes down on **fn** (bottom-left of built-in keyboard). Key legend readable. No logo. Caption (large, bottom-third): `hold fn.` | Real room tone + key thock (production sound, lifted +3dB). Music *already playing* faintly from Mac speakers. | Cold open on black? **No** — first frame is the keyboard (see §5). Hard start. |
| 2 | 0:02–0:04 | 2.0s | Medium profile, 35mm equiv., slow 10cm push-in | Maker mid-sentence, eyes off-screen (thinking, not presenting). Bottom of frame catches screen edge: glow rising. Caption continues dictated words. Music audibly **pauses** at 0:02.5. | Dictated line begins: “The thing about dictation is —” | Match cut on finger pressure → face (same real moment; shoot with 2 cameras or repeat action). |
| 3 | 0:04–0:09 | 5.0s | Over-shoulder → screen, 50mm equiv., gentle tilt down | Real desktop: empty doc with blinking caret. **Glow climbs with voice peaks** along bottom edge. No text yet (Buddadawg pastes on release — do not fake streaming words unless the build streams). Caption tracks speech word-by-word. | “…it never really feels like typing. You think out loud…” Breaths kept. | Continuous tilt from face to screen (one move, no cut) if geography allows; else motivated cut on head turn. |
| 4 | 0:09–0:14 | 5.0s | Screen capture (native, full-bleed), 110% slow push | Caret still waiting; glow is the motion. Captions show mess arriving: `…come out longer, and messier, and —` | Dictation continues at natural pace. | Cut to capture **on a voice peak** (glow spike masks the edit). |
| 5 | 0:14–0:20 | 6.0s | Screen capture, locked; **speed-ramp 1×→1.6×→1×** over the stumble | Captions show the restart, then struck words grey/strike: `~~no wait~~` `~~um~~`. On-screen micro-label (top-right, small mono): `Bark 3.0 Clean · Neural Engine · on-device`. | “…no wait, that’s the point…” — ramp is audible honesty: we are compressing *time*, not editing *words*. Add tiny “sped up” footnote in post copy, not burned in (see §6). | Ramp begins on inhale. |
| 6 | 0:20–0:23 | 3.0s | Macro fn key again, 100mm, locked | Finger **lifts**. Glow (reflected on bezel/desk edge) blooms then fades (pasted state). Caption: `let go.` | Key release click. One beat of near-silence (processing). | Whip-pan back from screen to keyboard (practical pan, 6 frames of blur). |
| 7 | 0:23–0:27 | 4.0s | Screen capture, punch to 150% on paragraph | **Payoff:** clean paragraph lands in one paste. Hold 1.5s readable. This frame must be screenshottable: full manifesto text, no UI chrome over it. | Soft system paste *absence* of sound is fine; add faint paper-like tick in mix (designed, –18dB). Music **resumes** under at 0:26. | Cut on finger lift (J-cut: hear lift 4 frames before seeing paste). |
| 8 | 0:27–0:31 | 4.0s | Split rhythm: 3 quick capture inserts, each ~1.2s, matched caret position | Same text via **⌘V** into: (a) Mail compose, (b) Slack/Discord message field, (c) code editor comment / Git commit box. Lower-third: `46.7s spoken → 432ms · M1 Pro` then `stays on your clipboard — ⌘V again, anywhere`. Keycap graphics `⌘V` pop on each paste. | Three soft ⌘V ticks on the beat; music now clearly back. No VO. | Match cuts on caret (same screen x/y). Fastest passage in film. |
| 9 | 0:31–0:34 | 3.0s | Menu-bar capture insert, 200% crop, locked | Cursor opens Buddadawg menu → **Recent Dictations** → hover top item (the manifesto, truncated). Label: `missed a paste? it’s in recents`. Do not click (avoid re-paste confusion); just prove it exists. | Menu click (real). | Cut on cursor travel. |
| 10 | 0:34–0:37 | 3.0s | Double-tap insert: macro fn, then wide hands-free | Two quick taps (`fn fn`), hands leave keyboard and pick up coffee; glow alive, maker still talking off-camera tail: “…locally. For free.” Caption: `double-tap to lock — hands free`. Tap fn (heard) to finish; glow settles. | Two taps are the sound design. Keep them dry and satisfying. | Cut back to macro (bookend with Shot 1). |
| 11 | 0:37–0:40 | 3.0s | End-card over dimmed real desk (not black void) | Centred, large: `Buddadawg 🧈🐶` / `Hold fn. Think out loud.` / small: `Free · Open source · macOS · link in post`. Glow breathes once along bottom edge, then holds. Final frame freezes glow mid-breathe for loop splice (§3.3). | Music resolves; room tone tail. No sting, no logo whoosh. | Fade of picture only (audio L-cut). |

**Performance notes**

- Maker never looks into lens except optionally a single glance on “And this?” — the film is observed work, not a pitch. Wardrobe: plain, no logos, no hoodie-founder costume.
- Desktop must look *used but tidy*: 2–3 real windows, personal wallpaper (cleared image), Dock visible. An empty showroom desktop reads as fake to the exact audience that frame-checks dictation.
- Glow legibility on camera: test Exposure so the Metal glow reads on the over-shoulder without blowing out. The glow is 240pt tall and voice-warped (`Overlay.swift`); in capture it will be crisp, on camera it may moiré — prefer capture for proof shots (4, 5, 7), camera for human shots (1–3, 6, 10).

### 3.1 15s cutdown (quote-post / reply asset; also 9:16 master source)

Rebuilt, not merely trimmed. One claim: *messy thought in, clean text out, paste anywhere.*

| TC | Shot | On-screen text |
|---|---|---|
| 0:00–0:02 | Shot 1 macro fn press | `hold fn.` |
| 0:02–0:07 | Capture: glow + captions with strike-through cleanup (Shots 4–5 compressed) | dictated captions, strikes visible |
| 0:07–0:09 | Finger lift → paste lands (Shots 6–7) | `let go.` |
| 0:09–0:13 | Two ⌘V landings only (Mail + editor; drop Slack) | `⌘V anywhere · stays on clipboard` |
| 0:13–0:15 | End-card | `Buddadawg — free, local dictation for Mac` |

Audio: first sentence of manifesto only (“The thing about dictation is, it never really feels like typing.”) + music pause/resume still audible. Export 16:9 and 9:16 (reframe: fn key lower-third, captions upper-third in vertical).

### 3.2 6s loop (silent, autoplay hero for README/landing)

OpenBrand rule: one action, legible muted.

- 0.0s: caret + `hold fn.` → glow rises (voice implied by glow + caption words appearing as *captions only*, not as fake streaming paste).
- 3.5s: `let go.` → paragraph pastes.
- 5.0s: `⌘V` → same paragraph in second app.
- 6.0s: hard loop to empty caret (glow at identical height/phase on first and last frame; 2-frame crossfade only if phase cannot be matched — prefer matched phase via picking loop points on zero-crossings of the glow).

No end-card, no logo hold (loop must not stall). File: muted MP4 + poster frame = loop frame 0.

### 3.3 Loop/end-card logic (hero)

Hero does not seamlessly loop (40s narrative). Instead it *bookends*: Shot 11’s breathing glow matches Shot 3’s resting glow, so X autoplay replay feels continuous. End-card holds ≥2s at full opacity for screenshotting and for X’s end-screen UI to settle. Never end on black.

## 4. Screen-recording choreography

**Principle:** captures are evidence. Record at native Retina (or 2× display) via Screen Studio / OBS / QuickTime (pick one and note it in the project file), cursor smoothed *lightly* or not at all — over-smoothed cursors read as adverts. Record system audio separately so the media pause/resume is provable.

**Pre-flight (before any take):**

1. Fresh demo user profile or cleaned desktop; notifications OFF (Focus), no personal messages/emails visible in any app used. Seed Mail/Slack/editor with fictional content.
2. Buddadawg engine = Clean (default). Confirm menu shows `Ready (…): hold fn, double-tap to lock`. Pre-warm models (one throwaway dictation) so no first-compile pause hits the hero take.
3. Dictionary: verify “Buddadawg,” “fn,” and any names in the script transcribe correctly; add entries via **Edit Dictionary…** if needed *and keep that menu state* (it is part of the honest setup; do not hide it if asked).
4. Music source: local file playing in Music.app or browser tab that Buddadawg’s `MediaPauser` reliably pauses (test MRMediaRemote path on the shoot machine; have a fallback: if auto-pause fails on camera, pause manually *out of frame* is **not** acceptable — reshoot with a source that works, and log the failure per §6).
5. Clipboard discipline: clear clipboard, then the *only* payloads during Shots 7–9 are real dictation outputs. Disable clipboard managers that might show history popups.

**App landing order (hero Shot 8) and why:**

1. **Primary doc (Shot 7):** TextEdit / Pages / Bear-style blank doc — neutral, readable serif or system font at large size. This is the proof frame; choose the app with the cleanest full-bleed capture.
2. **Mail compose** — “real work” credibility; subject pre-filled `launch notes` so paste context is instant.
3. **Slack or Discord** (whichever the maker genuinely uses; fake workspace, 2–3 channels) — shows paste into a field that is *not* a document.
4. **Code editor comment / commit message** — winks at the dev audience without claiming dictation writes code; paste as a comment, never as code.

Each landing: cursor already in field, single ⌘V, hold ≥20 frames readable, cut. Do not type corrections after paste on camera. If Clean makes an error on the hero take, that take is not the hero (retake) — but archive it; a “here’s a miss + dictionary fix” follow-up post is excellent Day-3 content and pre-empts audit threads.

**What never to fake:** streaming word-by-word insertion (unless the shipped build does it), transcription speed (no hidden cuts inside Shot 6→7 processing beat beyond the declared ramp in Shot 5), glow behaviour (no AE glow replacement), clipboard contents.

## 5. Sound, captions, first frame

### Sound design & music

- **Hierarchy:** voice intelligibility > key/glow Foley > music. Mix for laptop speakers and earbuds; mono-compatible.
- **Production sound is the design:** fn thock, release click, breaths, room. Record with a close mic (lav or shotgun just out of frame) *in addition to* the Mac’s dictation mic if needed for quality — but the *dictation* must be captured by the real input path. If two mics are used, document it; do not substitute a studio read for the dictated track.
- **Music:** one warm, lo-fi instrumental loop with a clear pause/resume edge (the auto-pause demo fails if the track is ambient wash with no audible cut). License for organic social + landing page in perpetuity; keep stems if ducking is needed. No trending-audio dependency (X launch must be self-contained and repostable).
- **Levels:** voice peaks ≈ –6dBFS, music under voice ≈ –24dB, music solo ≈ –14dB. True-peak ≤ –1dB. Export loudness ≈ –14 LUFS integrated for social consistency.
- **Silence is a feature:** the 0.5s processing beat (Shot 6→7) stays near-silent. Do not fill it with a riser.

### Captions

- **Burned-in** (styled, high-contrast, safe from X UI: bottom 18% kept clear of X progress/controls; in 9:16 keep captions above bottom 25%) **plus** uploaded `.srt` (X supports SRT via Media Studio / post flow where available — verify on posting day; burned-in remains the guarantee).
- Style: system-sans semibold, ≤2 lines, ≤42 chars/line, word-timed for dictated passage. Clean’s deletions shown as brief strikethrough + fade (max 0.8s) so muted viewers perceive editing. Speaker is always the maker; no speaker labels needed.
- On-screen *labels* (specs, `⌘V`, end-card) are **not** captions — set them in a distinct mono/small style so Deaf viewers can tell narration from annotation. Include `[music pauses]` / `[music resumes]` in the SRT (not burned in) for full accessibility.
- QC pass: one person watches muted start-to-finish and transcribes what they understood; any gap is a caption bug. Second person frame-checks every burned word against the archived Clean output (Wispr protocol).

### First frame / thumbnail

X autoplays muted in-feed, but the poster/first frame decides the click in search, embeds, and slow connections.

- **Hero first frame (export frame 0):** macro fn key with fingertip *just contacting* (not yet pressed), legend sharp, warm desk light, caption `hold fn.` already present. It must read at 200px wide: one key, one finger, two words. No logo, no title card.
- **Custom thumbnail (if X offers frame pick):** Shot 7 payoff (clean paragraph + glow) is more informative but less curious. Recommendation: keep frame-0 thumbnail for the main post (curiosity + motion on autoplay), use the payoff frame as the *reply* image and landing poster. A/B only if posting twice (do not delete/repost the hero to test thumbnails).
- 6s loop poster = empty caret + `hold fn.` (loop start). 15s vertical thumbnail = fn macro reframed.

## 6. Claims register — evidence required before use

Nothing in this table may appear in burned-in text, post copy, or replies until the evidence exists and is linked/archived. “Brief-supplied” ≠ verified.

| Claim as it would appear | Status today | Evidence to capture before posting |
|---|---|---|
| `46.7s spoken → 432ms transcribed · M1 Pro` (Shot 8) | **Brief-supplied, unverified in this doc.** No bench was run for this spec. | On the shoot Mac (state chip/RAM/macOS): record the 46.7s clip, run `CleanBench ModelsClean clip.wav` 5×, report median wall-clock *and* model time; keep terminal log + wav. If median ≠ 432ms, the film uses the measured number. Also time end-to-end (fn release → paste) on camera; if that differs materially, caption must say what was measured (e.g. “transcription” vs “release-to-paste”). |
| “Bark 3.0 Clean on the Neural Engine” | Supported by README/Package (FluidAudio Core ML) + `CleanTranscriber` presence; ANE utilisation not measured here. | Screenshot/log of compute units or FluidAudio config; Instruments/Core ML report optional. Safe wording until then: “Bark 3.0 Clean · on-device.” |
| “Fully local / no network at runtime” | README states it; not audited here. | Little Snitch / `nettop` capture during a dictation + code check for network calls outside install-time model download. Wording must scope install: “no network at runtime (models download once at install, ~640MB)”. |
| “Free / open source” | Positioning per brief; licence file not verified in this pass. | Confirm `LICENSE` in repo + model licences (`NOTICE`, `ModelsClean/NOTICE`: Conway Bark derived from NVIDIA Parakeet). End-card may say “Free · Open source” only for the app code; do not imply models are under the same licence. Credit line in post thread. |
| Media “auto-pauses and resumes” | `MediaPauser.swift` (MRMediaRemote) inspected; behaviour varies by source app. | Shoot-day matrix: Music.app, Spotify, YouTube (Safari/Chrome) — record which pause/resume cleanly. Film only a source that works; reply copy lists tested sources. |
| “Cleaned of ums and false starts” | README claim; exact behaviour take-dependent. | Archive hero take trio: `take.wav` + Bark verbatim `.txt` + Clean `.txt`. Captions/strikes must match the Clean file character-for-character. |
| “Works in any app” | Paste-based (Accessibility + ⌘V) — broadly true, with secure-field / non-standard-field edge cases. | Test each filmed app + one known-hard field; copy should say “in any app that takes a paste” in the thread (hero end-card may stay short, thread carries the qualifier). |
| Any accuracy comparison (vs Siri/Whisper/Wispr) | **Do not use.** No benchmark exists; Wispr’s “3×” claim is the cautionary tale. | N/A — compete on local/free/feel, not WER, until a reproducible bench ships. |
| macOS / hardware floor | README: macOS 15+, Apple Silicon. | Post copy + alt text state the floor so Intel/older-macOS viewers are not misled. |

**Speed-ramp disclosure:** Shot 5 ramps to 1.6×. Add one line in the post thread: “Middle of the dictation sped up for time; words unedited — raw audio + outputs linked.” Hiding a ramp in a dictation demo is how audit threads start.

## 7. Asset / equipment checklist

**Shoot (half-day, one desk, natural light + one practical):**

- [ ] Hero MacBook (built-in keyboard for fn macro; external keyboards move/omit fn — use built-in) + power, cleaned screen/keys, demo profile ready (§4 pre-flight)
- [ ] Camera A: 4K body + 35mm & 50mm equiv. primes (face/over-shoulder); Camera B or phone on overhead/macro arm for fn key (100mm equiv. or macro mode), tripods/monopod for push-in
- [ ] Close mic (lav on maker or shotgun overhead) + recorder; Mac input set to the *audience-plausible* mic (built-in or AirPods — decide and be consistent; if lav feeds dictation, say so in thread). Headphones for playback checks (not worn on camera unless that is the real workflow)
- [ ] Lighting: window key + warm desk practical; flag screen reflections; test glow exposure/moiré before takes
- [ ] Props: coffee cup (hands-free beat), notebook, *one* small butter dish at desk edge, out of focus, Shots 3/11 only — the single 🧈 joke. No dog costume, no Tenor GIF on screen (rights + tone).
- [ ] Script printed large (off-camera), take slate (take no. + engine + dictionary state), spare batteries/cards, lens wipes

**Capture/edit:**

- [ ] Screen capture at native res, 60fps, system audio isolated; cursor visible; Focus mode on
- [ ] Licensed music track + licence PDF saved to project; Foley (keys) from production sound preferred over library
- [ ] Edit project with named sequences: `HERO_40s_16x9`, `CUT_15s_16x9`, `CUT_15s_9x16`, `LOOP_6s`, `PROOF_90s+_UNCUT`; captions as editable text (not flattened) until final burn
- [ ] Evidence folder: hero `take.wav`, verbatim + Clean `.txt`, bench logs (§6), music licence, thumbnail exports

**Exports (all H.264 + AAC-LC, fast-start):**

| File | Spec | Captions |
|---|---|---|
| `buddadawg-hero-40s-1080p.mp4` | 1920×1080, 30fps, ~12–16 Mbps | burned-in + `…-40s.srt` |
| `buddadawg-cut-15s-1080p.mp4` | 1920×1080, 30fps | burned-in + SRT |
| `buddadawg-cut-15s-vertical.mp4` | 1080×1920, 30fps | burned-in (reframed) |
| `buddadawg-loop-6s.mp4` | 1920×1080 (or 1280×720 for README weight), muted | burned-in labels only |
| `buddadawg-proof-uncut.mp4` | native capture res, un-ramped hero take | SRT |
| Posters | `poster-fn.jpg` (frame 0), `poster-payoff.jpg` (Shot 7) | — |

Check file-size/duration limits against the posting account tier on the day (standard ≈140s cap is not a constraint at 40s; still verify Premium status if the proof cut is posted natively).

## 8. Posting copy (3 variants) + thread plan

Post natively (upload, never link-out to YouTube for the hero), from the **maker’s personal account**, link in first reply (keeps hero clean; verify current X link-suppression behaviour on the day — if links in main post are fine for the account tier, Variant A may carry the link directly). Pin the post. Repo/brand account quote-posts within the first hour. All variants assume §6 claims cleared; bracketed links to fill.

**Variant A — Manifesto (recommended hero pairing; the post text *is* dictation output):**

> The thing about dictation is it never really feels like typing. You think out loud, and the sentences come out longer and messier — and that’s the point.
>
> So I made Buddadawg: hold fn, say the whole thing, let go. It types the cleaned version, on-device, in any app.
>
> This post was dictated with it. Free + open source for Mac 🧈🐶

**Variant B — Proof/numbers (use if bench evidence is strong; otherwise do not use):**

> 46.7 seconds of thinking out loud → clean text in 432ms. On my M1 Pro. No cloud.
>
> Buddadawg: hold fn (or double-tap to lock), talk, let go. Bark 3.0 Clean on the Neural Engine, paste stays on your clipboard for ⌘V anywhere.
>
> Free, open source, macOS 15+ / Apple Silicon.

**Variant C — Deadpan/anti-launch (best if A feels earnest for the maker’s voice):**

> I got tired of editing my thoughts before I’d finished thinking them.
>
> Buddadawg — hold fn, ramble, let go, get the tidy version pasted wherever your cursor is. Local, free, slightly butter-themed.
>
> The video is one real dictation. Ums included, then removed by the app, not by me.

**First-reply thread (post immediately, in order):**

1. Install link + one-liner (`./scripts/install.sh`, ~640MB models, Mic + Accessibility) + macOS 15+/Apple Silicon floor.
2. Proof drop: uncut take (or link) + verbatim vs Clean outputs + bench log summary + ramp disclosure (§6). This reply is the Wispr vaccine — make auditing easy.
3. How it works in 3 bullets (hold/double-tap-lock; media auto-pause — tested sources listed; clipboard-stays + Recents + dictionary).
4. Credits/licences: Bark 3.0 / Clean by Conway Research via FluidAudio, derived from NVIDIA Parakeet; verbatim fallback note (`defaults write … engine bark`).
5. Ask: “What app should I test pasting into next?” (genuine bug-hunt prompt; reply to every answer in hour one).

**Timing/velocity notes (from §1 sources, treat as directional):** first hour matters most; have 3–5 genuine peers ready to try it and reply with their own dictated quote-posts (no engagement pods, no paid undisclosed posts). Maker stays in replies for 2 hours, dictating replies with Buddadawg where practical and saying so. Doomers’ small-account winners skew founder-posted — do not delegate the hero post to a brand handle.

## 9. Alt text & accessibility plan

- **Video alt text / post-level description** (X video alt where supported; otherwise first reply carries it verbatim):
  > “Screen and desk video: a finger holds the fn key on a MacBook while the maker dictates a paragraph about thinking out loud. A soft glow along the bottom of the screen rises with their voice and playing music pauses. On release, a cleaned paragraph pastes into a document, then the same text pastes with Command-V into Mail and a code editor. The menu-bar Recents list and a double-tap hands-free dictation are shown. Ends: ‘Buddadawg — Hold fn. Think out loud. Free, open source, macOS.’ Full transcript in thread.”
- **Full transcript** in thread (dictated words + `[music pauses/resumes]` + on-screen labels listed separately). Transcript text = archived Clean output for pasted text; spoken false starts noted as `[false start removed by Clean]`.
- **Captions:** burned-in + SRT per §5; check contrast (white on 70% black chip minimum), no caption smaller than ~4.5% of frame height in 16:9.
- **Photosensitivity/motion:** glow is soft and slow (no strobe); whip-pan is 6 frames — keep it, but ensure no flashing cuts >3/sec in Shot 8 (three pastes in 4s is safe; do not add flash frames). Vertical cut: same check.
- **Colour:** never encode meaning by glow colour alone; captions + labels carry all information. End-card text also in post copy.
- **Loop:** muted by design; `autoplay` embeds must respect `prefers-reduced-motion` (serve poster instead where the site supports it).

## 10. Risks & what would change this spec

- If Clean’s real output on the script is weak (butchers “fn,” keeps every “um”), the concept still holds but the script must be rewritten around *actual* strengths, or the dictionary beat becomes a featured shot. Do not shoot until a rehearsal take produces a payoff frame worth holding for 1.5s.
- If `MediaPauser` fails on the maker’s real music source, Shot 2/7’s pause/resume must be cut or re-sourced — never simulated. The film survives without it (drop the claim, keep the glow/clipboard story).
- If the maker will not appear on camera, fallback is hands + screen only (Shots 1, 3–11 without face). Acceptable, but §1 evidence says face-in-opening helps; compensate by keeping the voice unmistakably human and posting from the personal account with a face avatar.
- The 40s hero is a bet against the length data. If the proof cut outperforms in early replies/bookmarks, promote it (pin/quote) rather than defending the hero. Measure: completion, bookmarks, profile→repo clicks, installs — not views alone.

## Sources (inspected 12 Nov 2026)

- Doomers AI. *Best Product Launch Videos of 2026, Ranked by Views.* https://doomers.ai/guides/product-launch-videos (1,550 videos, 7 Jan–19 Oct 2026).
- Doomers AI. *Every AI Launch Video Looks the Same Now.* https://doomers.ai/guides/launch-video-templates
- LaunchVideo.com / Atomik Growth. *Startup Launch Video Strategy for X: 2026 Guide.* https://www.launchvideo.com/blog/x-launch-video-strategy-guide-for-2026-specs-to-strategy (agency guidance; multiples unverified).
- PiunikaWeb (Cubbins). *“Give her the Porsche”: Wispr Flow viral AI challenge video.* 25 Feb 2026. https://piunikaweb.com/2026/02/25/give-her-the-porsche-wispr-flow/ (quotes X post 2025981424470479008, 23 Feb 2026).
- Buddadawg repo on disk: `README.md`, `Package.swift`, `Sources/Buddadawg/{main,Hotkey,MediaPauser,Overlay}.swift`.
- Snippet-only (verify before citing publicly): Atomik Growth X-vs-Product-Hunt directory summary (Wispr Flow 19.7M, 5 Aug 2026); Cursor Origin corroboration via cursor-origin.dev / What Ships index.

## Appendix A — The Butterdog Test cold open (added 12 Nov 2026, owner-approved)

Creative lockup: **Buddadawg presents The Butterdog Test.** The product keeps the phonetic spelling (how the chant sounds); the test uses the canonical one-word meme spelling people search for.

Cold open (replaces a generic first shot; keep total hero runtime by trimming the weakest middle beat):

1. Recreated butter-dog shot, our own dog/footage and our own recorded chant. Do **not** use the original iFunny footage, later derivative audio, a soundboard rip, or the Tenor GIF in the film or shipped brand assets.
2. Live Buddadawg captions confidently fail over the chant.
3. Cut to title: **"We named a dictation app after the one phrase dictation can't transcribe."**
4. Smash into the real human dictation film; ordinary speech lands cleanly.

Measured failure evidence (soundboard analysis clip only, 11.2 s; never a film asset):

- Clean: "Butter. The dog with the butter. But a dog. I'll put the butter on him."
- Bark verbatim: "the dog with the **bug** dog with the **bird dog**"
- Bark Plus: "the dog with the **buttog**"
- Owner singing it live through Buddadawg: "Buddy dog dog with the butter on 'em"

Publish **The Butterdog Test** as a reproducible joke benchmark: one watermark-free recreated master recording, fixed normalization, exact-phrase and word-error scoring for every engine, raw outputs shown unedited. It is an honesty artifact, not an accuracy claim for normal speech.



