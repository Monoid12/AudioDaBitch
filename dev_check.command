#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cleanup(){ rm -rf build dist; find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true; find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true; }
check_git_artifacts(){
  local bad
  bad="$({ git ls-files; git diff --cached --name-only; } | sort -u | grep -E '(^|/)(build|dist|__pycache__)(/|$)|(^|/)\.DS_Store$|\.pyc$|\.pkg$|\.zip$|\.tar\.gz$' || true)"
  if [ -n "$bad" ]; then
    echo "FEHLER: Cache-/Build-Artefakte sind im Git-Index oder bereits getrackt:"
    echo "$bad"
    exit 1
  fi
}
cleanup
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
echo "AudioDaBitch Dev Check"
echo "======================"
echo "Version: $APP_VERSION"
echo
echo "Git Status:"; git status --short || true; echo
check_git_artifacts
if find . -path "*/audiodabitch_engine.py" -not -path "./.git/*" | grep -q .; then echo "FEHLER: alte audiodabitch_engine.py gefunden"; exit 1; fi
if [ ! -f Resources/engine.py ]; then echo "FEHLER: Resources/engine.py fehlt"; exit 1; fi
if ! grep -Fq "ENGINE_VERSION = \"$APP_VERSION\"" Resources/engine.py; then echo "FEHLER: Engine-Version passt nicht zu VERSION"; grep -n "ENGINE_VERSION" Resources/engine.py || true; exit 1; fi
if ! grep -Fq "let ADBVersion = \"$APP_VERSION\"" Sources/AudioDaBitch/main.swift; then echo "FEHLER: Swift-App-Version passt nicht zu VERSION"; grep -n "ADBVersion" Sources/AudioDaBitch/main.swift || true; exit 1; fi
python3 -m py_compile Resources/engine.py; cleanup; echo "Python Engine: OK"
find . -name "*.command" -not -path "./.git/*" -print0 | while IFS= read -r -d '' f; do bash -n "$f"; done
find scripts PackageScripts -type f -perm -111 -print0 2>/dev/null | while IFS= read -r -d '' f; do case "$f" in *.sh|*.command|*/preinstall|*/postinstall) bash -n "$f" ;; esac; done
echo "Shell Scripts: OK"
VERSION="$APP_VERSION" ./scripts/build_pkg.sh >/tmp/audiodabitch-build-check.txt
if [ ! -f build/AudioDaBitch.app/Contents/Resources/engine.py ]; then echo "FEHLER: engine.py fehlt im App-Bundle"; exit 1; fi
if [ -d build/AudioDaBitch.app/Contents/Resources/engine ]; then echo "FEHLER: alter Resources/engine Ordner im Bundle"; exit 1; fi
if [ ! -f build/AudioDaBitch.app/Contents/Resources/AudioDaBitch.icns ]; then echo "FEHLER: Icon fehlt im App-Bundle"; exit 1; fi
if [ ! -f dist/AudioDaBitch.pkg ]; then echo "FEHLER: dist/AudioDaBitch.pkg wurde nicht gebaut"; exit 1; fi
PKG_PAYLOAD="$(pkgutil --payload-files dist/AudioDaBitch.pkg)"
if ! printf "%s\n" "$PKG_PAYLOAD" | grep -Eq '^(\./)?Applications/AudioDaBitch.app/Contents/MacOS/AudioDaBitch$'; then echo "FEHLER: PKG enthält keine Applications/AudioDaBitch.app"; exit 1; fi
if ! printf "%s\n" "$PKG_PAYLOAD" | grep -Eq '^(\./)?Applications/AudioDaBitch.app/Contents/Resources/engine.py$'; then echo "FEHLER: PKG enthält keine Resources/engine.py"; exit 1; fi
cleanup
echo "Swift Build und PKG: OK"
echo
echo "Dev Check fertig."
