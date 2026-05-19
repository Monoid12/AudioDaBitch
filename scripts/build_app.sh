#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.5.0}"
APP_NAME="AudioDaBitch"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
rm -rf "$BUILD"
mkdir -p "$MACOS" "$RES"
cp "$ROOT/Resources/adbctl.sh" "$RES/"
cp "$ROOT/Resources/engine.py" "$RES/"
cp "$ROOT/Resources/HELP_BLACKHOLE_DE.md" "$RES/"
cp "$ROOT/Resources/CHANGELOG.md" "$RES/"
cp "$ROOT/Resources/AppIcon.png" "$RES/"
chmod +x "$RES/adbctl.sh" "$RES/engine.py"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleExecutable</key><string>AudioDaBitch</string>
  <key>CFBundleIconFile</key><string>AudioDaBitch</string>
  <key>CFBundleIdentifier</key><string>com.micheldamhorst.audiodabitch</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>AudioDaBitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSMicrophoneUsageDescription</key><string>AudioDaBitch verarbeitet virtuelle Audio-Inputs von BlackHole fuer Discord und xPilot.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

ICONSET="$BUILD/AudioDaBitch.iconset"
mkdir -p "$ICONSET"
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_$2.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES/AudioDaBitch.icns"
else
  cp "$ROOT/Resources/AppIcon.png" "$RES/AudioDaBitch.png"
fi

SWIFT_SRC="$ROOT/Sources/AudioDaBitch/main.swift"
BIN_NATIVE="$MACOS/AudioDaBitch"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build_app.sh muss auf macOS laufen, weil Cocoa/AppKit benoetigt wird." >&2
  exit 2
fi

# Try universal2 first; fall back to native runner architecture.
ARM_BIN="$BUILD/AudioDaBitch-arm64"
X64_BIN="$BUILD/AudioDaBitch-x86_64"
if swiftc -O -target arm64-apple-macos12.0 -framework Cocoa -framework Foundation "$SWIFT_SRC" -o "$ARM_BIN" &&    swiftc -O -target x86_64-apple-macos12.0 -framework Cocoa -framework Foundation "$SWIFT_SRC" -o "$X64_BIN" &&    command -v lipo >/dev/null 2>&1; then
  lipo -create "$ARM_BIN" "$X64_BIN" -output "$BIN_NATIVE"
else
  swiftc -O -framework Cocoa -framework Foundation "$SWIFT_SRC" -o "$BIN_NATIVE"
fi
chmod +x "$BIN_NATIVE"
echo "$APP"
