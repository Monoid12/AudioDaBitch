#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

cleanup_cache_artifacts() {
  find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true
  find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true
}

cleanup_cache_artifacts
echo "AudioDaBitch Release Assistent"
echo "=============================="
current="$(cat VERSION)"
read -r -p "Neue Version [$current]: " version
version="${version:-$current}"
echo "$version" > VERSION
perl -pi -e "s/AudioDaBitch [0-9]+\.[0-9]+\.[0-9]+/AudioDaBitch $version/g; s/ADBVersion = \"[0-9]+\.[0-9]+\.[0-9]+\"/ADBVersion = \"$version\"/g; s/ENGINE_VERSION = \"[0-9]+\.[0-9]+\.[0-9]+\"/ENGINE_VERSION = \"$version\"/g; s/## [0-9]+\.[0-9]+\.[0-9]+/## $version/ if $. < 10" Sources/AudioDaBitch/main.swift Resources/engine.py RELEASE_NOTES.md Resources/CHANGELOG.md CHANGELOG.md 2>/dev/null || true
./dev_check.command
echo
read -r -p "Release v$version jetzt committen, pushen und bauen? [j/N]: " ok
case "$ok" in
  j|J|ja|JA|y|Y|yes|YES) ;;
  *) echo "Abgebrochen."; exit 0 ;;
esac
cleanup_cache_artifacts
git add .
if git diff --cached --quiet; then
  echo "Keine Änderungen zum Committen."
else
  git commit -m "AudioDaBitch $version"
fi
git push origin main
if git rev-parse "v$version" >/dev/null 2>&1; then
  echo "Tag v$version existiert lokal bereits. Bitte Version erhöhen oder Tag löschen."
  exit 1
fi
git tag "v$version"
git push origin "v$version"
echo
echo "GitHub Actions wurde gestartet. Beobachten mit: gh run watch"
echo "Release-Seite: https://github.com/Monoid12/AudioDaBitch/releases"
