#!/usr/bin/env bash
set -euo pipefail
VERSION="${VERSION:-$(cat VERSION)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/AudioDaBitch.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/swiftc "$ROOT/Sources/AudioDaBitch/main.swift" -o "$APP/Contents/MacOS/AudioDaBitch" -framework Cocoa
cp -R "$ROOT/Resources/"* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>AudioDaBitch</string>
  <key>CFBundleDisplayName</key><string>AudioDaBitch</string>
  <key>CFBundleIdentifier</key><string>com.micheldamhorst.audiodabitch</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>AudioDaBitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSMicrophoneUsageDescription</key><string>AudioDaBitch benötigt Zugriff auf virtuelle Audio-Inputs wie BlackHole.</string>
</dict></plist>
PLIST
printf "%s\n" "$APP"
