#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cleanup(){ rm -rf build; find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true; find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true; }
clear || true
echo "AudioDaBitch Release Assistent"
echo "=============================="
default="$(tr -d '[:space:]' < VERSION)"
read -r -p "Neue Version [$default]: " version
version="${version:-$default}"
echo "$version" > VERSION
perl -pi -e "s/ENGINE_VERSION = \"[0-9.]+\"/ENGINE_VERSION = \"$version\"/" Resources/engine.py
perl -pi -e "s/let ADBVersion = \"[0-9.]+\"/let ADBVersion = \"$version\"/" Sources/AudioDaBitch/main.swift
cleanup
./dev_check.command
cleanup
echo
read -r -p "Release v$version jetzt committen, pushen und bauen? [j/N]: " yn
case "$yn" in j|J|ja|JA|y|Y) ;; *) echo "Abgebrochen."; exit 0 ;; esac
git add .
if git diff --cached --quiet; then echo "Keine Änderungen zum Committen."; else git commit -m "AudioDaBitch $version"; fi
git push origin main
if git rev-parse "v$version" >/dev/null 2>&1; then echo "FEHLER: Tag v$version existiert bereits."; exit 1; fi
git tag "v$version"
git push origin "v$version"
echo
echo "GitHub Actions wurde gestartet. Beobachten mit: gh run watch"
echo "Release-Seite: https://github.com/Monoid12/AudioDaBitch/releases"
