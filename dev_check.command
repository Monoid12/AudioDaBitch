#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cleanup_cache_artifacts() {
  rm -rf build dist 2>/dev/null || true
  find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true
  find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true
}
cleanup_cache_artifacts
echo "AudioDaBitch Dev Check"
echo "======================"
APP_VERSION="$(cat VERSION | tr -d '[:space:]')"
echo "Version: $APP_VERSION"
echo
echo "Git Status:"
git status --short || true
echo
if find . -path "*/audiodabitch_engine.py" -not -path "./.git/*" | grep -q .; then
  echo "FEHLER: alte audiodabitch_engine.py gefunden."
  find . -path "*/audiodabitch_engine.py" -not -path "./.git/*"
  exit 1
fi
EXPECTED="ENGINE_VERSION = \"$APP_VERSION\""
if ! grep -Fq "$EXPECTED" Resources/engine.py; then
  echo "FEHLER: Engine-Version passt nicht zu VERSION. Erwartet: $EXPECTED"
  grep -n "ENGINE_VERSION" Resources/engine.py || true
  exit 1
fi
python3 -m py_compile Resources/engine.py
echo "Python Engine: OK"
find . -name "*.command" -not -path "./.git/*" -print0 | while IFS= read -r -d '' f; do bash -n "$f"; done
find scripts PackageScripts -type f -perm -111 -print0 2>/dev/null | while IFS= read -r -d '' f; do
  case "$f" in *.sh|*.command|*/preinstall|*/postinstall) bash -n "$f" ;; esac
done
echo "Shell Scripts: OK"
if [ -x ./scripts/build_app.sh ]; then
  VERSION="$APP_VERSION" ./scripts/build_app.sh >/tmp/audiodabitch-build-check.txt
  cleanup_cache_artifacts
  echo "Swift Build: OK"
else
  echo "WARNUNG: scripts/build_app.sh fehlt oder ist nicht ausführbar."
fi
echo
echo "Dev Check fertig."
