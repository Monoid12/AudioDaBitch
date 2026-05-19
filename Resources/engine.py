#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math, os, signal, sys, threading, time, traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Tuple
from urllib.parse import parse_qs, urlparse

EPS = 1e-12
DEFAULT_SR = 48000
DEFAULT_BLOCK = 512
CONTROL_HOST = "127.0.0.1"
CONTROL_PORT = 49342
running = True
state_lock = threading.RLock()
engine_ref = None

levels_state = {
    "running": False,
    "status": "Bereit",
    "rms": [0.0, 0.0],
    "peak": [0.0, 0.0],
    "duck_db": 0.0,
    "limiter_db": 0.0,
    "xpilot_agc_gain_db": 0.0,
    "updated_at": 0.0,
}

def db_to_lin(db: float) -> float:
    return float(10.0 ** (float(db) / 20.0))

def lin_to_db(x: float) -> float:
    return float(20.0 * math.log10(max(float(x), EPS)))

def pan_gains(pan: float) -> Tuple[float, float]:
    p = max(-1.0, min(1.0, float(pan)))
    angle = (p + 1.0) * math.pi / 4.0
    return float(math.cos(angle)), float(math.sin(angle))

def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, float(v)))

def set_status(msg: str) -> None:
    with state_lock:
        levels_state["status"] = str(msg)
        levels_state["updated_at"] = time.time()

def write_json_atomic(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def read_json(path: Path, fallback: dict | None = None) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {} if fallback is None else fallback

def hostapi_name(sd, idx: int) -> str:
    try:
        return str(sd.query_hostapis()[idx].get("name", "HostAPI"))
    except Exception:
        return "HostAPI"

def list_devices() -> int:
    try:
        import sounddevice as sd
        inputs = []
        outputs = []
        for i, dev in enumerate(sd.query_devices()):
            name = str(dev.get("name", "Unbenannt"))
            api = hostapi_name(sd, int(dev.get("hostapi", 0)))
            max_in = int(dev.get("max_input_channels", 0) or 0)
            max_out = int(dev.get("max_output_channels", 0) or 0)
            sr = float(dev.get("default_samplerate", DEFAULT_SR) or DEFAULT_SR)
            if max_in > 0:
                inputs.append({"index": i, "name": name, "channels": max_in, "hostapi": api, "default_sr": sr})
            if max_out > 0:
                outputs.append({"index": i, "name": name, "channels": max_out, "hostapi": api, "default_sr": sr})
        default = sd.default.device
        print(json.dumps({"ok": True, "inputs": inputs, "outputs": outputs, "default_input": default[0], "default_output": default[1]}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": repr(exc)}, ensure_ascii=False))
        return 1

def fit(block, frames, np):
    if block is None or getattr(block, "size", 0) == 0:
        return np.zeros(frames, dtype=np.float32)
    if block.shape[0] == frames:
        return block.astype(np.float32, copy=False)
    out = np.zeros(frames, dtype=np.float32)
    if block.shape[0] > frames:
        out[:] = block[-frames:].astype(np.float32, copy=False)
    else:
        out[: block.shape[0]] = block.astype(np.float32, copy=False)
    return out

def normalize_channels(src: dict) -> List[int]:
    if "channels" in src and isinstance(src.get("channels"), list) and src.get("channels"):
        return [max(0, int(x)) for x in src.get("channels", [0])]
    ch = max(0, int(src.get("channel", 0)))
    return [ch]

class Engine:
    def __init__(self, cfg: dict, config_path: Path, level_path: Path):
        import numpy as np
        import sounddevice as sd
        self.np = np
        self.sd = sd
        self.cfg = cfg
        self.config_path = config_path
        self.level_path = level_path
        self.config_mtime = self._mtime(config_path)
        self.sample_rate = int(cfg.get("sample_rate", DEFAULT_SR))
        self.block_size = int(cfg.get("block_size", DEFAULT_BLOCK))
        self.blocks = [np.zeros(self.block_size, dtype=np.float32), np.zeros(self.block_size, dtype=np.float32)]
        self.rms = [0.0, 0.0]
        self.peak = [0.0, 0.0]
        self.duck_gain = 1.0
        self.limiter_gain = 1.0
        self.xpilot_agc_gain_db = 0.0
        self.streams = []
        self.last_reload_check = 0.0

    def _mtime(self, path: Path) -> float:
        try:
            return path.stat().st_mtime
        except Exception:
            return 0.0

    def reload_config_if_needed(self, force: bool = False) -> None:
        now = time.monotonic()
        if not force and now - self.last_reload_check < 0.10:
            return
        self.last_reload_check = now
        mt = self._mtime(self.config_path)
        if force or (mt and mt != self.config_mtime):
            cfg = read_json(self.config_path, self.cfg)
            if isinstance(cfg, dict) and cfg.get("inputs"):
                self.cfg = cfg
                self.config_mtime = mt

    def save_config(self) -> None:
        write_json_atomic(self.config_path, self.cfg)
        self.config_mtime = self._mtime(self.config_path)

    def apply_patch(self, patch: dict) -> dict:
        with state_lock:
            cfg = json.loads(json.dumps(self.cfg))
            for key, value in patch.items():
                if key == "ducking":
                    cfg["ducking"] = bool(value)
                elif key == "xpilot_agc_enabled":
                    cfg.setdefault("xpilot_agc", {})["enabled"] = bool(value)
                elif key == "xpilot_gain_delta_db":
                    cfg["inputs"][1]["gain_db"] = clamp(float(cfg["inputs"][1].get("gain_db", 0.0)) + float(value), -24, 24)
                elif key == "master_gain_delta_db":
                    cfg["master_gain_db"] = clamp(float(cfg.get("master_gain_db", 0.0)) + float(value), -24, 12)
                elif key == "duck_depth_delta_db":
                    cfg["duck_depth_db"] = clamp(float(cfg.get("duck_depth_db", 18.0)) + float(value), 0, 40)
                elif key == "xpilot_target_delta_db":
                    agc = cfg.setdefault("xpilot_agc", {})
                    agc["target_db"] = clamp(float(agc.get("target_db", -21.0)) + float(value), -32, -12)
                elif key in ["xpilot_gain_db", "discord_gain_db"]:
                    idx = 1 if key.startswith("xpilot") else 0
                    cfg["inputs"][idx]["gain_db"] = clamp(float(value), -24, 24)
                elif key in ["master_gain_db", "duck_depth_db", "threshold_db"]:
                    cfg[key] = float(value)
            self.cfg = cfg
            self.save_config()
            return cfg

    def start(self):
        cfg = self.cfg
        inputs = cfg.get("inputs", [])[:2]
        bydev: Dict[int, List[Tuple[int, List[int]]]] = {}
        for bus, src in enumerate(inputs):
            dev = src.get("device_index")
            if dev is None:
                raise RuntimeError("Input fuer %s fehlt." % src.get("name", bus))
            chans = normalize_channels(src)
            bydev.setdefault(int(dev), []).append((bus, chans))
        if cfg.get("output_index") is None:
            raise RuntimeError("Output fehlt.")
        for dev, maps in bydev.items():
            channels = max(max(chs) for _, chs in maps) + 1
            stream = self.sd.InputStream(device=dev, samplerate=self.sample_rate, blocksize=self.block_size, channels=channels, dtype="float32", latency="low", callback=self.input_callback(dev, maps))
            stream.start()
            self.streams.append(stream)
        out = self.sd.OutputStream(device=int(cfg.get("output_index")), samplerate=self.sample_rate, blocksize=self.block_size, channels=2, dtype="float32", latency="low", callback=self.output_callback)
        out.start()
        self.streams.append(out)
        with state_lock:
            levels_state["running"] = True
            levels_state["status"] = "Audio laeuft"
            levels_state["updated_at"] = time.time()

    def stop(self):
        for s in list(self.streams):
            try: s.stop()
            except Exception: pass
            try: s.close()
            except Exception: pass
        self.streams = []
        with state_lock:
            levels_state["running"] = False
            levels_state["status"] = "Gestoppt"
            levels_state["updated_at"] = time.time()

    def input_callback(self, dev, maps):
        def cb(indata, frames, time_info, status):
            if status:
                set_status("Input %s: %s" % (dev, status))
            with state_lock:
                for bus, chans in maps:
                    available = [ch for ch in chans if ch < indata.shape[1]]
                    if available:
                        data = indata[:, available].astype(self.np.float32, copy=True)
                        block = data.mean(axis=1) if data.ndim == 2 else data
                    else:
                        block = self.np.zeros(frames, dtype=self.np.float32)
                    self.blocks[bus] = block
                    pk = float(self.np.max(self.np.abs(block))) if block.size else 0.0
                    rms = float(self.np.sqrt(self.np.mean(self.np.square(block)))) if block.size else 0.0
                    self.peak[bus] = max(pk, self.peak[bus] * 0.86)
                    self.rms[bus] = 0.78 * self.rms[bus] + 0.22 * rms
                    levels_state["rms"] = list(self.rms)
                    levels_state["peak"] = list(self.peak)
                    levels_state["updated_at"] = time.time()
        return cb

    def apply_xpilot_agc(self, mono, frames: int, cfg: dict):
        np = self.np
        agc = cfg.get("xpilot_agc", {}) or {}
        if not bool(agc.get("enabled", True)):
            self.xpilot_agc_gain_db += (0.0 - self.xpilot_agc_gain_db) * 0.02
            return mono * db_to_lin(self.xpilot_agc_gain_db)
        rms = float(np.sqrt(np.mean(np.square(mono)))) if mono.size else 0.0
        peak = float(np.max(np.abs(mono))) if mono.size else 0.0
        rms_db = lin_to_db(rms)
        peak_db = lin_to_db(peak)
        target_db = float(agc.get("target_db", -21.0))
        gate_db = float(agc.get("gate_db", -55.0))
        min_gain = float(agc.get("min_gain_db", -14.0))
        max_gain = float(agc.get("max_gain_db", 14.0))
        peak_target_db = float(agc.get("peak_guard_db", -3.0))
        if rms_db < gate_db:
            desired = 0.0
            tau_ms = float(agc.get("idle_release_ms", 900.0))
        else:
            desired = clamp(target_db - rms_db, min_gain, max_gain)
            if peak_db + desired > peak_target_db:
                desired = min(desired, peak_target_db - peak_db)
            tau_ms = float(agc.get("fast_down_ms", 18.0)) if desired < self.xpilot_agc_gain_db else float(agc.get("fast_up_ms", 130.0))
        dt = max(frames / max(float(self.sample_rate), 1.0), 0.0001)
        coeff = math.exp(-dt / max(tau_ms / 1000.0, 0.001))
        self.xpilot_agc_gain_db = float(desired + (self.xpilot_agc_gain_db - desired) * coeff)
        with state_lock:
            levels_state["xpilot_agc_gain_db"] = self.xpilot_agc_gain_db
        return mono * db_to_lin(self.xpilot_agc_gain_db)

    def output_callback(self, outdata, frames, time_info, status):
        np = self.np
        if status:
            set_status("Output: %s" % status)
        try:
            self.reload_config_if_needed()
            with state_lock:
                cfg = json.loads(json.dumps(self.cfg))
                blocks = [fit(self.blocks[i], frames, np).copy() for i in range(2)]
                old_duck = float(self.duck_gain)
                old_lim = float(self.limiter_gain)
            trig = int(cfg.get("trigger", 1))
            trig = 1 if trig != 0 else 0
            ducking = bool(cfg.get("ducking", True))
            target_duck = 1.0
            if ducking:
                rms = float(np.sqrt(np.mean(np.square(blocks[trig])))) if blocks[trig].size else 0.0
                if lin_to_db(rms) >= float(cfg.get("threshold_db", -35.0)):
                    target_duck = db_to_lin(-abs(float(cfg.get("duck_depth_db", 18.0))))
            dt = max(frames / max(float(self.sample_rate), 1.0), 0.0001)
            tau_ms = float(cfg.get("attack_ms", 20.0)) if target_duck < old_duck else float(cfg.get("release_ms", 350.0))
            coeff = math.exp(-dt / max(tau_ms / 1000.0, 0.001))
            duck_gain = float(target_duck + (old_duck - target_duck) * coeff)
            mix = np.zeros((frames, 2), dtype=np.float32)
            for i, src in enumerate(cfg.get("inputs", [])[:2]):
                mono = blocks[i] * db_to_lin(float(src.get("gain_db", 0.0)))
                if i == 1:
                    mono = self.apply_xpilot_agc(mono, frames, cfg)
                if ducking and i != trig:
                    mono = mono * duck_gain
                l, r = pan_gains(float(src.get("pan", -1.0 if i == 0 else 1.0)))
                mix[:, 0] += mono * l
                mix[:, 1] += mono * r
            mix *= db_to_lin(float(cfg.get("master_gain_db", 0.0)))
            ceiling = db_to_lin(float(cfg.get("limiter_ceiling_db", -1.0)))
            pk = float(np.max(np.abs(mix))) if mix.size else 0.0
            target_lim = min(1.0, ceiling / pk) if pk > ceiling and pk > EPS else 1.0
            if target_lim < old_lim:
                lim_gain = target_lim
            else:
                lim_gain = float(target_lim + (old_lim - target_lim) * math.exp(-dt / 0.08))
                lim_gain = min(1.0, lim_gain)
            mix *= lim_gain
            outdata[:] = np.clip(mix, -1.0, 1.0)
            with state_lock:
                self.duck_gain = duck_gain
                self.limiter_gain = lim_gain
                levels_state["duck_db"] = lin_to_db(duck_gain)
                levels_state["limiter_db"] = lin_to_db(lim_gain)
                levels_state["updated_at"] = time.time()
        except Exception as exc:
            set_status("Audio Callback Fehler: %r" % exc)
            outdata[:] = self.np.zeros((frames, 2), dtype=self.np.float32)

class ControlHandler(BaseHTTPRequestHandler):
    server_version = "AudioDaBitchControl/0.5"
    def log_message(self, fmt, *args):
        return
    def _send(self, code: int, data: Any) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "http://127.0.0.1")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        global engine_ref
        parsed = urlparse(self.path)
        if parsed.path == "/api/status":
            with state_lock:
                data = dict(levels_state)
                data["config"] = engine_ref.cfg if engine_ref else None
            self._send(200, {"ok": True, **data})
            return
        if parsed.path == "/api/config":
            self._send(200, {"ok": True, "config": engine_ref.cfg if engine_ref else None})
            return
        if parsed.path == "/api/adjust":
            qs = parse_qs(parsed.query)
            patch = {}
            param = qs.get("param", [""])[0]
            delta = float(qs.get("delta", ["0"])[0] or 0)
            value = qs.get("value", [None])[0]
            if param == "xpilot_gain": patch["xpilot_gain_delta_db"] = delta
            elif param == "master_gain": patch["master_gain_delta_db"] = delta
            elif param == "duck_depth": patch["duck_depth_delta_db"] = delta
            elif param == "xpilot_target": patch["xpilot_target_delta_db"] = delta
            elif param == "ducking": patch["ducking"] = str(value).lower() in ["1", "true", "yes", "on"]
            elif param == "xpilot_agc": patch["xpilot_agc_enabled"] = str(value).lower() in ["1", "true", "yes", "on"]
            if engine_ref and patch:
                cfg = engine_ref.apply_patch(patch)
                self._send(200, {"ok": True, "config": cfg})
            else:
                self._send(400, {"ok": False, "error": "unknown parameter"})
            return
        self._send(404, {"ok": False, "error": "not found"})
    def do_POST(self):
        global engine_ref
        if self.path not in ["/api/adjust", "/api/config"]:
            self._send(404, {"ok": False, "error": "not found"})
            return
        length = int(self.headers.get("content-length", "0") or 0)
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except Exception:
            data = {}
        if not engine_ref:
            self._send(503, {"ok": False, "error": "engine not running"})
            return
        cfg = engine_ref.apply_patch(data)
        self._send(200, {"ok": True, "config": cfg})

def start_control_server():
    try:
        server = ThreadingHTTPServer((CONTROL_HOST, CONTROL_PORT), ControlHandler)
        th = threading.Thread(target=server.serve_forever, daemon=True)
        th.start()
        return server
    except Exception as exc:
        set_status("Control API nicht gestartet: %r" % exc)
        return None

def writer_thread(path: Path):
    while running:
        with state_lock:
            data = dict(levels_state)
        try:
            write_json_atomic(path, data)
        except Exception:
            pass
        time.sleep(0.10)

def run_engine(config_path: Path, level_path: Path, pid_path: Path) -> int:
    global running, engine_ref
    def handle(sig, frame):
        global running
        running = False
    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(str(os.getpid()), encoding="utf-8")
    server = None
    try:
        cfg = read_json(config_path, {})
        th = threading.Thread(target=writer_thread, args=(level_path,), daemon=True)
        th.start()
        eng = Engine(cfg, config_path, level_path)
        engine_ref = eng
        server = start_control_server()
        eng.start()
        while running:
            time.sleep(0.1)
        eng.stop()
        return 0
    except Exception as exc:
        with state_lock:
            levels_state["running"] = False
            levels_state["status"] = "Fehler: %r" % exc
            levels_state["updated_at"] = time.time()
        try:
            write_json_atomic(level_path, dict(levels_state))
        except Exception:
            pass
        traceback.print_exc()
        return 1
    finally:
        if server:
            try: server.shutdown()
            except Exception: pass
        try:
            pid_path.unlink()
        except Exception:
            pass

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list-devices", action="store_true")
    ap.add_argument("--run", nargs=3, metavar=("CONFIG", "LEVELS", "PID"))
    args = ap.parse_args()
    if args.list_devices:
        return list_devices()
    if args.run:
        return run_engine(Path(args.run[0]), Path(args.run[1]), Path(args.run[2]))
    print("usage: engine.py --list-devices | --run CONFIG LEVELS PID", file=sys.stderr)
    return 2
if __name__ == "__main__":
    raise SystemExit(main())
