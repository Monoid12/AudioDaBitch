#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

cleanup(){ rm -rf build dist; find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true; find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true; }
confirm(){ local prompt="$1"; local answer; read -r -p "$prompt [j/N]: " answer; case "$answer" in j|J|ja|JA|y|Y) return 0 ;; *) return 1 ;; esac; }

clear || true
echo "AudioDaBitch Release Assistent"
echo "=============================="
default="$(tr -d '[:space:]' < VERSION)"
read -r -p "Neue Version [$default]: " version
version="${version:-$default}"

echo "$version" > VERSION
perl -pi -e "s/ENGINE_VERSION = \"[0-9.]+\"/ENGINE_VERSION = \"$version\"/" Resources/engine.py
perl -pi -e "s/AudioDaBitch Engine [0-9.]+/AudioDaBitch Engine $version/" Resources/engine.py
perl -pi -e "s/let ADBVersion = \"[0-9.]+\"/let ADBVersion = \"$version\"/" Sources/AudioDaBitch/main.swift

cleanup
./dev_check.command
cleanup

echo
echo "Git Status:"
git status --short
echo

if confirm "Geprüfte Änderungen jetzt committen?"; then
  git add VERSION Resources/engine.py Sources/AudioDaBitch/main.swift CHANGELOG.md Resources/CHANGELOG.md RELEASE_NOTES.md README.md START_HIER_DE.md docs scripts PackageScripts .github dev_check.command release.command
  if git diff --cached --quiet; then
    echo "Keine Änderungen zum Committen."
  else
    git commit -m "AudioDaBitch $version"
  fi
fi

branch="$(git branch --show-current)"
if [ "$branch" != "main" ]; then
  echo
  echo "Aktueller Branch: $branch"
  echo "Push/Tag wird hier nicht automatisch gemacht. Bitte erst den geprüften Branch nach main mergen."
  exit 0
fi

if confirm "main jetzt zu GitHub pushen?"; then
  git push origin main
fi

tag="v$version"
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "FEHLER: Tag $tag existiert bereits."
  exit 1
fi

if confirm "Tag $tag erstellen und pushen?"; then
  git tag "$tag"
  git push origin "$tag"
  echo
  echo "GitHub Actions wurde gestartet."
  echo "Release-Seite: https://github.com/Monoid12/AudioDaBitch/releases"
fi
