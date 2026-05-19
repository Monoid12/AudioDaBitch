#!/usr/bin/env python3
import atexit, json, math, os, queue, signal, sys, threading, time
from array import array
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ENGINE_VERSION = "0.5.4"
PORT = 49372
APP_SUPPORT = Path.home() / "Library" / "Application Support" / "AudioDaBitch"
LOG_DIR = Path.home() / "Library" / "Logs" / "AudioDaBitch"
PID_FILE = APP_SUPPORT / "engine.pid"
CONFIG_FILE = APP_SUPPORT / "config.json"
LOG_FILE = LOG_DIR / "engine.log"

try:
    import sounddevice as sd
except Exception as e:
    sd = None
    SD_IMPORT_ERROR = repr(e)
else:
    SD_IMPORT_ERROR = ""

DEFAULT_CONFIG = {
    "discordInput": None,
    "xpilotInput": None,
    "outputDevice": None,
    "discordGain": 0.0,
    "xpilotGain": 0.0,
    "discordPan": -0.8,
    "xpilotPan": 0.8,
    "masterGain": 0.0,
    "duckDepth": -12.0,
    "targetDb": -21.0,
    "gateDb": -55.0,
    "fastDownMs": 18.0,
    "running": False,
}

APP_SUPPORT.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    try:
        with LOG_FILE.open("a") as f:
            f.write(f"{ts} {msg}\n")
    except Exception:
        pass

config = DEFAULT_CONFIG.copy()
meters = {"discordDb": -120.0, "xpilotDb": -120.0, "outputDb": -120.0, "engineVersion": ENGINE_VERSION}
streams = []
queues = {"discord": queue.Queue(maxsize=8), "xpilot": queue.Queue(maxsize=8)}
lock = threading.RLock()

def save_pid():
    PID_FILE.write_text(str(os.getpid()))

def cleanup_pid():
    try:
        if PID_FILE.exists() and PID_FILE.read_text().strip() == str(os.getpid()):
            PID_FILE.unlink()
    except Exception:
        pass

def load_config():
    global config
    if CONFIG_FILE.exists():
        try:
            data = json.loads(CONFIG_FILE.read_text())
            if isinstance(data, dict):
                config.update(data)
        except Exception as e:
            log(f"config load failed: {e!r}")

def save_config():
    try:
        CONFIG_FILE.write_text(json.dumps(config, indent=2))
    except Exception as e:
        log(f"config save failed: {e!r}")

def db_to_gain(db):
    return 10 ** (float(db) / 20.0)

def peak_db(vals):
    if not vals:
        return -120.0
    m = max(abs(x) for x in vals)
    if m <= 1e-8:
        return -120.0
    return max(-120.0, min(12.0, 20 * math.log10(m)))

def pan_pair(sample, pan):
    pan = max(-1.0, min(1.0, float(pan)))
    angle = (pan + 1.0) * math.pi / 4.0
    return sample * math.cos(angle), sample * math.sin(angle)

def frames_from_bytes(data):
    a = array('f')
    a.frombytes(bytes(data))
    return a

def bytes_from_frames(a):
    return a.tobytes()

def get_devices():
    inputs, outputs = [], []
    if sd is None:
        return {"inputs": inputs, "outputs": outputs, "error": SD_IMPORT_ERROR}
    try:
        for idx, d in enumerate(sd.query_devices()):
            name = d.get("name", f"Device {idx}")
            hostapi = d.get("hostapi", 0)
            item = {"id": str(idx), "index": idx, "name": name, "label": f"{name}", "hostapi": hostapi}
            if int(d.get("max_input_channels", 0)) > 0:
                inputs.append(item | {"channels": int(d.get("max_input_channels", 0))})
            if int(d.get("max_output_channels", 0)) > 0:
                outputs.append(item | {"channels": int(d.get("max_output_channels", 0))})
    except Exception as e:
        return {"inputs": inputs, "outputs": outputs, "error": repr(e)}
    return {"inputs": inputs, "outputs": outputs, "error": ""}

def pick_device(value):
    if value in (None, "", "none"):
        return None
    try:
        return int(value)
    except Exception:
        return None

def make_input_cb(name, channels):
    def cb(indata, frames, time_info, status):
        try:
            a = frames_from_bytes(indata)
            while len(a) < frames * channels:
                a.append(0.0)
            try:
                queues[name].put_nowait((a, channels, frames))
            except queue.Full:
                try:
                    queues[name].get_nowait()
                except Exception:
                    pass
                queues[name].put_nowait((a, channels, frames))
        except Exception as e:
            log(f"input cb {name} failed: {e!r}")
    return cb

def get_stereo(name, frames):
    try:
        a, channels, got_frames = queues[name].get_nowait()
    except Exception:
        return array('f', [0.0] * (frames * 2))
    out = array('f', [0.0] * (frames * 2))
    n = min(frames, got_frames)
    for i in range(n):
        if channels >= 2:
            l = a[i * channels]
            r = a[i * channels + 1]
        elif channels == 1:
            l = r = a[i]
        else:
            l = r = 0.0
        out[i*2] = l
        out[i*2+1] = r
    return out

def output_cb(outdata, frames, time_info, status):
    with lock:
        cfg = config.copy()
    discord = get_stereo("discord", frames)
    xpilot = get_stereo("xpilot", frames)
    dg = db_to_gain(cfg.get("discordGain", 0.0))
    xg = db_to_gain(cfg.get("xpilotGain", 0.0))
    mg = db_to_gain(cfg.get("masterGain", 0.0))
    dp = cfg.get("discordPan", -0.8)
    xp = cfg.get("xpilotPan", 0.8)
    mix = array('f', [0.0] * (frames * 2))
    dmono_vals, xmono_vals = [], []
    for i in range(frames):
        dl, dr = discord[i*2], discord[i*2+1]
        xl, xr = xpilot[i*2], xpilot[i*2+1]
        dm = 0.5 * (dl + dr) * dg
        xm = 0.5 * (xl + xr) * xg
        dmono_vals.append(dm)
        xmono_vals.append(xm)
        dpl, dpr = pan_pair(dm, dp)
        xpl, xpr = pan_pair(xm, xp)
        l = (dpl + xpl) * mg
        r = (dpr + xpr) * mg
        peak = max(abs(l), abs(r), 1e-9)
        if peak > 0.98:
            l *= 0.98 / peak
            r *= 0.98 / peak
        mix[i*2] = l
        mix[i*2+1] = r
    with lock:
        meters["discordDb"] = peak_db(dmono_vals)
        meters["xpilotDb"] = peak_db(xmono_vals)
        meters["outputDb"] = peak_db(mix)
    outdata[:] = bytes_from_frames(mix)

def stop_audio():
    global streams
    for s in streams:
        try:
            s.stop(); s.close()
        except Exception:
            pass
    streams = []
    with lock:
        config["running"] = False
        meters["discordDb"] = meters["xpilotDb"] = meters["outputDb"] = -120.0
    save_config()

def start_audio():
    global streams
    if sd is None:
        raise RuntimeError("sounddevice not available: " + SD_IMPORT_ERROR)
    stop_audio()
    with lock:
        cfg = config.copy()
    discord_dev = pick_device(cfg.get("discordInput"))
    xpilot_dev = pick_device(cfg.get("xpilotInput"))
    output_dev = pick_device(cfg.get("outputDevice"))
    if output_dev is None:
        raise RuntimeError("Output nicht ausgewählt")
    sr = 48000
    block = 480
    if discord_dev is not None:
        streams.append(sd.RawInputStream(device=discord_dev, channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=make_input_cb("discord", 2)))
    if xpilot_dev is not None:
        streams.append(sd.RawInputStream(device=xpilot_dev, channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=make_input_cb("xpilot", 2)))
    streams.append(sd.RawOutputStream(device=output_dev, channels=2, samplerate=sr, blocksize=block, dtype="float32", callback=output_cb))
    for s in streams:
        s.start()
    with lock:
        config["running"] = True
    save_config()
    log("audio started")

def json_response(handler, obj, code=200):
    data = json.dumps(obj).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return
    def do_GET(self):
        if self.path.startswith("/health"):
            return json_response(self, {"ok": True, "version": ENGINE_VERSION, "sounddevice": sd is not None, "error": SD_IMPORT_ERROR})
        if self.path.startswith("/devices"):
            return json_response(self, get_devices())
        if self.path.startswith("/state"):
            with lock:
                state = {"ok": True, "version": ENGINE_VERSION, "config": config.copy(), "meters": meters.copy()}
            return json_response(self, state)
        return json_response(self, {"ok": False, "error": "not found"}, 404)
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(body.decode("utf-8") or "{}")
        except Exception:
            data = {}
        try:
            if self.path.startswith("/config"):
                with lock:
                    config.update(data)
                    save_config()
                return json_response(self, {"ok": True})
            if self.path.startswith("/start"):
                start_audio(); return json_response(self, {"ok": True})
            if self.path.startswith("/stop"):
                stop_audio(); return json_response(self, {"ok": True})
            if self.path.startswith("/shutdown"):
                stop_audio(); json_response(self, {"ok": True}); os._exit(0)
        except Exception as e:
            log(f"POST {self.path} failed: {e!r}")
            return json_response(self, {"ok": False, "error": str(e)}, 500)
        return json_response(self, {"ok": False, "error": "not found"}, 404)

def main():
    save_pid(); atexit.register(cleanup_pid); load_config()
    log(f"AudioDaBitch engine {ENGINE_VERSION} starting pid={os.getpid()}")
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        stop_audio(); cleanup_pid()

if __name__ == "__main__":
    main()
