#!/bin/sh
# Build Buddadawg.app: release binary + Neural Engine model, signed with a stable local identity so macOS keeps
# its Microphone and Accessibility permissions across rebuilds (ad-hoc signatures change every build and reset them).
set -eu
cd "$(dirname "$0")/.."
APP="build/Buddadawg.app"
IDENTITY="Buddadawg Local Signing"

swift build -c release --product Buddadawg

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Models"
cp .build/release/Buddadawg "$APP/Contents/MacOS/Buddadawg"
cp -R Models/BarkEncoderANE.mlpackage Models/decoder.bin Models/decoder.json Models/vocab.json "$APP/Contents/Resources/Models/"
cp NOTICE "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>co.alex.buddadawg</string>
  <key>CFBundleName</key><string>Buddadawg</string>
  <key>CFBundleExecutable</key><string>Buddadawg</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Buddadawg listens only while you hold fn, and transcribes on this Mac.</string>
</dict></plist>
PLIST

if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then  # self-signed, so find-identity -v (trusted only) never lists it
  TMP=$(mktemp -d)
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:bark 2>/dev/null \
    || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:bark
  security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P bark -T /usr/bin/codesign
  rm -rf "$TMP"
fi
# Pin the designated requirement to the bundle id + our certificate. Without this a self-signed identity falls back to a
# cdhash requirement, every rebuild looks like a new app, and macOS drops the Accessibility grant.
CERT=$(security find-certificate -c "$IDENTITY" -Z | awk '/SHA-1 hash/{print $3}')
codesign --force --deep --sign "$CERT" -r="designated => identifier \"co.alex.buddadawg\" and certificate leaf = H\"$CERT\"" "$APP"
du -sh "$APP"
