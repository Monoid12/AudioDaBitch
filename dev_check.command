#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "AudioDaBitch Dev Check"
echo "======================"
echo "Version: $(cat VERSION)"
echo
if find . -type d -name "__pycache__" -not -path "./.git/*" | grep -q .; then
  echo "WARNUNG: __pycache__ Ordner gefunden. Bitte entfernen."
fi
if find . -name "*.pyc" -not -path "./.git/*" | grep -q .; then
  echo "WARNUNG: .pyc Dateien gefunden. Bitte entfernen."
fi
echo "Git Status:"
git status --short || true
echo
python3 -m py_compile Resources/engine.py
echo "Python Engine: OK"
for f in $(find . -name "*.sh" -o -name "*.command"); do bash -n "$f"; done
echo "Shell Scripts: OK"
if command -v swiftc >/dev/null 2>&1; then
  mkdir -p /tmp/audiodabitch-check
  swiftc Sources/AudioDaBitch/main.swift -o /tmp/audiodabitch-check/AudioDaBitchCheck -framework Cocoa
  echo "Swift Build: OK"
else
  echo "Swift Build: UEBERSPRUNGEN - swiftc nicht gefunden"
fi
echo
echo "Dev Check fertig."
