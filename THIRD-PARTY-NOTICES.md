# Third-Party Notices

Buddadawg's own source code is licensed under the MIT License (see `LICENSE`).
The following third-party components are bundled or linked and remain under
their own licenses:

## FluidAudio

<https://github.com/FluidInference/FluidAudio> — Apache License 2.0.
Swift framework used for on-device ASR (Parakeet/Bark pipeline via Core ML).

## Underdog Bark 3.0 / Bark 3.0 Clean model weights

Conway Research, distributed via FluidInference.
See `NOTICE` (verbatim fallback models) and `ModelsClean/NOTICE` (default
Clean models) for the full attribution. The bundled notices state
CC-BY-4.0, derived from:

- `nvidia/parakeet-tdt-0.6b-v3` — NVIDIA Corporation, CC-BY-4.0
- `moondream/parakeet-ultra` — Moondream, CC-BY-4.0

Note: the upstream Hugging Face model cards have displayed conflicting
license tags (CC-BY-NC-4.0 vs CC-BY-4.0). The bundled NOTICE files assert
CC-BY-4.0; treat the stricter reading (non-commercial) as authoritative
until Conway Research clarifies — see `docs/oss-release-plan.md` §1.1.

## Apple frameworks

AppKit, AVFoundation, Core ML, Core Audio HAL, MediaRemote (private SPI,
accessed dynamically), and Foundation Models are Apple system frameworks
used under the macOS SDK license.

## ffmpeg / misc

Not bundled. Build-time only.

---

If you redistribute Buddadawg, keep this file, `LICENSE`, `NOTICE`, and
`ModelsClean/NOTICE` together with the app.
