#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
echo "AudioDaBitch Dev Check"
echo "======================"
VERSION="$(cat VERSION 2>/dev/null || echo unknown)"
echo "Version: $VERSION"
echo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Git Status:"
  git status --short
  echo
fi
if find . -type d -name "__pycache__" -not -path "./.git/*" | grep -q .; then
  echo "WARNUNG: __pycache__ Ordner gefunden. Bitte entfernen."
fi

if find . -name "*.pyc" -not -path "./.git/*" | grep -q .; then
  echo "WARNUNG: .pyc Dateien gefunden. Bitte entfernen."
fi
python3 -m py_compile Resources/engine.py
echo "Python Engine: OK"
bash -n Resources/adbctl.sh
bash -n scripts/build_app.sh
bash -n scripts/build_pkg.sh
bash -n release.command
echo "Shell Scripts: OK"
if command -v swiftc >/dev/null 2>&1; then
  swiftc -parse Sources/AudioDaBitch/main.swift >/dev/null 2>&1 && echo "Swift Syntax: OK" || echo "Swift Syntax: WARNUNG/Fehler - bitte GitHub Actions pruefen"
else
  echo "Swift Syntax: uebersprungen, swiftc nicht gefunden"
fi
echo
echo "Dev Check fertig."
