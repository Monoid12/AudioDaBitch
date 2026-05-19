#!/bin/bash
set -euo pipefail
export COPYFILE_DISABLE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}" 
"$ROOT/scripts/build_app.sh"
PKGROOT="$ROOT/build/pkgroot"
rm -rf "$PKGROOT" "$ROOT/dist"
mkdir -p "$PKGROOT/Applications" "$ROOT/dist"
cp -R "$ROOT/build/AudioDaBitch.app" "$PKGROOT/Applications/AudioDaBitch.app"
/usr/bin/xattr -cr "$PKGROOT/Applications/AudioDaBitch.app" 2>/dev/null || true
PKG="$ROOT/dist/AudioDaBitch.pkg"
COMPONENT_PLIST="$ROOT/build/components.plist"
pkgbuild --analyze --root "$PKGROOT" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$COMPONENT_PLIST"
if [ "$(/usr/libexec/PlistBuddy -c "Print :0:BundleIsRelocatable" "$COMPONENT_PLIST")" != "false" ]; then
  echo "FEHLER: PKG-Komponente ist noch relocatable." >&2
  exit 1
fi
pkgbuild --root "$PKGROOT" --install-location / --identifier com.micheldamhorst.audiodabitch --version "$VERSION" --scripts "$ROOT/PackageScripts" --component-plist "$COMPONENT_PLIST" "$PKG"
PAYLOAD="$(pkgutil --payload-files "$PKG")"
if ! printf "%s\n" "$PAYLOAD" | grep -Eq '^(\./)?Applications/AudioDaBitch.app/Contents/MacOS/AudioDaBitch$'; then
  echo "FEHLER: PKG enthält keine Applications/AudioDaBitch.app." >&2
  exit 1
fi
if ! printf "%s\n" "$PAYLOAD" | grep -Eq '^(\./)?Applications/AudioDaBitch.app/Contents/Resources/engine.py$'; then
  echo "FEHLER: PKG enthält keine Resources/engine.py." >&2
  exit 1
fi
(cd "$ROOT/build" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent AudioDaBitch.app "$ROOT/dist/AudioDaBitch.app.zip")
(cd "$ROOT/dist" && shasum -a 256 AudioDaBitch.pkg > SHA256SUMS.txt)
echo "Built dist/AudioDaBitch.pkg"
