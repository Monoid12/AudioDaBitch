#!/bin/bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
echo "Installiere Developer Tool nach /Applications..."
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$APP_ROOT/Contents/Resources/icon.iconset" -o "$APP_ROOT/Contents/Resources/DevToolIcon.icns" || true
fi
rm -rf "/Applications/AudioDaBitch Developer Tool.app"
cp -R "$APP_ROOT" "/Applications/AudioDaBitch Developer Tool.app"
xattr -dr com.apple.quarantine "/Applications/AudioDaBitch Developer Tool.app" 2>/dev/null || true
echo "Fertig: /Applications/AudioDaBitch Developer Tool.app"
