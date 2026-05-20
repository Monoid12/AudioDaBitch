#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}" 
APP="$ROOT/build/AudioDaBitch.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Build Swift app
swiftc -O -framework Cocoa -o "$MACOS/AudioDaBitch" "$ROOT/Sources/AudioDaBitch/main.swift"
chmod +x "$MACOS/AudioDaBitch"

# Resources
cp "$ROOT/Resources/engine.py" "$RES/engine.py"
chmod +x "$RES/engine.py"
cp "$ROOT/Resources/HELP_BLACKHOLE_DE.md" "$RES/HELP_BLACKHOLE_DE.md"
cp "$ROOT/Resources/CHANGELOG.md" "$RES/CHANGELOG.md"
cp "$ROOT/Resources/README_IN_APP.txt" "$RES/README_IN_APP.txt"

# Icon
if [ -d "$ROOT/Resources/AudioDaBitch.iconset" ] && command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ROOT/Resources/AudioDaBitch.iconset" -o "$RES/AudioDaBitch.icns" || true
fi
if [ -f "$ROOT/Resources/AudioDaBitch.icns" ] && [ ! -f "$RES/AudioDaBitch.icns" ]; then
  cp "$ROOT/Resources/AudioDaBitch.icns" "$RES/AudioDaBitch.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>AudioDaBitch</string>
  <key>CFBundleDisplayName</key><string>AudioDaBitch</string>
  <key>CFBundleIdentifier</key><string>com.micheldamhorst.audiodabitch</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>AudioDaBitch</string>
  <key>CFBundleIconFile</key><string>AudioDaBitch</string>
  <key>NSMicrophoneUsageDescription</key><string>AudioDaBitch needs access to audio inputs so it can process BlackHole and virtual audio devices.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ ! -f "$RES/AudioDaBitch.icns" ]; then
  echo "WARNUNG: AudioDaBitch.icns fehlt. Icon wird eventuell nicht angezeigt."
fi

echo "Built $APP"
