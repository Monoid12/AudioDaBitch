#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
ensure_gh
REPO="$(repo_path)"
echo "Repo: $REPO"
cd "$REPO"
clean_caches
if [ -f VERSION ]; then echo "Version: $(cat VERSION)"; fi
if [ -x ./release.command ]; then
  ./release.command
else
  echo "FEHLER: release.command fehlt."
  exit 1
fi
