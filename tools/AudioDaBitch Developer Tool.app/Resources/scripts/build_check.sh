#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
REPO="$(repo_path)"
echo "Repo: $REPO"
cd "$REPO"
clean_caches
if [ -x ./dev_check.command ]; then
  ./dev_check.command
else
  echo "WARNUNG: dev_check.command fehlt. Nutze Fallback."
  python3 -m py_compile Resources/engine.py
  VERSION="$(cat VERSION)" ./scripts/build_app.sh
fi
clean_caches
echo "Build-Check fertig."
