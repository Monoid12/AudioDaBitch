#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}" 
"$ROOT/scripts/build_app.sh"
PKGROOT="$ROOT/build/pkgroot"
rm -rf "$PKGROOT" "$ROOT/dist"
mkdir -p "$PKGROOT/Applications" "$ROOT/dist"
cp -R "$ROOT/build/AudioDaBitch.app" "$PKGROOT/Applications/AudioDaBitch.app"
pkgbuild --root "$PKGROOT" --install-location / --identifier com.micheldamhorst.audiodabitch --version "$VERSION" --scripts "$ROOT/PackageScripts" "$ROOT/dist/AudioDaBitch.pkg"
(cd "$ROOT/dist" && shasum -a 256 AudioDaBitch.pkg > SHA256SUMS.txt)
echo "Built dist/AudioDaBitch.pkg"
