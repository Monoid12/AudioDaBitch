#!/bin/bash
set -euo pipefail
DEFAULT_REPO="$HOME/Documents/CODING/AudioDaBitch/AudioDaBitch_repo"
VERSION_TARGET="0.5.7"
repo_path() {
  if [ -n "${ADB_REPO_PATH:-}" ] && [ -d "$ADB_REPO_PATH/.git" ]; then echo "$ADB_REPO_PATH"; return; fi
  if [ -d "$DEFAULT_REPO/.git" ]; then echo "$DEFAULT_REPO"; return; fi
  echo "Repo nicht gefunden: $DEFAULT_REPO" >&2
  echo "Bitte ADB_REPO_PATH setzen oder Repo an diesen Pfad legen." >&2
  exit 1
}
ensure_gh() {
  if ! command -v gh >/dev/null 2>&1; then echo "FEHLER: GitHub CLI gh fehlt. Bitte: brew install gh"; exit 1; fi
  gh auth status >/dev/null || { echo "FEHLER: gh ist nicht angemeldet. Bitte einmal gh auth login ausführen."; exit 1; }
}
clean_caches() {
  find . -type d -name "__pycache__" -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true
  find . -name "*.pyc" -not -path "./.git/*" -delete 2>/dev/null || true
  rm -rf build 2>/dev/null || true
}
