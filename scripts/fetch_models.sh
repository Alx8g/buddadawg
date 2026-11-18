#!/bin/sh
# Download the speech models from Hugging Face (too large for git):
# - Models/      Bark 3.0 verbatim (Conway Research) Core ML ANE package + decoder, packed for BarkCore.
# - ModelsClean/ Bark 3.0 Clean (Conway Research) as FluidAudio-layout Core ML models
#                (FluidInference/bark-3.0-coreml, ANE encoder; the GPU lut3 variant is skipped).
set -eu
cd "$(dirname "$0")/.."
BASE=https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/resolve/main
CLEAN=https://huggingface.co/FluidInference/bark-3.0-coreml/resolve/main/bark-3.0-clean
PKG=Models/BarkEncoderANE.mlpackage

if [ -f Models/decoder.bin ] && [ -f "$PKG/Data/com.apple.CoreML/weights/weight.bin" ] \
   && [ -f ModelsClean/Encoder.mlmodelc/weights/weight.bin ]; then
  echo "Models already present."; exit 0
fi

if [ ! -f "$PKG/Data/com.apple.CoreML/weights/weight.bin" ]; then
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
fi

if [ ! -f ModelsClean/Encoder.mlmodelc/weights/weight.bin ]; then
  for comp in Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecisionv3.mlmodelc; do
    mkdir -p "ModelsClean/$comp/analytics" "ModelsClean/$comp/weights"
    for f in analytics/coremldata.bin coremldata.bin model.mil weights/weight.bin; do
      curl -fL --progress-bar -o "ModelsClean/$comp/$f" "$CLEAN/$comp/$f"
    done
    [ "$comp" = Encoder.mlmodelc ] || curl -fsSL -o "ModelsClean/$comp/metadata.json" "$CLEAN/$comp/metadata.json"  # Encoder ships no metadata.json
  done
  curl -fsSL -o ModelsClean/parakeet_vocab.json "$CLEAN/parakeet_vocab.json"
  curl -fsSL -o ModelsClean/NOTICE "$CLEAN/NOTICE"
fi
