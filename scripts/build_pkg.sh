#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.5.0}"
APP_PATH="$($ROOT/scripts/build_app.sh)"
DIST="$ROOT/dist"
PKGROOT="$ROOT/build/pkgroot"
rm -rf "$DIST" "$PKGROOT"
mkdir -p "$DIST" "$PKGROOT/Applications"
cp -R "$APP_PATH" "$PKGROOT/Applications/"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build_pkg.sh muss auf macOS laufen." >&2
  exit 2
fi
pkgbuild --root "$PKGROOT" --scripts "$ROOT/PackageScripts" --install-location "/" --identifier "com.micheldamhorst.audiodabitch.pkg" --version "$VERSION" "$DIST/AudioDaBitch.pkg"
( cd "$(dirname "$APP_PATH")" && ditto -c -k --sequesterRsrc --keepParent "AudioDaBitch.app" "$DIST/AudioDaBitch.zip" )
if [ -d "$ROOT/streamdeck/com.micheldamhorst.audiodabitch.sdPlugin" ]; then
  ( cd "$ROOT/streamdeck" && zip -qr "$DIST/AudioDaBitch.streamDeckPlugin" "com.micheldamhorst.audiodabitch.sdPlugin" )
fi
( cd "$DIST" && shasum -a 256 * > SHA256SUMS.txt )
echo "$DIST"
