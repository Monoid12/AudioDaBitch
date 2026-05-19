#!/usr/bin/env python3
# AudioDaBitch Engine 0.5.5
from __future__ import annotations

import atexit
import array
import json
import math
import os
import queue
import signal
import socket
import subprocess
import sys
import threading
import time
import venv
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional

ENGINE_VERSION = "0.5.5"
PORT = 49372
APP_NAME = "AudioDaBitch"
SUPPORT_DIR = Path.home() / "Library" / "Application Support" / APP_NAME
LOG_DIR = Path.home() / "Library" / "Logs" / APP_NAME
CONFIG_FILE = SUPPORT_DIR / "config.json"
PID_FILE = SUPPORT_DIR / "engine.pid"
VENV_DIR = SUPPORT_DIR / "venv"
LOG_FILE = LOG_DIR / "engine.log"
BOOTSTRAP_FLAG = "ADB_ENGINE_BOOTSTRAPPED"

for d in (SUPPORT_DIR, LOG_DIR):
    d.mkdir(parents=True, exist_ok=True)


def log(message: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {message}\n"
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def ensure_audio_dependencies() -> None:
    """Ensure sounddevice is available in a local venv, then re-exec into it."""
    if os.environ.get(BOOTSTRAP_FLAG) == "1":
        return
    try:
        import sounddevice  # noqa: F401
        return
    except Exception as e:
        log(f"sounddevice import failed before bootstrap: {e!r}")

    py = VENV_DIR / "bin" / "python3"
    try:
        if not py.exists():
            log(f"creating venv: {VENV_DIR}")
            venv.EnvBuilder(with_pip=True, clear=True).create(str(VENV_DIR))
        log("installing audio dependencies: sounddevice cffi")
        subprocess.check_call([str(py), "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        subprocess.check_call([str(py), "-m", "pip", "install", "--upgrade", "sounddevice==0.5.5", "cffi"], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        env = os.environ.copy()
        env[BOOTSTRAP_FLAG] = "1"
        log(f"re-exec engine with venv python: {py}")
        os.execve(str(py), [str(py), str(Path(__file__).resolve())], env)
    except Exception as e:
        log(f"dependency bootstrap failed: {e!r}")


ensure_audio_dependencies()

try:
    import sounddevice as sd
    SOUNDDEVICE_ERROR = ""
except Exception as e:
    sd = None  # type: ignore
    SOUNDDEVICE_ERROR = repr(e)
    log(f"sounddevice unavailable after bootstrap: {SOUNDDEVICE_ERROR}")


def save_pid() -> None:
    try:
        PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    except Exception as e:
        log(f"save pid failed: {e!r}")


def cleanup_pid() -> None:
    try:
        if PID_FILE.exists() and PID_FILE.read_text().strip() == str(os.getpid()):
            PID_FILE.unlink()
    except Exception:
        pass


def db_to_gain(db: float) -> float:
    return 10.0 ** (db / 20.0)


def gain_to_db(gain: float) -> float:
    if gain <= 1e-9:
        return -120.0
    return max(-120.0, min(24.0, 20.0 * math.log10(gain)))


def meter_db(samples: List[float]) -> float:
    if not samples:
        return -120.0
    peak = max(abs(x) for x in samples)
    return gain_to_db(peak)


def default_config() -> Dict[str, Any]:
    return {
        "discordInput": None,
        "xpilotInput": None,
        "outputDevice": None,
        "discordGainDb": 0.0,
        "xpilotGainDb": 0.0,
        "masterGainDb": 0.0,
        "discordPan": -1.0,
        "xpilotPan": 1.0,
        "duckingEnabled": True,
        "duckingMode": "xpilot_ducks_discord",
        "duckDepthDb": -12.0,
        "thresholdDb": -32.0,
        "limiterCeilingDb": -1.0,
        "xpilotLevelerEnabled": True,
        "xpilotLevelerPreset": "standard",
    }

CONFIG_LOCK = threading.RLock()
CONFIG = default_config()


def load_config() -> None:
    global CONFIG
    with CONFIG_LOCK:
        CONFIG = default_config()
        if CONFIG_FILE.exists():
            try:
                data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    CONFIG.update(data)
            except Exception as e:
                log(f"load config failed: {e!r}")


def save_config() -> None:
    with CONFIG_LOCK:
        CONFIG_FILE.write_text(json.dumps(CONFIG, indent=2, ensure_ascii=False), encoding="utf-8")


def list_devices() -> Dict[str, Any]:
    if sd is None:
        return {"inputs": [], "outputs": [], "error": SOUNDDEVICE_ERROR or "sounddevice unavailable"}
    try:
        devices = sd.query_devices()
        inputs: List[Dict[str, Any]] = []
        outputs: List[Dict[str, Any]] = []
        for idx, d in enumerate(devices):
            name = str(d.get("name", f"Device {idx}"))
            hostapi = int(d.get("hostapi", 0))
            max_in = int(d.get("max_input_channels", 0))
            max_out = int(d.get("max_output_channels", 0))
            samplerate = float(d.get("default_samplerate", 48000.0) or 48000.0)
            item = {"id": idx, "name": name, "hostapi": hostapi, "sampleRate": samplerate, "inputs": max_in, "outputs": max_out}
            if max_in > 0:
                inputs.append(item)
            if max_out > 0:
                outputs.append(item)
        return {"inputs": inputs, "outputs": outputs, "error": ""}
    except Exception as e:
        log(f"query devices failed: {e!r}")
        return {"inputs": [], "outputs": [], "error": repr(e)}


class AudioEngine:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.running = False
        self.streams: List[Any] = []
        self.queues: Dict[str, queue.Queue[List[float]]] = {"discord": queue.Queue(maxsize=8), "xpilot": queue.Queue(maxsize=8)}
        self.meters = {"discord": -120.0, "xpilot": -120.0, "output": -120.0}
        self.leveler_gain = 1.0

    def stop(self) -> None:
        with self.lock:
            for s in self.streams:
                try:
                    s.stop()
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass
            self.streams = []
            self.running = False
            while not self.queues["discord"].empty():
                try: self.queues["discord"].get_nowait()
                except Exception: break
            while not self.queues["xpilot"].empty():
                try: self.queues["xpilot"].get_nowait()
                except Exception: break
            log("audio stopped")

    def _input_cb(self, source: str):
        def cb(indata, frames, time_info, status):
            try:
                samples = array.array("f")
                samples.frombytes(bytes(indata))
                vals = list(samples)
                self.meters[source] = meter_db(vals)
                q = self.queues[source]
                if q.full():
                    try: q.get_nowait()
                    except Exception: pass
                q.put_nowait(vals)
            except Exception as e:
                log(f"input cb {source} failed: {e!r}")
        return cb

    def _get_stereo(self, source: str, frames: int) -> List[float]:
        try:
            vals = self.queues[source].get_nowait()
        except Exception:
            return [0.0] * (frames * 2)
        if len(vals) < frames * 2:
            vals = vals + [0.0] * (frames * 2 - len(vals))
        return vals[: frames * 2]

    def _pan(self, stereo: List[float], pan: float) -> List[float]:
        pan = max(-1.0, min(1.0, float(pan)))
        angle = (pan + 1.0) * math.pi / 4.0
        lg, rg = math.cos(angle), math.sin(angle)
        out: List[float] = []
        for i in range(0, len(stereo), 2):
            mono = 0.5 * (stereo[i] + stereo[i + 1])
            out.append(mono * lg)
            out.append(mono * rg)
        return out

    def _output_cb(self, outdata, frames, time_info, status):
        with CONFIG_LOCK:
            cfg = dict(CONFIG)
        d = self._pan(self._get_stereo("discord", frames), float(cfg.get("discordPan", -1.0)))
        x = self._pan(self._get_stereo("xpilot", frames), float(cfg.get("xpilotPan", 1.0)))
        dg = db_to_gain(float(cfg.get("discordGainDb", 0.0)))
        xg = db_to_gain(float(cfg.get("xpilotGainDb", 0.0)))
        mg = db_to_gain(float(cfg.get("masterGainDb", 0.0)))
        ceiling = db_to_gain(float(cfg.get("limiterCeilingDb", -1.0)))

        # simple xPilot auto-level: fast cut of loud signals, cautious boost of quiet signals
        if cfg.get("xpilotLevelerEnabled", True):
            xdb = self.meters.get("xpilot", -120.0)
            target = -21.0
            desired = db_to_gain(max(-18.0, min(12.0, target - xdb))) if xdb > -60 else 1.0
            alpha = 0.22 if desired < self.leveler_gain else 0.04
            self.leveler_gain = self.leveler_gain + alpha * (desired - self.leveler_gain)
            xg *= self.leveler_gain

        if cfg.get("duckingEnabled", True):
            mode = cfg.get("duckingMode", "xpilot_ducks_discord")
            th = float(cfg.get("thresholdDb", -32.0))
            duck = db_to_gain(float(cfg.get("duckDepthDb", -12.0)))
            if mode == "xpilot_ducks_discord" and self.meters.get("xpilot", -120) > th:
                dg *= duck
            if mode == "discord_ducks_xpilot" and self.meters.get("discord", -120) > th:
                xg *= duck

        mix: List[float] = []
        peak = 0.0
        for i in range(frames * 2):
            v = (d[i] * dg + x[i] * xg) * mg
            if abs(v) > ceiling and abs(v) > 1e-9:
                v = ceiling if v > 0 else -ceiling
            v = max(-1.0, min(1.0, v))
            peak = max(peak, abs(v))
            mix.append(v)
        self.meters["output"] = gain_to_db(peak)
        b = array.array("f", mix).tobytes()
        outdata[:] = b

    def start(self) -> Dict[str, Any]:
        if sd is None:
            return {"ok": False, "error": SOUNDDEVICE_ERROR or "sounddevice unavailable"}
        with self.lock:
            self.stop()
            with CONFIG_LOCK:
                cfg = dict(CONFIG)
            out_dev = cfg.get("outputDevice")
            if out_dev is None:
                return {"ok": False, "error": "Bitte Output auswählen."}
            sr = 48000
            block = 256
            try:
                if cfg.get("discordInput") is not None:
                    self.streams.append(sd.RawInputStream(device=int(cfg["discordInput"]), channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=self._input_cb("discord")))
                if cfg.get("xpilotInput") is not None:
                    self.streams.append(sd.RawInputStream(device=int(cfg["xpilotInput"]), channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=self._input_cb("xpilot")))
                self.streams.append(sd.RawOutputStream(device=int(out_dev), channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=self._output_cb))
                for s in self.streams:
                    s.start()
                self.running = True
                log("streams started")
                return {"ok": True}
            except Exception as e:
                log(f"audio start failed: {e!r}")
                self.stop()
                return {"ok": False, "error": repr(e)}

    def state(self) -> Dict[str, Any]:
        return {"ok": True, "version": ENGINE_VERSION, "running": self.running, "meters": dict(self.meters), "levelerGainDb": gain_to_db(self.leveler_gain)}

ENGINE = AudioEngine()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _read_json(self) -> Dict[str, Any]:
        n = int(self.headers.get("Content-Length", "0") or "0")
        if n <= 0:
            return {}
        raw = self.rfile.read(n)
        try:
            data = json.loads(raw.decode("utf-8"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _send(self, obj: Dict[str, Any], code: int = 200) -> None:
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def do_GET(self):
        if self.path.startswith("/health"):
            self._send({"ok": True, "version": ENGINE_VERSION, "sounddevice": sd is not None, "error": SOUNDDEVICE_ERROR})
        elif self.path.startswith("/devices"):
            self._send(list_devices())
        elif self.path.startswith("/state"):
            self._send(ENGINE.state())
        elif self.path.startswith("/config"):
            with CONFIG_LOCK:
                self._send({"ok": True, "config": dict(CONFIG)})
        else:
            self._send({"ok": False, "error": "not found"}, 404)

    def do_POST(self):
        data = self._read_json()
        if self.path.startswith("/config"):
            with CONFIG_LOCK:
                CONFIG.update(data)
                save_config()
            self._send({"ok": True})
        elif self.path.startswith("/start"):
            self._send(ENGINE.start())
        elif self.path.startswith("/stop"):
            ENGINE.stop()
            self._send({"ok": True})
        elif self.path.startswith("/shutdown"):
            self._send({"ok": True})
            threading.Thread(target=lambda: (time.sleep(0.2), os.kill(os.getpid(), signal.SIGTERM)), daemon=True).start()
        else:
            self._send({"ok": False, "error": "not found"}, 404)


def main() -> int:
    save_pid()
    atexit.register(cleanup_pid)
    load_config()
    log(f"AudioDaBitch engine {ENGINE_VERSION} starting pid={os.getpid()} python={sys.executable}")
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        server.serve_forever(poll_interval=0.5)
    except OSError as e:
        log(f"server failed: {e!r}")
        return 2
    finally:
        ENGINE.stop()
        cleanup_pid()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
