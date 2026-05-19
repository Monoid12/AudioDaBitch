#!/usr/bin/env python3
import atexit, audioop, json, math, os, queue, signal, struct, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ENGINE_VERSION = "0.5.3"
PORT = 49372
SUPPORT = Path(os.environ.get("ADB_SUPPORT", str(Path.home()/"Library/Application Support/AudioDaBitch")))
LOG_DIR = Path(os.environ.get("ADB_LOG_DIR", str(Path.home()/"Library/Logs/AudioDaBitch")))
SUPPORT.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
PID_FILE = SUPPORT / "engine.pid"
LOG_FILE = LOG_DIR / "engine.log"
CONFIG_FILE = SUPPORT / "config.json"

try:
    import sounddevice as sd
except Exception as e:
    sd = None
    SOUNDDEVICE_ERROR = repr(e)
else:
    SOUNDDEVICE_ERROR = ""

state = {"running": False, "levels": {"discord": -120.0, "xpilot": -120.0, "output": -120.0}, "error": ""}
config = {
    "discordDevice": -1, "xpilotDevice": -1, "outputDevice": -1,
    "discordGainDb": 0.0, "xpilotGainDb": 0.0, "discordPan": -0.8, "xpilotPan": 0.8,
    "masterGainDb": 0.0, "duckingDepthDb": -12.0, "targetDb": -21.0, "gateDb": -55.0, "fastDownMs": 18.0
}
streams = []
queues = {"discord": queue.Queue(maxsize=4), "xpilot": queue.Queue(maxsize=4)}
lock = threading.RLock()
last_active = time.time()

def log(msg):
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + str(msg) + "\n")

def save_pid():
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")

def cleanup_pid():
    try:
        if PID_FILE.exists() and PID_FILE.read_text().strip() == str(os.getpid()):
            PID_FILE.unlink()
    except Exception:
        pass

def db_to_gain(db): return 10.0 ** (float(db) / 20.0)
def gain_to_db(g): return -120.0 if g <= 1e-9 else 20.0 * math.log10(max(1e-9, g))

def rms_db(samples):
    if not samples: return -120.0
    s = 0.0
    n = 0
    for x in samples:
        s += x * x
        n += 1
    return gain_to_db(math.sqrt(s / max(1, n)))

def bytes_to_floats(data):
    if not data: return []
    count = len(data) // 4
    return list(struct.unpack("<" + "f" * count, data[:count*4]))

def floats_to_bytes(values):
    if not values: return b""
    return struct.pack("<" + "f" * len(values), *values)

def stereo_from_raw(raw, channels, frames, selected=(1,2)):
    vals = bytes_to_floats(raw)
    if channels < 1 or not vals:
        return [0.0] * (frames * 2)
    out = []
    ch0 = max(0, min(channels-1, selected[0]-1))
    ch1 = max(0, min(channels-1, selected[1]-1 if len(selected) > 1 else ch0))
    total_frames = min(frames, len(vals)//channels)
    for i in range(total_frames):
        base = i * channels
        out.append(vals[base + ch0])
        out.append(vals[base + ch1])
    while len(out) < frames * 2:
        out.append(0.0)
    return out[:frames*2]

def pan_stereo(stereo, pan):
    pan = max(-1.0, min(1.0, float(pan)))
    angle = (pan + 1.0) * math.pi / 4.0
    lg = math.cos(angle)
    rg = math.sin(angle)
    out = []
    for i in range(0, len(stereo), 2):
        mono = 0.5 * (stereo[i] + stereo[i+1])
        out.append(mono * lg)
        out.append(mono * rg)
    return out

def apply_gain(stereo, db):
    g = db_to_gain(db)
    return [x * g for x in stereo]

def clamp(stereo):
    return [max(-1.0, min(1.0, x)) for x in stereo]

def current_config():
    with lock:
        return dict(config)

def load_config():
    global config
    if CONFIG_FILE.exists():
        try:
            data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                config.update(data)
        except Exception as e:
            log(f"config load failed: {e}")

def save_config():
    try:
        CONFIG_FILE.write_text(json.dumps(config, indent=2), encoding="utf-8")
    except Exception as e:
        log(f"config save failed: {e}")

def input_callback(name, channels):
    def cb(indata, frames, time_info, status):
        if status: log(f"{name} status {status}")
        raw = bytes(indata)
        q = queues[name]
        try:
            while q.qsize() >= 3:
                q.get_nowait()
        except Exception:
            pass
        try: q.put_nowait((raw, channels, frames))
        except queue.Full: pass
    return cb

def get_frame(name, frames):
    try:
        raw, channels, got_frames = queues[name].get_nowait()
    except queue.Empty:
        return [0.0] * (frames * 2)
    return stereo_from_raw(raw, channels, frames)

def output_callback(outdata, frames, time_info, status):
    cfg = current_config()
    discord = pan_stereo(apply_gain(get_frame("discord", frames), cfg.get("discordGainDb", 0)), cfg.get("discordPan", -0.8))
    xpilot = pan_stereo(apply_gain(get_frame("xpilot", frames), cfg.get("xpilotGainDb", 0)), cfg.get("xpilotPan", 0.8))
    xdb = rms_db(xpilot)
    target = float(cfg.get("targetDb", -21.0))
    gate = float(cfg.get("gateDb", -55.0))
    if xdb > gate:
        diff = target - xdb
        diff = max(-18.0, min(12.0, diff))
        xpilot = apply_gain(xpilot, diff)
    ddb = rms_db(discord)
    if xdb > float(cfg.get("gateDb", -55.0)) and ddb > -70:
        discord = apply_gain(discord, float(cfg.get("duckingDepthDb", -12.0)))
    mix = []
    mg = db_to_gain(cfg.get("masterGainDb", 0.0))
    peak = 0.0
    for a, b in zip(discord, xpilot):
        v = (a + b) * mg
        peak = max(peak, abs(v))
        mix.append(v)
    if peak > db_to_gain(-1.0):
        reduction = db_to_gain(-1.0) / peak
        mix = [x * reduction for x in mix]
    mix = clamp(mix)
    outdata[:] = floats_to_bytes(mix)
    with lock:
        state["levels"] = {"discord": rms_db(discord), "xpilot": rms_db(xpilot), "output": rms_db(mix)}

def devices():
    if sd is None:
        return []
    out = []
    try:
        for idx, d in enumerate(sd.query_devices()):
            out.append({"id": idx, "name": d.get("name", f"Device {idx}"), "max_input_channels": int(d.get("max_input_channels", 0)), "max_output_channels": int(d.get("max_output_channels", 0))})
    except Exception as e:
        log(f"devices failed: {e}")
    return out

def stop_audio():
    global streams
    with lock:
        state["running"] = False
    for s in streams:
        try: s.stop(); s.close()
        except Exception: pass
    streams = []
    for q in queues.values():
        try:
            while True: q.get_nowait()
        except queue.Empty:
            pass

def start_audio():
    global streams
    if sd is None:
        with lock: state["error"] = "sounddevice nicht verfügbar: " + SOUNDDEVICE_ERROR
        return False
    stop_audio()
    cfg = current_config()
    try:
        sr = 48000
        bs = 512
        dd = int(cfg.get("discordDevice", -1)); xd = int(cfg.get("xpilotDevice", -1)); od = int(cfg.get("outputDevice", -1))
        if dd >= 0:
            channels = max(2, int(sd.query_devices(dd).get("max_input_channels", 2)))
            streams.append(sd.RawInputStream(device=dd, channels=channels, samplerate=sr, blocksize=bs, dtype="float32", callback=input_callback("discord", channels)))
        if xd >= 0:
            channels = max(2, int(sd.query_devices(xd).get("max_input_channels", 2)))
            streams.append(sd.RawInputStream(device=xd, channels=channels, samplerate=sr, blocksize=bs, dtype="float32", callback=input_callback("xpilot", channels)))
        if od < 0:
            raise RuntimeError("Bitte Output auswählen")
        streams.append(sd.RawOutputStream(device=od, channels=2, samplerate=sr, blocksize=bs, dtype="float32", callback=output_callback))
        for s in streams: s.start()
        with lock:
            state["running"] = True; state["error"] = ""
        return True
    except Exception as e:
        log(f"start_audio failed: {e}")
        with lock: state["error"] = str(e); state["running"] = False
        stop_audio()
        return False

def test_pan():
    # Non-blocking short test: if no audio stream is active, just mark levels briefly.
    with lock:
        state["levels"] = {"discord": -6.0, "xpilot": -6.0, "output": -6.0}
    return True

class Handler(BaseHTTPRequestHandler):
    def _send(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        return
    def do_GET(self):
        if self.path.startswith("/devices"):
            return self._send(devices())
        if self.path.startswith("/state"):
            with lock: snap = dict(state)
            snap["version"] = ENGINE_VERSION
            return self._send(snap)
        return self._send({"ok": True, "version": ENGINE_VERSION})
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""
        if self.path.startswith("/config"):
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                with lock: config.update(data); save_config()
                return self._send({"ok": True})
            except Exception as e:
                return self._send({"ok": False, "error": str(e)}, 400)
        if self.path.startswith("/start"):
            return self._send({"ok": start_audio()})
        if self.path.startswith("/audio_stop"):
            stop_audio(); return self._send({"ok": True})
        if self.path.startswith("/test_pan"):
            return self._send({"ok": test_pan()})
        if self.path.startswith("/stop"):
            stop_audio(); self._send({"ok": True}); threading.Thread(target=lambda: (time.sleep(0.2), os._exit(0)), daemon=True).start(); return
        return self._send({"ok": False, "error": "unknown"}, 404)

def main():
    save_pid(); atexit.register(cleanup_pid); load_config(); log(f"AudioDaBitch engine {ENGINE_VERSION} starting")
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        log(f"port bind failed: {e}")
        os.system("/usr/sbin/lsof -iTCP:49372 -sTCP:LISTEN >> '%s' 2>&1" % LOG_FILE)
        raise
    def sig(_signum, _frame):
        stop_audio(); cleanup_pid(); os._exit(0)
    signal.signal(signal.SIGTERM, sig); signal.signal(signal.SIGINT, sig)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        stop_audio(); cleanup_pid(); log("engine stop")

if __name__ == "__main__":
    main()
