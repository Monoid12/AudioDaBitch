#!/bin/bash
set -u
APP_NAME="AudioDaBitch"
RESOURCES="${ADB_RESOURCES:-$(cd "$(dirname "$0")" && pwd)}"
APP_SUPPORT="$HOME/Library/Application Support/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
LOG_FILE="$LOG_DIR/AudioDaBitch.log"
ENGINE_LOG="$LOG_DIR/AudioEngine.log"
VENV_DIR="$APP_SUPPORT/venv"
MARKER_FILE="$APP_SUPPORT/venv.marker"
ENGINE="$RESOURCES/engine.py"
mkdir -p "$APP_SUPPORT" "$LOG_DIR"

echo_json_string() { /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || printf '"error"'; }
fail_json() { msg="$1"; printf '{"ok":false,"error":%s}\n' "$(echo_json_string "$msg")"; exit 1; }

find_python() {
  PYTHON_BIN=""
  PYTHON_ARM64="0"
  IS_ARM64="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
  for candidate in \
    "/opt/homebrew/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3" \
    "/usr/local/bin/python3" \
    "/usr/bin/python3" \
    "/Library/Developer/CommandLineTools/usr/bin/python3"
  do
    [ -x "$candidate" ] || continue
    if [ "$IS_ARM64" = "1" ]; then
      if /usr/bin/arch -arm64 "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)' >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"; PYTHON_ARM64="1"; return 0
      fi
    fi
    if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)' >/dev/null 2>&1; then
      PYTHON_BIN="$candidate"; PYTHON_ARM64="0"; return 0
    fi
  done
  return 1
}

base_python() {
  if [ "$PYTHON_ARM64" = "1" ]; then /usr/bin/arch -arm64 "$PYTHON_BIN" "$@"; else "$PYTHON_BIN" "$@"; fi
}
venv_python() {
  if [ "$PYTHON_ARM64" = "1" ]; then /usr/bin/arch -arm64 "$VENV_DIR/bin/python" "$@"; else "$VENV_DIR/bin/python" "$@"; fi
}

kill_existing_engines() {
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "${PID:-}" ]; then kill "$PID" >/dev/null 2>&1 || true; fi
  fi
  # Kill old AudioDaBitch engine processes that may have survived window closes or updates.
  /usr/bin/pgrep -f "engine.py --run .*AudioDaBitch" 2>/dev/null | while read -r OLD; do
    [ -n "$OLD" ] || continue
    [ "$OLD" = "$$" ] && continue
    kill "$OLD" >/dev/null 2>&1 || true
  done
  sleep 0.3
  /usr/bin/pgrep -f "engine.py --run .*AudioDaBitch" 2>/dev/null | while read -r OLD; do
    [ -n "$OLD" ] || continue
    [ "$OLD" = "$$" ] && continue
    kill -9 "$OLD" >/dev/null 2>&1 || true
  done
}

setup_env() {
  find_python || fail_json "Python 3.9 oder neuer wurde nicht gefunden. Bitte Python 3 von python.org oder Homebrew installieren."
  PY_ID="$(base_python -c 'import sys,platform; print(platform.machine()+"|"+str(sys.version_info[0])+"."+str(sys.version_info[1])+"."+str(sys.version_info[2]))' 2>/dev/null || echo unknown)"
  NEED_SETUP="0"
  if [ ! -x "$VENV_DIR/bin/python" ]; then NEED_SETUP="1"; fi
  if [ ! -f "$MARKER_FILE" ]; then NEED_SETUP="1"; fi
  if [ "$(cat "$MARKER_FILE" 2>/dev/null || true)" != "$PY_ID" ]; then NEED_SETUP="1"; fi
  if [ "$NEED_SETUP" = "0" ]; then
    if ! venv_python -c 'import numpy, sounddevice' >/dev/null 2>&1; then
      NEED_SETUP="1"
    fi
  fi
  if [ "$NEED_SETUP" = "1" ]; then
    {
      echo "---- $(date) Setup start ----"
      echo "Base Python: $PYTHON_BIN"
      echo "Python ID: $PY_ID arm64_pref=$PYTHON_ARM64"
      rm -rf "$VENV_DIR"
      base_python -m venv "$VENV_DIR"
      venv_python -m ensurepip --upgrade
      venv_python -m pip install --upgrade pip setuptools wheel
      venv_python -m pip install --upgrade "numpy>=2.0,<3" "sounddevice>=0.5,<0.6"
      echo "$PY_ID" > "$MARKER_FILE"
      echo "---- $(date) Setup done ----"
    } >> "$LOG_FILE" 2>&1 || fail_json "Setup der Audio-Komponenten ist fehlgeschlagen. Details: $LOG_FILE"
  fi
}

cmd="${1:-}"
case "$cmd" in
  list)
    setup_env
    OUT="$(venv_python "$ENGINE" --list-devices 2>>"$LOG_FILE")" || {
      echo "$OUT" >> "$LOG_FILE"
      fail_json "Audiogeraete konnten nicht gelesen werden. Details: $LOG_FILE"
    }
    echo "$OUT" >> "$LOG_FILE"
    printf '%s\n' "$OUT" | tail -n 1
    ;;
  start)
    setup_env
    CONFIG="${2:-}"; LEVELS="${3:-}"; PIDFILE="${4:-}"
    [ -n "$CONFIG" ] || fail_json "Config fehlt."
    [ -n "$LEVELS" ] || fail_json "Level-Datei fehlt."
    [ -n "$PIDFILE" ] || fail_json "PID-Datei fehlt."
    kill_existing_engines
    nohup "$VENV_DIR/bin/python" "$ENGINE" --run "$CONFIG" "$LEVELS" "$PIDFILE" >> "$ENGINE_LOG" 2>&1 &
    child="$!"
    sleep 0.6
    if kill -0 "$child" >/dev/null 2>&1; then
      printf '{"ok":true,"pid":%s}\n' "$child"
    else
      fail_json "Audio-Engine konnte nicht gestartet werden. Details: $ENGINE_LOG"
    fi
    ;;
  stop)
    PIDFILE="${2:-$APP_SUPPORT/engine.pid}"
    if [ -f "$PIDFILE" ]; then
      PID="$(cat "$PIDFILE" 2>/dev/null || true)"
      if [ -n "$PID" ]; then kill "$PID" >/dev/null 2>&1 || true; sleep 0.2; kill -9 "$PID" >/dev/null 2>&1 || true; fi
      rm -f "$PIDFILE"
    fi
    kill_existing_engines
    printf '{"ok":true}\n'
    ;;
  reset)
    rm -rf "$APP_SUPPORT/venv" "$MARKER_FILE"
    printf '{"ok":true}\n'
    ;;
  logs)
    printf '{"ok":true,"log_dir":"%s"}\n' "$LOG_DIR"
    ;;
  *)
    fail_json "Unbekannter Befehl: $cmd"
    ;;
esac
