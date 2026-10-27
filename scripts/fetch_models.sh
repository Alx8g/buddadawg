#!/bin/sh
# Download Bark 3.0 (Conway Research, CC-BY-4.0) from Hugging Face into Models/ and pack the decoder for Swift.
# The model is ~200 MB, too large for git, so it lives on Hugging Face instead of in this repo.
set -eu
cd "$(dirname "$0")/.."
BASE=https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/resolve/main
PKG=Models/BarkEncoderANE.mlpackage

if [ -f Models/decoder.bin ] && [ -f "$PKG/Data/com.apple.CoreML/weights/weight.bin" ]; then
  echo "Models already present."; exit 0
fi
mkdir -p "$PKG/Data/com.apple.CoreML/weights"
for f in Manifest.json Data/com.apple.CoreML/model.mlmodel Data/com.apple.CoreML/weights/weight.bin; do
  curl -fL --progress-bar -o "$PKG/$f" "$BASE/coreml/ane/BarkEncoder.mlpackage/$f"
done
curl -fsSL -o Models/vocab.json "$BASE/coreml/ane/vocab.json"
curl -fsSL -o NOTICE "$BASE/NOTICE"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/decoder.npz" "$BASE/coreml/ane/decoder.npz"
# numpy is only needed for this one-off conversion; uv runs it without touching your Python installs.
if command -v uv >/dev/null; then uv run -q --with numpy python3 scripts/convert_decoder.py "$TMP/decoder.npz" Models
else python3 -c "import numpy" && python3 scripts/convert_decoder.py "$TMP/decoder.npz" Models; fi
rm -rf "$TMP"
