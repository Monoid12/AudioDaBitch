#!/usr/bin/env python3
# AudioDaBitch Engine 0.5.7
from __future__ import annotations

import atexit
import array
import json
import math
import os
import queue
import signal
import subprocess
import sys
import threading
import time
import venv
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List

ENGINE_VERSION = "0.5.7"
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
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] {message}\n")
    except Exception:
        pass


def ensure_audio_dependencies() -> None:
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
        subprocess.check_call([str(py), "-m", "pip", "install", "--upgrade", "sounddevice==0.5.7", "cffi"], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
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
        "safeMode": True,
        "sampleRate": 48000,
        "blockSize": 1024,
        "latency": "high",
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


class RingBuffer:
    def __init__(self, max_samples: int = 48000 * 8) -> None:
        self.lock = threading.Lock()
        self.data: deque[float] = deque(maxlen=max_samples)
        self.underruns = 0
        self.overruns = 0

    def clear(self) -> None:
        with self.lock:
            self.data.clear()
            self.underruns = 0
            self.overruns = 0

    def append(self, values: List[float]) -> None:
        with self.lock:
            before_free = self.data.maxlen - len(self.data) if self.data.maxlen else len(values)
            if before_free < len(values):
                self.overruns += 1
            self.data.extend(values)

    def read(self, count: int) -> List[float]:
        out: List[float] = []
        with self.lock:
            n = min(count, len(self.data))
            for _ in range(n):
                out.append(self.data.popleft())
            if n < count:
                self.underruns += 1
                out.extend([0.0] * (count - n))
        return out

    def diagnostics(self) -> Dict[str, Any]:
        with self.lock:
            return {"queuedSamples": len(self.data), "underruns": self.underruns, "overruns": self.overruns}


class AudioEngine:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.running = False
        self.streams: List[Any] = []
        self.buffers: Dict[str, RingBuffer] = {"discord": RingBuffer(), "xpilot": RingBuffer()}
        self.meters = {"discord": -120.0, "xpilot": -120.0, "output": -120.0}
        self.leveler_gain = 1.0
        self.last_error = ""
        self.sample_rate = 48000
        self.block_size = 1024
        self.latency: Any = "high"
        self.callback_errors = 0

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
            self.buffers["discord"].clear()
            self.buffers["xpilot"].clear()
            log("audio stopped")

    def _input_cb(self, source: str):
        def cb(indata, frames, time_info, status):
            try:
                samples = array.array("f")
                samples.frombytes(bytes(indata))
                vals = list(samples)
                self.meters[source] = meter_db(vals)
                self.buffers[source].append(vals)
            except Exception:
                self.callback_errors += 1
        return cb

    def _get_stereo(self, source: str, frames: int) -> List[float]:
        return self.buffers[source].read(frames * 2)

    def _pan(self, stereo: List[float], pan: float) -> List[float]:
        pan = max(-1.0, min(1.0, float(pan)))
        angle = (pan + 1.0) * math.pi / 4.0
        lg, rg = math.cos(angle), math.sin(angle)
        out: List[float] = []
        for i in range(0, len(stereo), 2):
            left = stereo[i]
            right = stereo[i + 1] if i + 1 < len(stereo) else left
            mono = 0.5 * (left + right)
            out.append(mono * lg)
            out.append(mono * rg)
        return out

    def _output_cb(self, outdata, frames, time_info, status):
        try:
            with CONFIG_LOCK:
                cfg = dict(CONFIG)
            d = self._pan(self._get_stereo("discord", frames), float(cfg.get("discordPan", -1.0)))
            x = self._pan(self._get_stereo("xpilot", frames), float(cfg.get("xpilotPan", 1.0)))
            dg = db_to_gain(float(cfg.get("discordGainDb", 0.0)))
            xg = db_to_gain(float(cfg.get("xpilotGainDb", 0.0)))
            mg = db_to_gain(float(cfg.get("masterGainDb", 0.0)))
            ceiling = db_to_gain(float(cfg.get("limiterCeilingDb", -1.0)))

            if cfg.get("xpilotLevelerEnabled", True):
                xdb = self.meters.get("xpilot", -120.0)
                target = -21.0
                desired = db_to_gain(max(-18.0, min(12.0, target - xdb))) if xdb > -60 else 1.0
                alpha = 0.18 if desired < self.leveler_gain else 0.025
                self.leveler_gain = self.leveler_gain + alpha * (desired - self.leveler_gain)
                xg *= self.leveler_gain

            if cfg.get("duckingEnabled", True):
                th = float(cfg.get("thresholdDb", -32.0))
                duck = db_to_gain(float(cfg.get("duckDepthDb", -12.0)))
                if cfg.get("duckingMode", "xpilot_ducks_discord") == "xpilot_ducks_discord" and self.meters.get("xpilot", -120) > th:
                    dg *= duck
                if cfg.get("duckingMode") == "discord_ducks_xpilot" and self.meters.get("discord", -120) > th:
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
            outdata[:] = array.array("f", mix).tobytes()
        except Exception:
            self.callback_errors += 1
            outdata[:] = array.array("f", [0.0] * (frames * 2)).tobytes()

    def start(self) -> Dict[str, Any]:
        if sd is None:
            self.last_error = SOUNDDEVICE_ERROR or "sounddevice unavailable"
            return {"ok": False, "error": self.last_error}
        with self.lock:
            self.stop()
            load_config()
            with CONFIG_LOCK:
                cfg = dict(CONFIG)
            out_dev = cfg.get("outputDevice")
            if out_dev is None:
                return {"ok": False, "error": "Bitte Output auswählen."}
            self.sample_rate = int(cfg.get("sampleRate", 48000) or 48000)
            self.block_size = int(cfg.get("blockSize", 1024) or 1024)
            if cfg.get("safeMode", True):
                self.block_size = max(self.block_size, 1024)
                self.latency = "high"
            else:
                self.block_size = max(256, self.block_size)
                self.latency = cfg.get("latency", "low") or "low"
            try:
                if cfg.get("discordInput") is not None:
                    self.streams.append(sd.RawInputStream(device=int(cfg["discordInput"]), channels=2, samplerate=self.sample_rate, blocksize=self.block_size, latency=self.latency, dtype="float32", callback=self._input_cb("discord")))
                if cfg.get("xpilotInput") is not None:
                    self.streams.append(sd.RawInputStream(device=int(cfg["xpilotInput"]), channels=2, samplerate=self.sample_rate, blocksize=self.block_size, latency=self.latency, dtype="float32", callback=self._input_cb("xpilot")))
                self.streams.append(sd.RawOutputStream(device=int(out_dev), channels=2, samplerate=self.sample_rate, blocksize=self.block_size, latency=self.latency, dtype="float32", callback=self._output_cb))
                for s in self.streams:
                    s.start()
                self.running = True
                self.last_error = ""
                log(f"streams started sr={self.sample_rate} block={self.block_size} latency={self.latency}")
                return {"ok": True, "sampleRate": self.sample_rate, "blockSize": self.block_size, "latency": str(self.latency)}
            except Exception as e:
                self.last_error = repr(e)
                log(f"audio start failed: {e!r}")
                self.stop()
                return {"ok": False, "error": self.last_error}

    def state(self) -> Dict[str, Any]:
        return {"ok": True, "version": ENGINE_VERSION, "running": self.running, "meters": dict(self.meters), "levelerGainDb": gain_to_db(self.leveler_gain), "diagnostics": self.diagnostics()}

    def diagnostics(self) -> Dict[str, Any]:
        return {"sampleRate": self.sample_rate, "blockSize": self.block_size, "latency": str(self.latency), "callbackErrors": self.callback_errors, "discord": self.buffers["discord"].diagnostics(), "xpilot": self.buffers["xpilot"].diagnostics(), "lastError": self.last_error}

ENGINE = AudioEngine()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _read_json(self) -> Dict[str, Any]:
        n = int(self.headers.get("Content-Length", "0") or "0")
        if n <= 0:
            return {}
        try:
            data = json.loads(self.rfile.read(n).decode("utf-8"))
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
        elif self.path.startswith("/diagnostics"):
            self._send({"ok": True, "version": ENGINE_VERSION, "sounddevice": sd is not None, "engine": ENGINE.diagnostics(), "devices": list_devices()})
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
