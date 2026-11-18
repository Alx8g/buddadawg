# Buddadawg visual language

> **Owner decision, 12 Nov 2026:** the butter-tinted glow described below was rejected after
> on-screen review. The shipping overlay is the original grayscale Grain Horizon. The palette
> remains available for the icon, film and other brand surfaces, but must not be reapplied to
> the live overlay without an explicit new decision.

The whole product surface is three things: the Grain Horizon glow along the bottom screen edge
(`Sources/Buddadawg/Overlay.swift`), a menu-bar item with a menu, and the app icon. This document
is the contract for how they look and move. Numbers below are read from the code, not aspirations;
proposals are labelled as proposals.

## Principle

Warm, quiet, peripheral. The glow is felt at the edge of vision while you talk; it never asks to be
looked at. Butter is the one brand colour: amber where the light is strongest, cream where it fades.
No red recording clichés, no rainbow voice bars, no text in the overlay ever.

## Palette

Shader constants are sRGB hex ÷ 255 written straight to the `bgra8Unorm` drawable (no
linearisation), the same convention the old grayscale path used. They live in `fmain` in
`Overlay.swift` as `creamEdge`, `butterMid`, `amberCore`.

| Name | Hex | Shader float3 | Role |
|---|---|---|---|
| Amber Core | `#FF9E2C` | `(1.00, .620, .173)` | Hottest part of the glow: bottom edge, peak crests |
| Butter | `#FFC94D` | `(1.00, .788, .302)` | Mid glow; the pasted flash leans here |
| Cream Edge | `#FFF1CF` | `(1.00, .945, .812)` | Faint edge of the glow; transcribing leans here |
| Warm Gray (derived) | ≈`#BEA88C` at test levels | `luma × (1.0, .98, .94)` | Cancelled only; computed per-pixel, not a constant |
| Icon Ink | `#222222` | — | Icon background (sampled from `Brand/icon-concept.png`, dominant pixel) |
| Pat Cream | `#FFEEA9` | — | Butter pat in the icon concept (sampled) |
| Coat range | `#DF9838`–`#F6CB83` | — | Dog gradient in the icon concept (sampled) |

How the tint is built (in `fmain`, after the grayscale intensity `G` is fully computed — colour
never feeds back into motion):

- `heat = clamp(G * 1.1, 0, 1)`.
- Cream Edge → Butter across `smoothstep(0, .55, heat)`, then → Amber Core across
  `smoothstep(.5, 1, heat)`. Because `G` itself falls off with height, the core-to-edge gradient
  follows the glow's shape for free.
- Output is premultiplied: `alpha = G * .85` (same coverage as the grayscale glow had) and
  `return float4(tint * alpha, alpha)`. `tint` is clamped to ≤ 1 per channel, so `rgb ≤ alpha`
  always — no bright fringing when the window server composites the transparent panel. The price:
  at equal `G` the tinted glow reads slightly deeper and less blown-out than the old white; that is
  intended. Verified offscreen: 0 premultiply violations in 800×240 frames for listening,
  cancelled, and reduced-motion renders; brightest unpremultiplied pixel measured
  `(255, 157, 43)` ≈ Amber Core.

## State colour semantics

State weights arrive as the `s` uniform (`u.s.x/y/z/w` = listening, transcribing, pasted,
cancelled), blended on the CPU at rate 26/s, so every colour change below crossfades smoothly
with the shape change. Colour reinforces the shape; it is never the only signal.

| State | Shape (existing) | Colour treatment | Meaning |
|---|---|---|---|
| Listening (`lG`) | Bottom glow + 7 voice peaks climbing from the edge | Full gradient: Amber Core at crests to Cream Edge at the fade | "I hear you" — warm and alive |
| Transcribing (`wG`) | Pinches to a narrow centre column over 0.22 s | Mixed 45% toward Cream Edge (`u.s.y`) — paler, quieter | "Thinking" — held breath, not a spinner |
| Pasted (`dG`) | Flash line rises over 0.3 s, gone by 0.6 s | Mixed 30% toward Butter `#FFC94D` (`u.s.z`) — fullest butter | "Done" — the one moment of full saturation |
| Cancelled (`cG`) | Listening shape sinks over 0.18 s | Desaturated 80% toward warm gray `luma × (1, .98, .94)` and dimmed 12% (`u.s.w`) | "Never mind" — calm, no error red, no alarm |

Measured (offscreen 800×240, level/swell 0.8): mean saturation where alpha > 60 is 0.717
listening vs 0.227 cancelled; brightest alpha 217 listening vs 191 cancelled.

## Motion principles (exact, from the shader and `draw(in:)`)

One easing everywhere: `ease(x) = x*x*(3-2*x)` on clamped `x` (smoothstep), plus exponential
approach `1 - exp(-rate * dt)` for continuous signals. No springs, no overshoot, no linear fades.

Geometry and budget: panel is full screen width × `Overlay.height` = 240 pt
(`placeOnScreen`), rendered at half resolution (`backingScaleFactor * 0.5`, floor 0.5),
`preferredFramesPerSecond = 120`, and only while visible — at `visibility < 0.002` the view
pauses and the panel orders out. Frame `dt` is clamped to 0.05 s. If Metal setup fails the
overlay simply stays dark and dictation continues; that fallback is part of the language
(silence, never an error look).

Signals (CPU, `draw(in:)`):

- Voice level `smoothed`: rise rate 20/s (τ ≈ 50 ms), fall 6/s (τ ≈ 167 ms) — quick to answer,
  slow to leave.
- Peak swell `swell`: rise 7/s (τ ≈ 143 ms), fall 3.5/s (τ ≈ 286 ms), so peaks heave instead of
  flickering.
- Whole-glow `visibility`: in at 18/s (τ ≈ 56 ms); out at 9/s after pasted, 14/s otherwise.
- Brief states end themselves: pasted → hidden at `sinceState > 0.62 s`, cancelled → hidden at
  `> 0.20 s`.

Voice-warped phases (`BarkCore.PhaseClock`, untouched by the colour work): phases are integrated,
never `sin(elapsed * (1 + k*level))`. `shaftTime += dt * (1 + 1.5*level)`,
`bumpTime += dt * (0.7 + 0.8*swell)`, `time += dt`; all re-based mod 600 once past 7200 s, only
while faded out.

In the shader:

- Light shafts (`shafts`): 4 bands along `a = x*.94 − y*.34` (band long axis ≈ 20° off vertical,
  leaning right as they rise). Centres −520/−150/230/560 pt, widths 110/150/120/90 pt, powers
  .30/.85/.42/.20. Each sways ±70/110/90/60 pt at .13/.071/.097/.053 rad/s of warped shaft time
  (periods ≈ 48/88/65/119 s at warp 1) with unrelated phases 0/2.1/4.3/1.2, so the pattern never
  visibly repeats. Loudness widens bands by up to 25%.
- Peaks (`bumps`): 7 Gaussians, 105 pt apart, widths 30–56 pt, wandering ±35 pt on raw time at
  .31–.73 rad/s, bouncing on warped bump time at .55–1.93 rad/s (periods ≈ 11.4 s for the leftmost
  peak down to 3.3 s for the rightmost), squared bounce, damped away from centre by `exp(-xn²*4)`. Peak height scale is
  `4 + 200*swell*bumps` pt with a soft top (`exp(-q²*1.6) * (.6 + .4*exp(-q))`, `q = y/top`) — the
  light climbs rather than the whole glow brightening.
- Transcribing pinch completes at `ph = 0.22 s`; pasted rises by `ph/.3` and is gone by `ph/.6`;
  cancelled sinks by `ph/.18` (`ph` is `sinceState`).
- The glow always fades to zero inside the panel: `1 − smoothstep(0.4*R.y, 0.92*R.y, y)`, i.e.
  between 96 pt and 221 pt of the 240 pt panel. There is never a visible panel edge.
- Film grain: `h21` hash re-stepped at `floor(t*24)` (24 steps/s — on a 120 Hz display each grain
  frame holds 5 frames, like film). Amplitude factor `.85 + .3*h` (mean 1.0).

Reduced Motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, honoured via
`Overlay.reduceMotion`, refreshed on `accessibilityDisplayOptionsDidChangeNotification` and on
every `show(_:)`):

- Phase advance is damped to 15% (`Overlay.reducedPhaseScale`): shafts, peak bounce, wander, and
  grain stepping all crawl; the voice-warp ratios inside `PhaseClock` are unchanged.
- Grain amplitude drops .3 → .04 in the shader (`Uniforms.reduce` → `grainAmp`). Measured mean
  per-channel change between frames 1/24 s apart: 1.827 normally, 0.249 reduced (≈7× stiller).
- State timings, level response, and fades stay real-time: feedback about listening / pasted /
  cancelled is information, not decoration, so it is not slowed or removed.

## Typography

Current product: no custom fonts, anywhere. The menu is a plain `NSMenu` (system font, SF Pro Text
at menu size), the status line and "Recent Dictations" entries are `NSMenuItem` titles (recents
truncated at 64 characters + "…" in `rebuildRecents`), and dictated text lands in the user's app
in that app's own type. Keep it that way: the app has no windows, so it needs no type system.

Proposal (marketing, launch film supers, future settings window — not in the app today):

- Headlines: SF Pro Rounded Semibold — the rounded terminals carry the "butter" softness without a
  novelty face. Body: SF Pro Text. Specs/timings: SF Mono.
- Menu strings stay Title Case as shipped ("Recent Dictations", "Launch at Login",
  "Pause Media While Dictating", "Quit Buddadawg"). The product name is one word, "Buddadawg",
  capital B; never set it in a meme or display font, never letter-spaced all-caps.

## Menu-bar icon states (proposal — not implemented; `main.swift` is outside this lane)

Today there is exactly one glyph: `NSImage(systemSymbolName: "waveform")` in `buildMenu`,
template-rendered. Proposal: swap the SF Symbol on the same `overlay.show(...)` call sites, stay
template-rendered so the menu bar controls the colour (colour lives in the glow, not the menu
bar), and update `accessibilityDescription` with the state.

| State | Symbol | Accessibility description | Notes |
|---|---|---|---|
| Idle / ready | `waveform` (current) | "Buddadawg" | Unchanged |
| Listening | `mic.fill` | "Buddadawg, listening" | On `.listening` |
| Transcribing | `ellipsis` | "Buddadawg, transcribing" | Brief; no spinner animation |
| Pasted | `checkmark` | "Buddadawg, pasted" | Only for the same 0.62 s the glow flashes, then back to idle |
| Cancelled | back to `waveform` at once | "Buddadawg" | No ✕, no dwelling on failure — matches the calm gray sink |

If colour is ever added here, the only permitted accent is Butter `#FFC94D` on the listening
glyph — never system red.

## Overlay do / don't

Do:

- Keep colour downstream of intensity: compute grayscale `G` (motion, shape, grain, top fade)
  first, tint last. Any future palette change must be provably motion-neutral.
- Keep output premultiplied (`tint ≤ 1`, `rgb = tint * alpha`) and keep `alpha = G * .85` as the
  single coverage knob.
- Keep the glow's zero line inside the panel (top fade by 221 pt of 240 pt) and half-res
  rendering — softness is the look and the perf budget.
- Keep every state readable with colour removed (shape + timing), and keep Reduced Motion
  behaviour when touching grain or phases.
- Fail dark: any Metal/pipeline failure leaves no visual trace.

Don't:

- No text, icons, waveform bars, or level meter in the overlay; no hard edges or 1 px lines.
- No hue outside the cream→amber ramp (no green "success", no red "recording", no blue
  "thinking"). Cancelled desaturates; it never recolours.
- No new easing curves, springs, or overshoot; no `sin(elapsed * f(level))` phase hacks —
  integrate phases in `PhaseClock` or not at all.
- No full-res rendering, sharpening, or saturation boosts "for Retina"; no raising the .85 alpha
  cap to make it pop.
- No copying the butter-dog meme artwork anywhere (icon, film, site). The silhouette in
  `Brand/icon-concept.png` is an original direction: minimal butter-yellow dog head in profile,
  one floppy ear, a melting butter pat on top, dark `#222222` rounded square, no text. Before
  shipping it needs a vector redraw on the palette above (sampled raster tones normalised to
  Amber Core / Butter / Cream Edge), Apple's icon grid and safe margins, and a full iconset
  export — the PNG is a concept, not an asset.

## Launch film: lighting and reproducing the glow

Shoot (capture) the real thing wherever possible: run the app's `--demo` loop (`runDemo` in
`main.swift` cycles listen → transcribe → paste → listen → cancel with a speech-like fake level)
and screen-capture at the display's native rate. The glow is half-res by design; do not upscale,
sharpen, or denoise it — the softness is the product.

If the glow must be recreated or comped (device footage, set extension):

- Light the set to match before comping: a warm practical low in frame, raking up from below the
  screen edge. Dial LED/gel to the palette, not a Kelvin guess — core `RGB(255,158,44)`
  (#FF9E2C) at the edge, falling to `RGB(255,241,207)` (#FFF1CF) at the top of the light. Flag it
  so nothing reaches above ~90% of the glow's height in frame, and tilt any visible shafts ~20°
  off vertical, leaning right as they rise.
- Rebuild the gradient as intensity first, colour second, exactly like the shader: a grayscale
  glow (exponential falloff from the bottom edge, soft peaks, zero before the frame top), then
  map luminance → Cream Edge (0) → Butter (0.55) → Amber Core (1.0). Max alpha 0.85: the
  background always shows through 15%, so never let the comp clip to solid amber.
- Treat the glow as premultiplied throughout the pipeline (e.g. ProRes 4444 with premultiplied
  alpha, comped straight over). Unpremultiplying twice gives dark fringes; forgetting once gives
  milky edges — check against a real capture over both dark and light wallpapers.
- Grain: 24 steps/s (in a 24 fps film it re-steps every frame; do not interpolate it), roughly
  ±15% multiplicative. Fine, monochrome, in the glow only — not over the whole frame.
- Timing beats for the edit: glow answers voice within ~50 ms, peaks heave on a ~0.3 s fall,
  transcribing pinches in 0.22 s, the pasted flash lives 0.6 s (cut on it), a cancel sinks in
  0.18 s (let it play; it reads as a shrug, not an error).
- Wallpaper/set dressing behind the glow: dark and quiet. Cream Edge disappears against light,
  busy backgrounds; that is true in the product too, so don't "fix" it in the film.

## What changed for this document

In `Sources/Buddadawg/Overlay.swift` only: added `Overlay.reducedPhaseScale` and
`Overlay.reduceMotion` (plus its `NSWorkspace` change observer in `init` and refresh in
`show(_:)`), added the `reduce` field to `Uniforms` and shader struct `U`, damped the
`phases.advance(...)` call in `draw(in:)`, and in shader `fmain` replaced the grayscale return
with the `grainAmp` grain factor, the `creamEdge`/`butterMid`/`amberCore` tint ramp, per-state
tint mixes, and the premultiplied `float4(tint * alpha, alpha)` return. `BarkCore.PhaseClock`,
half-res rendering, panel/fallback behaviour, and every motion constant above are unchanged.
New files: this document and `Brand/icon-concept.png` (generated raster concept, cropped to the
icon's bounding box; needs the vector redraw described above).
