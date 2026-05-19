#!/usr/bin/env bash
set -euo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/AudioDaBitch"
LOG_DIR="$HOME/Library/Logs/AudioDaBitch"
VENV="$APP_SUPPORT/venv"
LOG_FILE="$LOG_DIR/engine-bootstrap.log"
mkdir -p "$APP_SUPPORT" "$LOG_DIR"
echo "---- $(date) bootstrap start ----" >> "$LOG_FILE"
find_python() {
  local candidates=(
    "/opt/homebrew/bin/python3.12"
    "/opt/homebrew/bin/python3"
    "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
    "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
    "/usr/local/bin/python3.12"
    "/usr/local/bin/python3"
    "/usr/bin/python3"
  )
  for py in "${candidates[@]}"; do
    if [[ -x "$py" ]]; then
      if "$py" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
        echo "$py"
        return 0
      fi
    fi
  done
  return 1
}
PYTHON_BIN="$(find_python || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "No suitable Python 3.9+ found. Install Python 3.12 universal2 from python.org or Homebrew." >> "$LOG_FILE"
  exit 12
fi
echo "Using Python: $PYTHON_BIN" >> "$LOG_FILE"
"$PYTHON_BIN" -m venv "$VENV" >> "$LOG_FILE" 2>&1
"$VENV/bin/python" -m pip install --upgrade pip setuptools wheel >> "$LOG_FILE" 2>&1
"$VENV/bin/python" -m pip install -r "$ENGINE_DIR/requirements.txt" >> "$LOG_FILE" 2>&1
echo "---- $(date) launching engine ----" >> "$LOG_FILE"
exec "$VENV/bin/python" "$ENGINE_DIR/audiodabitch_engine.py" >> "$LOG_DIR/engine.log" 2>&1
