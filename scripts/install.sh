#!/bin/sh
# Fetch the model, build, install to /Applications, and pre-compile the model so the first dictation isn't a ~5 minute wait.
set -eu
cd "$(dirname "$0")/.."
APP="/Applications/Buddadawg.app"

./scripts/fetch_models.sh
./scripts/bundle.sh
pkill -x Buddadawg 2>/dev/null || true
rm -rf "$APP"
cp -R "build/Buddadawg.app" "$APP"

echo "Pre-compiling the model for the Neural Engine (only slow the first time)…"
"$APP/Contents/MacOS/Buddadawg" --precompile
open "$APP"
