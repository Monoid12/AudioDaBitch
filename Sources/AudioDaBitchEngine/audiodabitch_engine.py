#!/usr/bin/env python3
from __future__ import annotations

import array
import json
import math
import os
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import sounddevice as sd

APP_SUPPORT = Path.home() / "Library" / "Application Support" / "AudioDaBitch"
LOG_DIR = Path.home() / "Library" / "Logs" / "AudioDaBitch"
CONFIG_PATH = APP_SUPPORT / "config.json"
ENGINE_LOG = LOG_DIR / "engine.log"
PORT = int(os.environ.get("AUDIODABITCH_PORT", "49372"))
VERSION = os.environ.get("AUDIODABITCH_VERSION", "0.4.4")
APP_SUPPORT.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

StereoBlock = List[Tuple[float, float]]
RawBlock = Tuple[int, int, array.array]  # frames, channels, interleaved float32 samples

def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n"
    try:
        with ENGINE_LOG.open("a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass
    print(line, end="", flush=True)

def db_to_gain(db: float) -> float:
    return float(10.0 ** (db / 20.0))

def gain_to_db(gain: float) -> float:
    return float(20.0 * math.log10(max(abs(gain), 1e-9)))

def rms_db(block: StereoBlock) -> float:
    count = len(block) * 2
    if count <= 0:
        return -120.0
    s = 0.0
    for l, r in block:
        s += l * l + r * r
    return gain_to_db(math.sqrt(s / count))

def peak_db(block: StereoBlock) -> float:
    peak = 0.0
    for l, r in block:
        peak = max(peak, abs(l), abs(r))
    return gain_to_db(peak) if peak > 0 else -120.0

def one_pole(current: float, target: float, ms: float, block_size: int, sr: float) -> float:
    if ms <= 0:
        return target
    coeff = math.exp(-(block_size / sr) / (ms / 1000.0))
    return target + (current - target) * coeff

def zeros(frames: int) -> StereoBlock:
    return [(0.0, 0.0)] * frames

def scale(block: StereoBlock, gain: float) -> StereoBlock:
    if gain == 1.0:
        return block
    return [(l * gain, r * gain) for l, r in block]

def add_blocks(a: StereoBlock, b: StereoBlock) -> StereoBlock:
    n = min(len(a), len(b))
    return [(a[i][0] + b[i][0], a[i][1] + b[i][1]) for i in range(n)]

def block_peak_linear(block: StereoBlock) -> float:
    p = 0.0
    for l, r in block:
        p = max(p, abs(l), abs(r))
    return p

DEFAULT_CONFIG: Dict[str, Any] = {
    "sampleRate": 48000.0,
    "blockSize": 480,
    "discord": {"enabled": True, "deviceName": "BlackHole 2ch", "channels": [1, 2], "gainDb": 0.0, "pan": -0.75},
    "xpilot": {"enabled": True, "deviceName": "BlackHole 16ch", "channels": [1, 2], "gainDb": 0.0, "pan": 0.75},
    "outputDeviceName": "",
    "masterGainDb": 0.0,
    "limiter": {"enabled": True, "ceilingDb": -1.0, "releaseMs": 120.0},
    "ducking": {"mode": "xpilot_ducks_discord", "thresholdDb": -36.0, "depthDb": -12.0, "attackMs": 20.0, "releaseMs": 220.0},
    "xpilotAutoLevel": {"enabled": True, "targetRmsDb": -18.0, "maxBoostDb": 12.0, "maxCutDb": 18.0, "attackMs": 18.0, "releaseMs": 160.0, "peakCeilingDb": -3.0, "gateDb": -55.0},
}

def deep_merge(default: Dict[str, Any], actual: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(default)
    for k, v in actual.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out

def load_config() -> Dict[str, Any]:
    if CONFIG_PATH.exists():
        try:
            return deep_merge(DEFAULT_CONFIG, json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except Exception as exc:
            log(f"config load failed, using defaults: {exc}")
    return json.loads(json.dumps(DEFAULT_CONFIG))

def save_config(cfg: Dict[str, Any]) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")

def list_devices() -> List[Dict[str, Any]]:
    devices: List[Dict[str, Any]] = []
    try:
        for idx, dev in enumerate(sd.query_devices()):
            devices.append({
                "id": int(idx),
                "name": str(dev.get("name", "")),
                "maxInputChannels": int(dev.get("max_input_channels", 0)),
                "maxOutputChannels": int(dev.get("max_output_channels", 0)),
                "defaultSampleRate": float(dev.get("default_samplerate", 0.0)),
            })
    except Exception as exc:
        log(f"device query failed: {exc}")
    return devices

def find_device(name: str, wants_input: bool) -> Optional[int]:
    key = "max_input_channels" if wants_input else "max_output_channels"
    try:
        devices = sd.query_devices()
        if not name:
            default = sd.default.device[0 if wants_input else 1]
            return int(default) if default is not None and default >= 0 else None
        lname = name.lower(); exact = []; fuzzy = []
        for idx, dev in enumerate(devices):
            if int(dev.get(key, 0)) <= 0:
                continue
            dname = str(dev.get("name", ""))
            if dname == name:
                exact.append(idx)
            elif lname in dname.lower() or dname.lower() in lname:
                fuzzy.append(idx)
        if exact:
            return int(exact[0])
        if fuzzy:
            return int(fuzzy[0])
    except Exception as exc:
        log(f"find_device failed for {name}: {exc}")
    return None

class AudioEngine:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.cfg = load_config()
        self.running = False
        self.message = "Initialisiert"
        self.input_queues: Dict[str, queue.Queue[RawBlock]] = {"discord": queue.Queue(maxsize=12), "xpilot": queue.Queue(maxsize=12)}
        self.streams: List[Any] = []
        self.levels = {"discordRmsDb": -120.0, "xpilotRmsDb": -120.0, "outputPeakDb": -120.0, "xpilotAutoGainDb": 0.0, "duckGainDb": 0.0, "limiterGainDb": 0.0}
        self._xpilot_gain_db = 0.0
        self._duck_gain_db = 0.0
        self._limiter_gain = 1.0

    def start(self) -> None:
        with self.lock:
            self._stop_streams()
            self._start_streams_locked()

    def apply_config(self, cfg: Dict[str, Any]) -> None:
        cfg = deep_merge(DEFAULT_CONFIG, cfg)
        with self.lock:
            self.cfg = cfg
            save_config(cfg)
            log("config applied")
            self._stop_streams()
            self._start_streams_locked()

    def update_config_path(self, path: str, value: Any = None, delta: Optional[float] = None, toggle: bool = False) -> Dict[str, Any]:
        with self.lock:
            cfg = json.loads(json.dumps(self.cfg))
            parts = path.split(".")
            node = cfg
            for p in parts[:-1]:
                node = node[p]
            last = parts[-1]
            if toggle:
                node[last] = not bool(node[last])
            elif delta is not None:
                node[last] = float(node.get(last, 0.0)) + float(delta)
            else:
                node[last] = value
            self.apply_config(cfg)
            return self.cfg

    def _start_streams_locked(self) -> None:
        cfg = self.cfg
        sr = float(cfg.get("sampleRate", 48000))
        block_size = int(cfg.get("blockSize", 480))
        discord_dev = find_device(cfg["discord"].get("deviceName", ""), True) if cfg["discord"].get("enabled", True) else None
        xpilot_dev = find_device(cfg["xpilot"].get("deviceName", ""), True) if cfg["xpilot"].get("enabled", True) else None
        output_dev = find_device(cfg.get("outputDeviceName", ""), False)
        missing = []
        if cfg["discord"].get("enabled", True) and discord_dev is None:
            missing.append(f"Discord Input '{cfg['discord'].get('deviceName','')}'")
        if cfg["xpilot"].get("enabled", True) and xpilot_dev is None:
            missing.append(f"xPilot Input '{cfg['xpilot'].get('deviceName','')}'")
        if output_dev is None:
            missing.append(f"Output '{cfg.get('outputDeviceName','default')}'")
        if missing:
            self.running = False
            self.message = "Fehlende Geräte: " + ", ".join(missing)
            log(self.message)
            return
        try:
            if discord_dev is not None:
                channels = max(cfg["discord"].get("channels", [1, 2]))
                self.streams.append(sd.RawInputStream(device=discord_dev, channels=channels, samplerate=sr, blocksize=block_size, dtype="float32", callback=self._make_input_cb("discord", channels)))
            if xpilot_dev is not None:
                channels = max(cfg["xpilot"].get("channels", [1, 2]))
                self.streams.append(sd.RawInputStream(device=xpilot_dev, channels=channels, samplerate=sr, blocksize=block_size, dtype="float32", callback=self._make_input_cb("xpilot", channels)))
            self.streams.append(sd.RawOutputStream(device=output_dev, channels=2, samplerate=sr, blocksize=block_size, dtype="float32", callback=self._output_cb))
            for s in self.streams:
                s.start()
            self.running = True
            self.message = "Audio läuft"
            log("streams started")
        except Exception as exc:
            self.running = False
            self.message = f"Audio-Start fehlgeschlagen: {exc}"
            log(self.message)
            self._stop_streams()

    def _stop_streams(self) -> None:
        for s in self.streams:
            try:
                s.stop(); s.close()
            except Exception:
                pass
        self.streams = []
        for q in self.input_queues.values():
            while not q.empty():
                try:
                    q.get_nowait()
                except queue.Empty:
                    break
        self.running = False

    def _make_input_cb(self, name: str, channels: int):
        def callback(indata, frames, time_info, status):
            if status:
                log(f"{name} input status: {status}")
            samples = array.array("f")
            samples.frombytes(bytes(indata))
            q = self.input_queues[name]
            try:
                if q.full():
                    q.get_nowait()
                q.put_nowait((int(frames), int(channels), samples))
            except Exception:
                pass
        return callback

    def _get_frame(self, source: str, frames: int, channels_one_based: List[int]) -> StereoBlock:
        q = self.input_queues[source]
        try:
            got_frames, in_channels, samples = q.get_nowait()
        except queue.Empty:
            return zeros(frames)
        idxs = [max(0, int(c) - 1) for c in channels_one_based[:2]]
        while len(idxs) < 2:
            idxs.append(idxs[0] if idxs else 0)
        out: StereoBlock = []
        n = min(frames, got_frames)
        for i in range(n):
            vals = []
            base = i * in_channels
            for in_ch in idxs:
                vals.append(float(samples[base + in_ch]) if in_ch < in_channels and base + in_ch < len(samples) else 0.0)
            out.append((vals[0], vals[1]))
        if n < frames:
            out.extend(zeros(frames - n))
        return out

    def _pan(self, stereo: StereoBlock, pan: float) -> StereoBlock:
        pan = float(max(-1.0, min(1.0, pan)))
        angle = (pan + 1.0) * math.pi / 4.0
        lg = math.cos(angle)
        rg = math.sin(angle)
        return [(((l + r) * 0.5) * lg, ((l + r) * 0.5) * rg) for l, r in stereo]

    def _output_cb(self, outdata, frames, time_info, status):
        if status:
            log(f"output status: {status}")
        with self.lock:
            cfg = self.cfg
        sr = float(cfg.get("sampleRate", 48000))
        block_size = int(cfg.get("blockSize", frames))
        discord = self._get_frame("discord", frames, cfg["discord"].get("channels", [1, 2])) if cfg["discord"].get("enabled", True) else zeros(frames)
        xpilot = self._get_frame("xpilot", frames, cfg["xpilot"].get("channels", [1, 2])) if cfg["xpilot"].get("enabled", True) else zeros(frames)
        discord = scale(discord, db_to_gain(float(cfg["discord"].get("gainDb", 0.0))))
        xpilot = scale(xpilot, db_to_gain(float(cfg["xpilot"].get("gainDb", 0.0))))
        xpilot_level_before = rms_db(xpilot)
        auto = cfg.get("xpilotAutoLevel", {})
        if auto.get("enabled", True) and xpilot_level_before > float(auto.get("gateDb", -55.0)):
            desired = float(auto.get("targetRmsDb", -18.0)) - xpilot_level_before
            desired = max(-float(auto.get("maxCutDb", 18.0)), min(float(auto.get("maxBoostDb", 12.0)), desired))
            peak = block_peak_linear(xpilot)
            peak_ceiling = db_to_gain(float(auto.get("peakCeilingDb", -3.0)))
            if peak > 1e-9 and peak * db_to_gain(desired) > peak_ceiling:
                desired = min(desired, gain_to_db(peak_ceiling / peak))
            ms = float(auto.get("attackMs", 18.0)) if desired < self._xpilot_gain_db else float(auto.get("releaseMs", 160.0))
            self._xpilot_gain_db = one_pole(self._xpilot_gain_db, desired, ms, block_size, sr)
        else:
            self._xpilot_gain_db = one_pole(self._xpilot_gain_db, 0.0, 250.0, block_size, sr)
        xpilot = scale(xpilot, db_to_gain(self._xpilot_gain_db))
        discord = self._pan(discord, float(cfg["discord"].get("pan", -0.75)))
        xpilot = self._pan(xpilot, float(cfg["xpilot"].get("pan", 0.75)))
        duck = cfg.get("ducking", {})
        mode = duck.get("mode", "xpilot_ducks_discord")
        target_duck = 0.0
        if mode == "xpilot_ducks_discord" and rms_db(xpilot) > float(duck.get("thresholdDb", -36.0)):
            target_duck = float(duck.get("depthDb", -12.0))
        elif mode == "discord_ducks_xpilot" and rms_db(discord) > float(duck.get("thresholdDb", -36.0)):
            target_duck = float(duck.get("depthDb", -12.0))
        ms = float(duck.get("attackMs", 20.0)) if target_duck < self._duck_gain_db else float(duck.get("releaseMs", 220.0))
        self._duck_gain_db = one_pole(self._duck_gain_db, target_duck, ms, block_size, sr)
        if mode == "xpilot_ducks_discord":
            discord = scale(discord, db_to_gain(self._duck_gain_db))
        elif mode == "discord_ducks_xpilot":
            xpilot = scale(xpilot, db_to_gain(self._duck_gain_db))
        mix = scale(add_blocks(discord, xpilot), db_to_gain(float(cfg.get("masterGainDb", 0.0))))
        lim = cfg.get("limiter", {})
        if lim.get("enabled", True):
            ceiling = db_to_gain(float(lim.get("ceilingDb", -1.0)))
            peak = block_peak_linear(mix)
            if peak > ceiling and peak > 1e-9:
                self._limiter_gain = min(self._limiter_gain, ceiling / peak)
            else:
                self._limiter_gain = one_pole(self._limiter_gain, 1.0, float(lim.get("releaseMs", 120.0)), block_size, sr)
            mix = scale(mix, self._limiter_gain)
        else:
            self._limiter_gain = 1.0
        samples = array.array("f")
        for l, r in mix:
            samples.append(max(-1.0, min(1.0, l)))
            samples.append(max(-1.0, min(1.0, r)))
        outdata[:] = samples.tobytes()
        self.levels = {
            "discordRmsDb": rms_db(discord),
            "xpilotRmsDb": rms_db(xpilot),
            "outputPeakDb": peak_db(mix),
            "xpilotAutoGainDb": self._xpilot_gain_db,
            "duckGainDb": self._duck_gain_db,
            "limiterGainDb": gain_to_db(self._limiter_gain),
        }

    def state_payload(self) -> Dict[str, Any]:
        with self.lock:
            return {"version": VERSION, "state": {"ok": bool(self.running), "message": self.message, "running": bool(self.running), **self.levels}, "config": self.cfg}

ENGINE = AudioEngine()

class Handler(BaseHTTPRequestHandler):
    def _send(self, payload: Any, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(data)
    def do_OPTIONS(self) -> None:
        self._send({"ok": True})
    def do_GET(self) -> None:
        if self.path.startswith("/health"):
            self._send({"ok": True, "version": VERSION})
        elif self.path.startswith("/devices"):
            self._send({"devices": list_devices()})
        elif self.path.startswith("/state"):
            self._send(ENGINE.state_payload())
        else:
            self._send({"error": "not found"}, 404)
    def do_POST(self) -> None:
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")) or 0)
        try:
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            self._send({"error": "invalid json"}, 400)
            return
        try:
            if self.path.startswith("/config"):
                ENGINE.apply_config(data)
                self._send({"ok": True, "config": ENGINE.cfg})
            elif self.path.startswith("/command"):
                action = data.get("action")
                path = data.get("path", "")
                if action == "toggle":
                    cfg = ENGINE.update_config_path(path, toggle=True)
                elif action == "adjust":
                    cfg = ENGINE.update_config_path(path, delta=float(data.get("delta", 0)))
                elif action == "set":
                    cfg = ENGINE.update_config_path(path, value=data.get("value"))
                else:
                    self._send({"error": "unknown action"}, 400)
                    return
                self._send({"ok": True, "config": cfg})
            else:
                self._send({"error": "not found"}, 404)
        except Exception as exc:
            log(f"API error: {exc}")
            self._send({"error": str(exc)}, 500)
    def log_message(self, format: str, *args: Any) -> None:
        return

def serve() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log(f"control API listening on 127.0.0.1:{PORT}")
    server.serve_forever()

def main() -> int:
    log(f"AudioDaBitch engine {VERSION} starting")
    log(f"Python: {sys.version}")
    log(f"sounddevice: {sd.__version__}")
    threading.Thread(target=serve, daemon=True).start()
    ENGINE.start()
    while True:
        time.sleep(1)

if __name__ == "__main__":
    raise SystemExit(main())
