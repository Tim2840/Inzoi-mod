// How the page talks to the mod.
//  - Desktop preview: HTTP calls to tools/preview_server.py, which runs the real Lua engine.
//  - In the game: mailboxes shared with the B1 relay (mod/lua/pawhome/adapters/inzoi_relay.lua),
//    see docs/design/modkit-runtime.md. Method names and payloads are the same in both places.
//
// In-game protocol (all strings):
//   to_ui  (relay writes, page reads): "seq,channel,payload;..."  (fields percent-encoded)
//          seq 0 is the relay's epoch. Channels: pawhome:hello, pawhome:save, pawhome:rpc_result.
//          payload = "<session>|<data>"
//   to_sim (page writes, relay reads): same format. Channels: pawhome:state, pawhome:rpc.
// The save data lives in wf.state.pawhome (stored inside the game's save file).
const Bridge = (() => {
  const inGame = typeof window.inzoi !== "undefined" && !!window.inzoi.cli;
  const SECTION = "bridge";
  const POLL_MS = 1000;
  const RPC_TIMEOUT_MS = 20000;
  const STATE_GRACE_MS = 4000;
  const KEEP = 20;

  // ---------------------------------------------------------------- desktop preview

  async function httpCall(method, args) {
    const res = await fetch("/api/" + method, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error(data.error || "HTTP " + res.status);
    return data;
  }

  if (!inGame) return { call: (m, a = {}) => httpCall(m, a), preview: true };

  // ---------------------------------------------------------------- in-game transport

  const modId = () => (window.wf && window.wf.MOD_ID) || "PawHome";
  const store = () => {
    const s = window.wf ? window.wf.state : (window.__pawhomeState = window.__pawhomeState || {});
    if (!s.pawhome || typeof s.pawhome !== "object") s.pawhome = {};
    return s.pawhome;
  };

  const esc = (s) => encodeURIComponent(String(s));
  const unesc = (s) => { try { return decodeURIComponent(s); } catch (e) { return s; } };

  function encodeMailbox(entries) {
    return entries.map((e) => e.seq + "," + esc(e.channel) + "," + esc(e.payload)).join(";");
  }
  function decodeMailbox(text) {
    if (typeof text !== "string" || text === "") return [];
    const out = [];
    for (const item of text.split(";")) {
      const m = item.match(/^(\d+),([^,]*),(.*)$/);
      if (m) out.push({ seq: Number(m[1]), channel: unesc(m[2]), payload: unesc(m[3]) });
    }
    return out;
  }

  async function cli(id, params) {
    const r = await window.inzoi.cli.execute(id, params);
    return r || {};
  }
  async function cfgLoad(key) {
    const r = await cli("uimod.cfg_load", { mod_id: modId(), section: SECTION, key });
    const d = r.data;
    if (d && typeof d === "object" && typeof d.value === "string") return d.value;
    return "";
  }
  async function cfgSave(key, value) {
    await cli("uimod.cfg_save", { mod_id: modId(), section: SECTION, key, value });
  }

  const epoch = String(Math.floor(Math.random() * 900000) + 100000);
  const outbox = [];        // what the page sends to the relay
  let nextSeq = 1;
  let relayEpoch = null;
  let lastSeen = 0;
  let skipBefore = null;    // entries that were already in the mailbox when the page started are stale
  let session = null;       // the B2 session we are talking to
  let stateReady = false;   // wf.state has been restored (or there is none)
  let answered = null;      // the session we already sent the save data to
  let nextRpc = 1;
  const waiting = new Map(); // rpc id -> { resolve, reject, timer }

  window._onStateLoaded = ((prev) => (s) => {
    stateReady = true;
    if (typeof prev === "function") prev(s);
  })(window._onStateLoaded);
  setTimeout(() => { stateReady = true; }, STATE_GRACE_MS);

  async function send(channel, data) {
    outbox.push({ seq: nextSeq++, channel, payload: session + "|" + data });
    while (outbox.length > KEEP) outbox.shift();
    await cfgSave("to_sim", encodeMailbox([{ seq: 0, channel: "epoch", payload: epoch }, ...outbox]));
  }

  function answerHello() {
    if (!session || !stateReady || answered === session) return;
    answered = session;
    send("pawhome:state", JSON.stringify(store()));
  }

  function handle(e) {
    const bar = e.payload.indexOf("|");
    const from = bar >= 0 ? e.payload.slice(0, bar) : e.payload;
    const data = bar >= 0 ? e.payload.slice(bar + 1) : "";
    if (e.channel === "pawhome:hello") {
      session = from;
      answerHello();
      return;
    }
    if (from !== session) return;                       // left over from another game session
    if (e.channel === "pawhome:save") {
      try {
        const t = JSON.parse(data);
        if (t && typeof t.key === "string") store()[t.key] = t.value;
      } catch (err) { /* ignore a damaged entry */ }
    } else if (e.channel === "pawhome:rpc_result") {
      let t;
      try { t = JSON.parse(data); } catch (err) { return; }
      const w = t && waiting.get(t.id);
      if (!w) return;
      waiting.delete(t.id);
      clearTimeout(w.timer);
      if (t.result && t.result.error) w.reject(new Error(t.result.error));
      else w.resolve(t.result);
    }
  }

  async function poll() {
    try {
      const entries = decodeMailbox(await cfgLoad("to_ui"));
      const head = entries.find((e) => e.seq === 0 && e.channel === "epoch");
      const ep = head ? head.payload : null;
      if (skipBefore === null) {
        // first read: everything already there belongs to an earlier load
        relayEpoch = ep;
        lastSeen = entries.reduce((m, e) => Math.max(m, e.seq), 0);
        skipBefore = true;
      } else if (ep !== relayEpoch) {
        relayEpoch = ep;
        lastSeen = 0;
      }
      for (const e of entries) {
        if (e.seq > lastSeen) { lastSeen = e.seq; handle(e); }
      }
      answerHello();
    } catch (err) {
      if (window.inzoi.debug) window.inzoi.debug.log("[PawHome] poll failed: " + err);
    } finally {
      setTimeout(poll, POLL_MS);
    }
  }
  poll();

  function call(method, args = {}) {
    if (!session || answered !== session) return Promise.reject(new Error("not_ready"));
    const id = nextRpc++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiting.delete(id); reject(new Error("timeout")); }, RPC_TIMEOUT_MS);
      waiting.set(id, { resolve, reject, timer });
      send("pawhome:rpc", JSON.stringify({ id, method, args })).catch(reject);
    });
  }

  return { call, preview: false, ready: () => !!session && answered === session };
})();
