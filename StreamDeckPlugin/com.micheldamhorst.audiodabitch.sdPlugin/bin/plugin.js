const streamDeck = require("@elgato/streamdeck");
const API = "http://127.0.0.1:49372/command";
async function sendCommand(payload) {
  try {
    await fetch(API, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
  } catch (err) { console.error("AudioDaBitch not reachable", err); }
}
function commandFor(uuid, ticks = 1) {
  const step = Math.max(-5, Math.min(5, ticks));
  switch (uuid) {
    case "com.micheldamhorst.audiodabitch.xpilot-gain-up": return { action: "adjust", path: "xpilot.gainDb", delta: 1 };
    case "com.micheldamhorst.audiodabitch.xpilot-gain-down": return { action: "adjust", path: "xpilot.gainDb", delta: -1 };
    case "com.micheldamhorst.audiodabitch.discord-gain-up": return { action: "adjust", path: "discord.gainDb", delta: 1 };
    case "com.micheldamhorst.audiodabitch.discord-gain-down": return { action: "adjust", path: "discord.gainDb", delta: -1 };
    case "com.micheldamhorst.audiodabitch.duck-more": return { action: "adjust", path: "ducking.depthDb", delta: -1 };
    case "com.micheldamhorst.audiodabitch.duck-less": return { action: "adjust", path: "ducking.depthDb", delta: 1 };
    case "com.micheldamhorst.audiodabitch.limiter-toggle": return { action: "toggle", path: "limiter.enabled" };
    case "com.micheldamhorst.audiodabitch.xpilot-gain-dial": return { action: "adjust", path: "xpilot.gainDb", delta: step };
    case "com.micheldamhorst.audiodabitch.ducking-dial": return { action: "adjust", path: "ducking.depthDb", delta: -step };
    default: return null;
  }
}
class ADBAction extends streamDeck.SingletonAction {
  async onKeyDown(ev) { const cmd = commandFor(ev.action.manifestId, 1); if (cmd) await sendCommand(cmd); }
  async onDialRotate(ev) { const cmd = commandFor(ev.action.manifestId, ev.payload.ticks || 0); if (cmd) await sendCommand(cmd); }
  async onDialDown(ev) {
    if (ev.action.manifestId === "com.micheldamhorst.audiodabitch.xpilot-gain-dial") await sendCommand({ action: "set", path: "xpilot.gainDb", value: 0 });
    if (ev.action.manifestId === "com.micheldamhorst.audiodabitch.ducking-dial") await sendCommand({ action: "set", path: "ducking.depthDb", value: -12 });
  }
}
for (const uuid of [
  "com.micheldamhorst.audiodabitch.xpilot-gain-up",
  "com.micheldamhorst.audiodabitch.xpilot-gain-down",
  "com.micheldamhorst.audiodabitch.discord-gain-up",
  "com.micheldamhorst.audiodabitch.discord-gain-down",
  "com.micheldamhorst.audiodabitch.duck-more",
  "com.micheldamhorst.audiodabitch.duck-less",
  "com.micheldamhorst.audiodabitch.limiter-toggle",
  "com.micheldamhorst.audiodabitch.xpilot-gain-dial",
  "com.micheldamhorst.audiodabitch.ducking-dial"
]) streamDeck.action({ UUID: uuid })(ADBAction);
streamDeck.connect();
