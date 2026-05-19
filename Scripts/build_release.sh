#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '\n' < "$ROOT/VERSION")"
APP_NAME="AudioDaBitch"
BUNDLE_ID="com.micheldamhorst.audiodabitch"
DIST="$ROOT/dist"
BUILD_DIR="$ROOT/.build-release"
APP="$DIST/$APP_NAME.app"
rm -rf "$DIST" "$BUILD_DIR"
mkdir -p "$DIST" "$BUILD_DIR"
cd "$ROOT"
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift/Xcode command line tools not found. Install Xcode." >&2
  exit 1
fi
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Built binary not found: $BIN_PATH" >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Resources/engine"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/SetupGuide.md" "$APP/Contents/Resources/SetupGuide.md"
cp "$ROOT/CHANGELOG.md" "$APP/Contents/Resources/CHANGELOG.md"
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"; fi
cp "$ROOT/Sources/AudioDaBitchEngine/audiodabitch_engine.py" "$APP/Contents/Resources/engine/"
cp "$ROOT/Sources/AudioDaBitchEngine/bootstrap_engine.sh" "$APP/Contents/Resources/engine/"
cp "$ROOT/Sources/AudioDaBitchEngine/requirements.txt" "$APP/Contents/Resources/engine/"
chmod +x "$APP/Contents/Resources/engine/bootstrap_engine.sh"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSMicrophoneUsageDescription</key><string>AudioDaBitch benötigt Zugriff auf virtuelle Audio-Inputs wie BlackHole, um Discord und xPilot zu verarbeiten.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size*2))
    sips -z "$double" "$double" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
if command -v pkgbuild >/dev/null 2>&1; then
  pkgbuild --install-location /Applications --component "$APP" "$DIST/$APP_NAME.pkg"
else
  echo "pkgbuild not found. .pkg can only be built on macOS with Xcode command line tools." >&2
fi
(cd "$DIST" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
if [[ -d "$ROOT/StreamDeckPlugin/com.micheldamhorst.audiodabitch.sdPlugin" ]]; then
  (cd "$ROOT/StreamDeckPlugin" && ditto -c -k --keepParent "com.micheldamhorst.audiodabitch.sdPlugin" "$DIST/AudioDaBitch.streamDeckPlugin.zip")
fi
cat > "$DIST/RELEASE_NOTES.md" <<NOTES
# AudioDaBitch $VERSION

Siehe CHANGELOG.md für die vollständigen Änderungen.

Highlights:
- Native SwiftUI-App ohne Browser und ohne Terminal beim normalen Start.
- GitHub Update-Check für Monoid12/AudioDaBitch.
- Changelog-Anzeige in der App.
- Log-Verzeichnis und Diagnose-ZIP.
- xPilot Auto-Leveling für stark unterschiedliche VATSIM-Pegel.
- Stream Deck API und Plugin-Scaffold.
NOTES
find "$DIST" -maxdepth 1 -type f ! -name "SHA256SUMS.txt" -print0 | sort -z | xargs -0 shasum -a 256 > "$DIST/SHA256SUMS.txt"
echo "Built release artifacts in $DIST"
