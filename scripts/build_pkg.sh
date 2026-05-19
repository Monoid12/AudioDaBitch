#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}" 
APP_PATH="$($ROOT/scripts/build_app.sh)"
PKGROOT="$ROOT/build/pkgroot"
SCRIPTS="$ROOT/PackageScripts"
mkdir -p "$PKGROOT/Applications" "$SCRIPTS" "$ROOT/dist"
rm -rf "$PKGROOT/Applications/AudioDaBitch.app"
cp -R "$APP_PATH" "$PKGROOT/Applications/AudioDaBitch.app"
if [ ! -f "$SCRIPTS/preinstall" ]; then
cat > "$SCRIPTS/preinstall" <<'SH'
#!/bin/bash
/usr/bin/pkill -f '/AudioDaBitch.app/.*/engine.py' 2>/dev/null || true
/usr/bin/pkill -f 'Resources/engine.py' 2>/dev/null || true
exit 0
SH
chmod +x "$SCRIPTS/preinstall"
fi
if [ ! -f "$SCRIPTS/postinstall" ]; then
cat > "$SCRIPTS/postinstall" <<'SH'
#!/bin/bash
/usr/bin/open -a AudioDaBitch 2>/dev/null || true
exit 0
SH
chmod +x "$SCRIPTS/postinstall"
fi
/usr/bin/pkgbuild --root "$PKGROOT" --scripts "$SCRIPTS" --identifier com.micheldamhorst.audiodabitch --version "$VERSION" --install-location / "$ROOT/dist/AudioDaBitch.pkg"
(cd "$ROOT/dist" && /usr/bin/zip -qry AudioDaBitch.app.zip ../build/AudioDaBitch.app)
(cd "$ROOT/dist" && /usr/bin/shasum -a 256 AudioDaBitch.pkg AudioDaBitch.app.zip > SHA256SUMS.txt)
