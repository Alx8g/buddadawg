# Buddadawg 🧈🐶

<p align="center"><img src="https://media.tenor.com/Esbsny0YGXoAAAAM/butta-dawg-dog-with-the-butta.gif" alt="The dog with the butter on him" width="260"></p>

Hold **fn**, talk, let go. It types what you said, on-device, in any app.

- [Bark 3.0](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0) on the Neural Engine
- ~150 MB RAM, ~100–350 ms per dictation
- Native Swift, no Python, no network

## Install

macOS 15+, Apple Silicon, Command Line Tools.

```sh
./scripts/install.sh
```

The first run compiles the model (~5 min). Allow Mic and Accessibility when asked.

## Use

- Hold **fn** to talk. fn + another key cancels.
- Fix words via the menu bar → **Edit Dictionary…** (`tail scale => Tailscale`).

Model: Bark 3.0 by Conway Research, CC-BY-4.0.
