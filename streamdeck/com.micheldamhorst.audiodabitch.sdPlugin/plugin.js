// AudioDaBitch Stream Deck plugin bridge.
// This is a lightweight SDK v2 style WebSocket plugin that talks to the local AudioDaBitch HTTP API.

let websocket = null;
let pluginUUID = null;
const API = "http://127.0.0.1:49342/api";

function send(payload) {
  if (websocket && websocket.readyState === 1) websocket.send(JSON.stringify(payload));
}
function setTitle(context, title) {
  send({ event: "setTitle", context, payload: { title, target: 0 } });
}
async function apiGet(path) {
  const r = await fetch(API + path);
  return await r.json();
}
async function adjust(param, delta = 0, value = null) {
  const url = new URL(API + "/adjust");
  url.searchParams.set("param", param);
  url.searchParams.set("delta", String(delta));
  if (value !== null) url.searchParams.set("value", String(value));
  const r = await fetch(url.toString());
  return await r.json();
}
function setting(ev, key, fallback) {
  return (ev && ev.payload && ev.payload.settings && ev.payload.settings[key] !== undefined) ? ev.payload.settings[key] : fallback;
}

function connectElgatoStreamDeckSocket(inPort, inPluginUUID, inRegisterEvent, inInfo) {
  pluginUUID = inPluginUUID;
  websocket = new WebSocket("ws://127.0.0.1:" + inPort);
  websocket.onopen = () => send({ event: inRegisterEvent, uuid: inPluginUUID });
  websocket.onmessage = async (evt) => {
    const ev = JSON.parse(evt.data);
    const action = ev.action || "";
    const context = ev.context;
    try {
      if (ev.event === "willAppear") {
        setTitle(context, "ADB");
      }
      if (ev.event === "keyDown") {
        const param = setting(ev, "param", "xpilot_gain");
        const delta = Number(setting(ev, "delta", 1));
        if (param === "ducking" || param === "xpilot_agc") {
          const st = await apiGet("/status");
          const cfg = st.config || {};
          const next = param === "ducking" ? !cfg.ducking : !(cfg.xpilot_agc && cfg.xpilot_agc.enabled);
          await adjust(param, 0, next ? "true" : "false");
          setTitle(context, param === "ducking" ? (next ? "Duck\nON" : "Duck\nOFF") : (next ? "AGC\nON" : "AGC\nOFF"));
        } else {
          await adjust(param, delta);
          setTitle(context, `${param}\n${delta > 0 ? "+" : ""}${delta}`);
        }
      }
      if (ev.event === "dialRotate") {
        const param = setting(ev, "param", "xpilot_gain");
        const ticks = Number(ev.payload && ev.payload.ticks ? ev.payload.ticks : 0);
        const step = Number(setting(ev, "step", 0.5));
        await adjust(param, ticks * step);
        setTitle(context, `${param}\n${ticks > 0 ? "+" : ""}${ticks * step}`);
      }
      if (ev.event === "dialDown") {
        const toggle = setting(ev, "push", "ducking");
        const st = await apiGet("/status");
        const cfg = st.config || {};
        const next = toggle === "xpilot_agc" ? !(cfg.xpilot_agc && cfg.xpilot_agc.enabled) : !cfg.ducking;
        await adjust(toggle, 0, next ? "true" : "false");
        setTitle(context, toggle === "xpilot_agc" ? (next ? "AGC\nON" : "AGC\nOFF") : (next ? "Duck\nON" : "Duck\nOFF"));
      }
    } catch (e) {
      setTitle(context, "ADB\noffline");
    }
  };
}
