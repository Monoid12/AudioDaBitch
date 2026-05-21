#!/usr/bin/env python3
# AudioDaBitch Engine 0.5.15
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
from typing import Any, Dict, List, Tuple

ENGINE_VERSION = "0.5.15"
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


def meter_db(samples: Any) -> float:
    if not samples:
        return -120.0
    peak = max(abs(x) for x in samples)
    return gain_to_db(peak)


def audio_levels(samples: Any) -> Tuple[float, float]:
    if not samples:
        return -120.0, -120.0
    peak = 0.0
    total = 0.0
    count = 0
    for sample in samples:
        value = float(sample)
        magnitude = abs(value)
        if magnitude > peak:
            peak = magnitude
        total += value * value
        count += 1
    if count <= 0:
        return -120.0, -120.0
    return gain_to_db(peak), gain_to_db(math.sqrt(total / count))


def smoothing_alpha(block_ms: float, tau_ms: float) -> float:
    tau = max(1.0, tau_ms)
    return max(0.0, min(1.0, 1.0 - math.exp(-max(1.0, block_ms) / tau)))


def default_config() -> Dict[str, Any]:
    return {
        "configVersion": ENGINE_VERSION,
        "discordInput": None,
        "discordInputName": "",
        "xpilotInput": None,
        "xpilotInputName": "",
        "outputDevice": None,
        "outputDeviceName": "",
        "discordGainDb": 0.0,
        "xpilotGainDb": 0.0,
        "masterGainDb": 0.0,
        "discordPan": -1.0,
        "xpilotPan": 1.0,
        "duckingEnabled": True,
        "duckingMode": "xpilot_ducks_discord",
        "duckDepthDb": -24.0,
        "thresholdDb": -46.0,
        "duckAttackMs": 4.0,
        "duckReleaseMs": 180.0,
        "limiterCeilingDb": -1.0,
        "discordLevelerEnabled": True,
        "discordLevelerTargetDb": -20.0,
        "discordLevelerMaxBoostDb": 15.0,
        "discordLevelerMaxCutDb": -24.0,
        "discordLevelerSpeed": 65.0,
        "xpilotLevelerEnabled": True,
        "xpilotLevelerPreset": "standard",
        "xpilotLevelerTargetDb": -20.0,
        "xpilotLevelerMaxBoostDb": 15.0,
        "xpilotLevelerMaxCutDb": -24.0,
        "xpilotLevelerSpeed": 70.0,
        "bufferMaxMs": 120.0,
        "bufferTargetMs": 45.0,
        "safeMode": True,
        "sampleRate": 48000,
        "blockSize": 1024,
        "latency": "high",
    }

CONFIG_LOCK = threading.RLock()
CONFIG = default_config()


def migrate_config_if_needed(existing: Dict[str, Any]) -> None:
    if str(existing.get("configVersion", "")) == ENGINE_VERSION:
        return

    def replace_old(key: str, old: float, new: float) -> None:
        try:
            if key not in existing or abs(float(existing.get(key, old)) - old) < 0.001:
                CONFIG[key] = new
        except Exception:
            CONFIG[key] = new

    replace_old("duckDepthDb", -12.0, -24.0)
    replace_old("thresholdDb", -32.0, -46.0)
    replace_old("discordLevelerTargetDb", -21.0, -20.0)
    replace_old("discordLevelerMaxBoostDb", 12.0, 15.0)
    replace_old("discordLevelerMaxCutDb", -18.0, -24.0)
    replace_old("discordLevelerSpeed", 45.0, 65.0)
    replace_old("xpilotLevelerTargetDb", -21.0, -20.0)
    replace_old("xpilotLevelerMaxBoostDb", 12.0, 15.0)
    replace_old("xpilotLevelerMaxCutDb", -18.0, -24.0)
    replace_old("xpilotLevelerSpeed", 45.0, 70.0)
    CONFIG["duckAttackMs"] = float(existing.get("duckAttackMs", 4.0))
    CONFIG["duckReleaseMs"] = float(existing.get("duckReleaseMs", 180.0))
    CONFIG["bufferMaxMs"] = float(existing.get("bufferMaxMs", 120.0))
    CONFIG["bufferTargetMs"] = float(existing.get("bufferTargetMs", 45.0))
    CONFIG["configVersion"] = ENGINE_VERSION


def normalized_device_name(name: Any) -> str:
    return " ".join(str(name or "").casefold().split())


def resolve_device_id(device_id: Any, device_name: Any, direction: str) -> Any:
    devices = list_devices()
    key = "inputs" if direction == "input" else "outputs"
    candidates = devices.get(key, [])
    try:
        wanted_id = None if device_id is None else int(device_id)
    except Exception:
        wanted_id = None
    if wanted_id is not None:
        for item in candidates:
            if int(item.get("id", -1)) == wanted_id:
                return wanted_id
    wanted_name = normalized_device_name(device_name)
    if wanted_name:
        for item in candidates:
            if normalized_device_name(item.get("name", "")) == wanted_name:
                return int(item["id"])
    return device_id


def load_config() -> None:
    global CONFIG
    with CONFIG_LOCK:
        CONFIG = default_config()
        existing: Dict[str, Any] = {}
        if CONFIG_FILE.exists():
            try:
                data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    existing = data
                    CONFIG.update(data)
            except Exception as e:
                log(f"load config failed: {e!r}")
        migrate_config_if_needed(existing)
        if existing and str(existing.get("configVersion", "")) != ENGINE_VERSION:
            save_config()


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
    def __init__(self, sample_rate: int = 48000, channels: int = 2, max_ms: float = 120.0, target_ms: float = 45.0) -> None:
        self.lock = threading.Lock()
        self.channels = channels
        self.sample_rate = sample_rate
        self.max_ms = max_ms
        self.target_ms = target_ms
        self.max_samples = self._ms_to_samples(max_ms)
        self.target_samples = self._ms_to_samples(target_ms)
        self.chunks: deque[Any] = deque()
        self.samples = 0
        self.underruns = 0
        self.overruns = 0
        self.dropped_samples = 0
        self.high_water_samples = 0

    def _ms_to_samples(self, ms: float) -> int:
        return max(self.channels * 2, int((self.sample_rate * self.channels * max(1.0, ms)) / 1000.0))

    def configure(self, sample_rate: int, channels: int = 2, max_ms: float = 120.0, target_ms: float = 45.0) -> None:
        with self.lock:
            self.sample_rate = max(8000, int(sample_rate))
            self.channels = max(1, int(channels))
            self.max_ms = max(30.0, float(max_ms))
            self.target_ms = max(10.0, min(float(target_ms), self.max_ms))
            self.max_samples = self._ms_to_samples(self.max_ms)
            self.target_samples = self._ms_to_samples(self.target_ms)
            if self.samples > self.max_samples:
                self._drop_unlocked(self.samples - self.target_samples)

    def clear(self) -> None:
        with self.lock:
            self.chunks.clear()
            self.samples = 0
            self.underruns = 0
            self.overruns = 0
            self.dropped_samples = 0
            self.high_water_samples = 0

    def _drop_unlocked(self, count: int) -> None:
        remaining = max(0, count)
        dropped = 0
        while remaining > 0 and self.chunks:
            chunk = self.chunks[0]
            n = len(chunk)
            if n <= remaining:
                self.chunks.popleft()
                self.samples -= n
                dropped += n
                remaining -= n
            else:
                del chunk[:remaining]
                self.samples -= remaining
                dropped += remaining
                remaining = 0
        self.dropped_samples += dropped

    def append(self, values: Any) -> None:
        if not values:
            return
        with self.lock:
            self.chunks.append(values)
            self.samples += len(values)
            if self.samples > self.high_water_samples:
                self.high_water_samples = self.samples
            if self.samples > self.max_samples:
                self.overruns += 1
                self._drop_unlocked(self.samples - self.target_samples)

    def read(self, count: int) -> Any:
        out = array.array("f")
        remaining = count
        with self.lock:
            while remaining > 0 and self.chunks:
                chunk = self.chunks[0]
                n = len(chunk)
                if n <= remaining:
                    out.extend(chunk)
                    self.chunks.popleft()
                    self.samples -= n
                    remaining -= n
                else:
                    out.extend(chunk[:remaining])
                    del chunk[:remaining]
                    self.samples -= remaining
                    remaining = 0
            if remaining > 0:
                self.underruns += 1
        if remaining > 0:
            out.extend(array.array("f", [0.0]) * remaining)
        return out

    def diagnostics(self) -> Dict[str, Any]:
        with self.lock:
            denom = max(1, self.sample_rate * self.channels)
            return {
                "queuedSamples": self.samples,
                "queuedMs": round((self.samples / denom) * 1000.0, 1),
                "maxMs": round(self.max_ms, 1),
                "targetMs": round(self.target_ms, 1),
                "underruns": self.underruns,
                "overruns": self.overruns,
                "droppedSamples": self.dropped_samples,
                "droppedMs": round((self.dropped_samples / denom) * 1000.0, 1),
                "highWaterMs": round((self.high_water_samples / denom) * 1000.0, 1),
            }


class AudioEngine:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.running = False
        self.streams: List[Any] = []
        self.buffers: Dict[str, RingBuffer] = {"discord": RingBuffer(), "xpilot": RingBuffer()}
        self.meters = {"discord": -120.0, "xpilot": -120.0, "output": -120.0}
        self.rms_meters = {"discord": -120.0, "xpilot": -120.0}
        self.activity_gains = {"discord": 0.0, "xpilot": 0.0}
        self.leveler_gains = {"discord": 1.0, "xpilot": 1.0}
        self.duck_gains = {"discord": 1.0, "xpilot": 1.0}
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
            self.activity_gains = {"discord": 0.0, "xpilot": 0.0}
            self.duck_gains = {"discord": 1.0, "xpilot": 1.0}
            log("audio stopped")

    def _input_cb(self, source: str):
        def cb(indata, frames, time_info, status):
            try:
                samples = array.array("f")
                try:
                    samples.frombytes(indata)
                except TypeError:
                    samples.frombytes(bytes(indata))
                peak_db, rms_db = audio_levels(samples)
                self.meters[source] = peak_db
                self.rms_meters[source] = rms_db
                peak_gain = db_to_gain(peak_db)
                current = self.activity_gains.get(source, 0.0)
                self.activity_gains[source] = peak_gain if peak_gain > current else current * 0.82
                self.buffers[source].append(samples)
            except Exception:
                self.callback_errors += 1
        return cb

    def _get_stereo(self, source: str, frames: int) -> Any:
        return self.buffers[source].read(frames * 2)

    def _pan_gains(self, pan: float) -> Tuple[float, float]:
        pan = max(-1.0, min(1.0, float(pan)))
        angle = (pan + 1.0) * math.pi / 4.0
        return math.cos(angle), math.sin(angle)

    def _leveler_gain(self, source: str, cfg: Dict[str, Any], frames: int) -> float:
        enabled_key = f"{source}LevelerEnabled"
        if not cfg.get(enabled_key, True):
            current = self.leveler_gains.get(source, 1.0)
            self.leveler_gains[source] = current + 0.04 * (1.0 - current)
            return self.leveler_gains[source]
        source_db = self.rms_meters.get(source, -120.0)
        current = self.leveler_gains.get(source, 1.0)
        if source_db <= -56.0:
            desired = 1.0
        else:
            target = float(cfg.get(f"{source}LevelerTargetDb", -20.0))
            max_boost = max(0.0, float(cfg.get(f"{source}LevelerMaxBoostDb", 15.0)))
            max_cut = min(0.0, float(cfg.get(f"{source}LevelerMaxCutDb", -24.0)))
            desired_db = max(max_cut, min(max_boost, target - source_db))
            desired = db_to_gain(desired_db)
        speed = max(1.0, min(100.0, float(cfg.get(f"{source}LevelerSpeed", 65.0))))
        block_ms = (frames / max(1, self.sample_rate)) * 1000.0
        cut_tau = 35.0 + (100.0 - speed) * 2.0
        boost_tau = 130.0 + (100.0 - speed) * 6.0
        alpha = smoothing_alpha(block_ms, cut_tau if desired < current else boost_tau)
        current = current + alpha * (desired - current)
        self.leveler_gains[source] = current
        return current

    def _ducking_gain(self, target: str, trigger: str, cfg: Dict[str, Any], frames: int, force_release: bool = False) -> float:
        current = self.duck_gains.get(target, 1.0)
        if force_release or not cfg.get("duckingEnabled", True):
            desired = 1.0
        else:
            threshold = float(cfg.get("thresholdDb", -46.0))
            trigger_db = gain_to_db(self.activity_gains.get(trigger, 0.0))
            desired = db_to_gain(float(cfg.get("duckDepthDb", -24.0))) if trigger_db > threshold else 1.0
        block_ms = (frames / max(1, self.sample_rate)) * 1000.0
        attack_ms = float(cfg.get("duckAttackMs", 4.0))
        release_ms = float(cfg.get("duckReleaseMs", 180.0))
        alpha = smoothing_alpha(block_ms, attack_ms if desired < current else release_ms)
        current = current + alpha * (desired - current)
        self.duck_gains[target] = current
        return current

    def _output_cb(self, outdata, frames, time_info, status):
        try:
            with CONFIG_LOCK:
                cfg = dict(CONFIG)
            d = self._get_stereo("discord", frames)
            x = self._get_stereo("xpilot", frames)
            d_lg, d_rg = self._pan_gains(float(cfg.get("discordPan", -1.0)))
            x_lg, x_rg = self._pan_gains(float(cfg.get("xpilotPan", 1.0)))
            dg = db_to_gain(float(cfg.get("discordGainDb", 0.0)))
            xg = db_to_gain(float(cfg.get("xpilotGainDb", 0.0)))
            mg = db_to_gain(float(cfg.get("masterGainDb", 0.0)))
            ceiling = db_to_gain(float(cfg.get("limiterCeilingDb", -1.0)))

            if cfg.get("discordLevelerEnabled", True):
                dg *= self._leveler_gain("discord", cfg, frames)
            else:
                self._leveler_gain("discord", cfg, frames)
            if cfg.get("xpilotLevelerEnabled", True):
                xg *= self._leveler_gain("xpilot", cfg, frames)
            else:
                self._leveler_gain("xpilot", cfg, frames)

            mode = cfg.get("duckingMode", "xpilot_ducks_discord")
            if mode == "xpilot_ducks_discord":
                dg *= self._ducking_gain("discord", "xpilot", cfg, frames)
                self._ducking_gain("xpilot", "discord", cfg, frames, force_release=True)
            elif mode == "discord_ducks_xpilot":
                xg *= self._ducking_gain("xpilot", "discord", cfg, frames)
                self._ducking_gain("discord", "xpilot", cfg, frames, force_release=True)
            else:
                self._ducking_gain("discord", "xpilot", cfg, frames, force_release=True)
                self._ducking_gain("xpilot", "discord", cfg, frames, force_release=True)

            mix = array.array("f", [0.0]) * (frames * 2)
            peak = 0.0
            for i in range(0, frames * 2, 2):
                d_mono = 0.5 * (d[i] + d[i + 1])
                x_mono = 0.5 * (x[i] + x[i + 1])
                left = ((d_mono * d_lg * dg) + (x_mono * x_lg * xg)) * mg
                right = ((d_mono * d_rg * dg) + (x_mono * x_rg * xg)) * mg
                if abs(left) > ceiling and abs(left) > 1e-9:
                    left = ceiling if left > 0 else -ceiling
                if abs(right) > ceiling and abs(right) > 1e-9:
                    right = ceiling if right > 0 else -ceiling
                left = max(-1.0, min(1.0, left))
                right = max(-1.0, min(1.0, right))
                peak = max(peak, abs(left), abs(right))
                mix[i] = left
                mix[i + 1] = right
            self.meters["output"] = gain_to_db(peak)
            outdata[:] = mix.tobytes()
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
            cfg["discordInput"] = resolve_device_id(cfg.get("discordInput"), cfg.get("discordInputName"), "input")
            cfg["xpilotInput"] = resolve_device_id(cfg.get("xpilotInput"), cfg.get("xpilotInputName"), "input")
            cfg["outputDevice"] = resolve_device_id(cfg.get("outputDevice"), cfg.get("outputDeviceName"), "output")
            with CONFIG_LOCK:
                CONFIG.update({"discordInput": cfg.get("discordInput"), "xpilotInput": cfg.get("xpilotInput"), "outputDevice": cfg.get("outputDevice")})
                save_config()
            out_dev = cfg.get("outputDevice")
            if out_dev is None:
                return {"ok": False, "error": "Please choose an output device."}
            self.sample_rate = int(cfg.get("sampleRate", 48000) or 48000)
            self.block_size = int(cfg.get("blockSize", 1024) or 1024)
            if cfg.get("safeMode", True):
                self.block_size = max(self.block_size, 1024)
                self.latency = "high"
            else:
                self.block_size = max(256, self.block_size)
                self.latency = cfg.get("latency", "low") or "low"
            buffer_max_ms = float(cfg.get("bufferMaxMs", 120.0))
            buffer_target_ms = float(cfg.get("bufferTargetMs", 45.0))
            for buffer in self.buffers.values():
                buffer.configure(self.sample_rate, channels=2, max_ms=buffer_max_ms, target_ms=buffer_target_ms)
                buffer.clear()
            self.rms_meters = {"discord": -120.0, "xpilot": -120.0}
            self.activity_gains = {"discord": 0.0, "xpilot": 0.0}
            self.leveler_gains = {"discord": 1.0, "xpilot": 1.0}
            self.duck_gains = {"discord": 1.0, "xpilot": 1.0}
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
        return {
            "ok": True,
            "version": ENGINE_VERSION,
            "running": self.running,
            "meters": dict(self.meters),
            "rmsMeters": dict(self.rms_meters),
            "levelerGainDb": gain_to_db(self.leveler_gains.get("xpilot", 1.0)),
            "discordLevelerGainDb": gain_to_db(self.leveler_gains.get("discord", 1.0)),
            "xpilotLevelerGainDb": gain_to_db(self.leveler_gains.get("xpilot", 1.0)),
            "discordDuckGainDb": gain_to_db(self.duck_gains.get("discord", 1.0)),
            "xpilotDuckGainDb": gain_to_db(self.duck_gains.get("xpilot", 1.0)),
            "diagnostics": self.diagnostics(),
        }

    def diagnostics(self) -> Dict[str, Any]:
        return {
            "sampleRate": self.sample_rate,
            "blockSize": self.block_size,
            "latency": str(self.latency),
            "callbackErrors": self.callback_errors,
            "discord": self.buffers["discord"].diagnostics(),
            "xpilot": self.buffers["xpilot"].diagnostics(),
            "lastError": self.last_error,
        }

ENGINE = AudioEngine()
HTTPD: ThreadingHTTPServer | None = None


def request_shutdown() -> None:
    global HTTPD
    log("shutdown requested")
    if HTTPD is not None:
        threading.Thread(target=HTTPD.shutdown, daemon=True).start()


def handle_signal(signum, frame) -> None:
    log(f"signal {signum} received")
    request_shutdown()


signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)


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
            threading.Thread(target=lambda: (time.sleep(0.2), request_shutdown()), daemon=True).start()
        else:
            self._send({"ok": False, "error": "not found"}, 404)


def main() -> int:
    global HTTPD
    save_pid()
    atexit.register(cleanup_pid)
    load_config()
    log(f"AudioDaBitch engine {ENGINE_VERSION} starting pid={os.getpid()} python={sys.executable}")
    try:
        HTTPD = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        HTTPD.serve_forever(poll_interval=0.5)
    except OSError as e:
        log(f"server failed: {e!r}")
        return 2
    finally:
        if HTTPD is not None:
            HTTPD.server_close()
        ENGINE.stop()
        cleanup_pid()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
