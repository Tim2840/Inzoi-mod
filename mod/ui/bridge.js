// How the page talks to the mod.
//  - Desktop preview: HTTP calls to tools/preview_server.py, which runs the real Lua engine.
//  - In the game: mailboxes shared with the B1 relay (mod/lua/pawhome/adapters/inzoi_relay.lua),
//    see docs/design/modkit-runtime.md. Method names and payloads are the same in both places.
//
// In-game protocol (all strings):
//   to_ui  (relay writes, page reads): "seq,channel,payload;..."  (fields percent-encoded)
//          seq 0 is the relay's epoch. Channels: pawhome:hello, pawhome:save, pawhome:rpc_result,
//          pawhome:open (data = JSON entry {shell, tab, stray}: show the shop, e.g. after an interaction).
//          payload = "<session>|<data>"
//   to_sim (page writes, relay reads): same format. Channels: pawhome:state, pawhome:rpc.
// The save data lives in wf.state.pawhome (stored inside the game's save file).
const Bridge = (() => {
  const inGame = typeof window.inzoi !== "undefined" && !!window.inzoi.cli;
  const SECTION = "bridge";
  const POLL_FAST_MS = 150;     // while a request is open and for a few seconds after one
  const POLL_SLOW_MS = 1000;
  const FAST_FOR_MS = 5000;
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

  if (!inGame) return { call: (m, a = {}) => httpCall(m, a), preview: true, onOpen: () => {} };

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
    // rejects with "Key not found" until the other side has written the mailbox once
    const r = await cli("uimod.cfg_load", { mod_id: modId(), section: SECTION, key }).catch(() => ({}));
    const d = r.data;
    if (d && typeof d === "object" && typeof d.value === "string") return d.value;
    return "";
  }
  async function cfgSave(key, value) {
    await cli("uimod.cfg_save", { mod_id: modId(), section: SECTION, key, value });
  }

  // The game shows no browser console; page errors go to <mod>/log/ui.cfg instead.
  const pageLog = [];
  function report(line) {
    pageLog.push(new Date().toISOString() + " " + line);
    while (pageLog.length > 30) pageLog.shift();
    cli("uimod.cfg_save", { mod_id: modId(), section: "log", key: "ui", value: esc(pageLog.join("\n")) }).catch(() => {});
  }
  window.addEventListener("error", (e) => report("error: " + e.message + " @ " + e.filename + ":" + e.lineno));
  window.addEventListener("unhandledrejection", (e) => report("rejection: " + (e.reason && e.reason.message || e.reason)));
  report("page loaded, wf=" + !!window.wf + " saveState=" + !!(window.inzoi && window.inzoi.saveState));

  // Game data the Lua side relies on, added at every load with the Public data.patch command
  // (runtime patches are dropped when the session ends, so nothing is written to the save).
  //  - PawHome_WelcomeCat: the Zoi strikes the cat-heart pose; at the end a DEV_Void_Cat is
  //    summoned in front of her (the home cat, ADR 0008).
  //  - PawHome_SendAway: the Zoi plays with the cat once more; at the end the cat is removed.
  // Neither is added to any interaction menu; only the mod puts them in a Zoi's queue.
  // Verified in game 20261019.16318.W (2026-10-21): these minimal rows are accepted and
  // PawHome_WelcomeCat summons a visible, persistent cat.
  const GAME_DATA = [
    ["Script", "PawHome_SpawnCat", { ID: "PawHome_SpawnCat", Scripts: [{ IfType: "If", Conditions: [], Executes: [
      { BaseObject: "Self", Command: "SpawnGameObjectToFront", S1: "DEV_Void_Cat", S2: "None", F1: 110, F2: 0, Prob: 1 }] }] }],
    ["Script", "PawHome_DespawnTarget", { ID: "PawHome_DespawnTarget", Scripts: [{ IfType: "If", Conditions: [], Executes: [
      { BaseObject: "Target", Command: "DespawnGameObject", S1: "None", S2: "None", F1: 0, F2: 0, Prob: 1 }] }] }],
    ["Interaction", "PawHome_WelcomeCat", { ID: "PawHome_WelcomeCat", ActionIdList: ["Self_Pose_CatHeart"],
      FinishScriptIdList: ["PawHome_SpawnCat"], InteractionSlotUsage: "None", NoneTargetPlayable: true,
      PostureId: ["Stand"], BodyParts: ["BothHands"] }],
    ["InteractionBag", "PawHome_WelcomeCat", { ID: "PawHome_WelcomeCat", GroupId: "Group_Self_Expression",
      PostureGroupId: "StandGroup", AgingConditionFlags: 504, RepeatCount: 1,
      InteractionSequence: [{ Probability: 1, InteractionInfos: [{ InteractionId: "PawHome_WelcomeCat", Label: "A" }] }] }],
    ["Interaction", "PawHome_SendAway", { ID: "PawHome_SendAway", ActionIdList: ["Object_Void_Cat_Tickle"],
      FinishScriptIdList: ["PawHome_DespawnTarget"], InteractionSlotUsage: "Single",
      PostureId: ["Stand"], BodyParts: ["BothHands"] }],
    ["InteractionBag", "PawHome_SendAway", { ID: "PawHome_SendAway", PostureGroupId: "StandGroup",
      AgingConditionFlags: 504, RepeatCount: 1,
      InteractionSequence: [{ Probability: 1, InteractionInfos: [{ InteractionId: "PawHome_SendAway", Label: "A" }] }] }],
  ];
  // The cat's gifts are real items (mod/lua/pawhome/data/keepsakes.lua lists the same ids; a test
  // keeps the lists equal). After a happy moment the mod queues PawHome_Gift_<object> on the Zoi:
  // she strikes the cat-heart pose and the finish script puts the object in her bag.
  const GIFT_OBJECTS = ["CarriableStone01", "CatLeaf01", "CatPuree01", "CatToy01", "GiftCatDoll01",
    "GiftBouquet01", "CollectionRibbonCoral01", "AmethystStone", "AquamarineStone", "EmeraldStone"];
  for (const obj of GIFT_OBJECTS) {
    const script = "PawHome_GiftScript_" + obj, id = "PawHome_Gift_" + obj;
    GAME_DATA.push(
      ["Script", script, { ID: script, Scripts: [{ IfType: "If", Conditions: [], Executes: [
        { BaseObject: "Self", Command: "AddObjectToBag", S1: obj, S2: "None", F1: 1, F2: 0, Prob: 1 }] }] }],
      ["Interaction", id, { ID: id, ActionIdList: ["Self_Pose_CatHeart"], FinishScriptIdList: [script],
        InteractionSlotUsage: "None", NoneTargetPlayable: true, PostureId: ["Stand"], BodyParts: ["BothHands"] }],
      ["InteractionBag", id, { ID: id, GroupId: "Group_Self_Expression", PostureGroupId: "StandGroup", AgingConditionFlags: 504,
        RepeatCount: 1, InteractionSequence: [{ Probability: 1, InteractionInfos: [{ InteractionId: id, Label: "A" }] }] }]);
  }
  // Shop entries in the game's own menus (docs/research/phone-pc-ui.md). Labels are our text ids
  // (mod_PawHome_*), shipped as l10n/<culture>_mod/PawHome.po by tools/build_modkit.py.
  //  - PawHome_ShopPhone: the Zoi's own menu, "Use smartphone" group; she looks at her phone.
  // While the Zoi does it, app.js opens the shop.
  const SHOP_DATA = [
    ["Interaction", "PawHome_ShopPhone", { ID: "PawHome_ShopPhone", ActionIdList: ["SmartPhone_Check"],
      InteractionSlotUsage: "None", PostureId: ["Stand", "MovingChair_Sit", "Sit"], BodyParts: ["LeftHand"] }],
    ["InteractionBag", "PawHome_ShopPhone", { ID: "PawHome_ShopPhone", GroupId: "Group_Using_SmartPhone", PostureGroupId: "StandGroup",
      AgingConditionFlags: 504, RepeatCount: 1,
      InteractionSequence: [{ Probability: 1, InteractionInfos: [{ InteractionId: "PawHome_ShopPhone", Label: "B" }] }],
      DisplayInfo: { DisplayTextId: "mod_PawHome_shop_phone", Icon: "/Game/UI/Icon/Object/Action_SmartPhone.Action_SmartPhone",
        DisplayCategoryTextId: "InteractionBag_DisplayInfo_Self_SmartPhone_Insurance_CurrentState_DisplayCategoryTextId" } }],
  ];
  // PawHome_Adopt: on city cats (DEV_Void_Cat / Level_Void_Cat share this selection set; the
  // B2 adapter ignores it on our own home cats). The Zoi plays with the cat once; at the start
  // the adapter sends pawhome:open with the cat, and the shop opens on the adopt tab.
  SHOP_DATA.push(
    ["Interaction", "PawHome_Adopt", { ID: "PawHome_Adopt", ActionIdList: ["Object_Void_Cat_Tickle"],
      InteractionSlotUsage: "Single", PostureId: ["Stand"], BodyParts: ["BothHands"] }],
    ["InteractionBag", "PawHome_Adopt", { ID: "PawHome_Adopt", PostureGroupId: "StandGroup", AgingConditionFlags: 504, RepeatCount: 1,
      InteractionSequence: [{ Probability: 1, InteractionInfos: [{ InteractionId: "PawHome_Adopt", Label: "A" }] }],
      DisplayInfo: { DisplayTextId: "mod_PawHome_adopt_cat" } }]);
  // The cat's own menu (docs/design/gameplay-v2.md): the game's interactions for cats, with the
  // game's own names in every language. The mod counts them as care (adapters/inzoi.lua CARE):
  // Pet Gently = cuddle, Give Treat to Cat / Give Catnip Candy to Cat (need that item in the bag)
  // = feed. Give Snack and Play are on the cat already. Verified in game 20261019.16318.W
  // (2026-10-22): they appear on the cat and Pet Gently plays the Zoi and cat animation.
  const SHOP_MENUS = [   // [selection set row, state group, interaction bag]
    ["DEV_Void_Cat", "Normal", "Petting_Cat"],
    ["DEV_Void_Cat", "Normal", "Giving_Snack_To_Cat"],
    ["DEV_Void_Cat", "Normal", "Giving_Catnip_Candy_To_Cat"],
    ["DEV_Void_Cat", "Normal", "PawHome_Adopt"],
    ["SelfCharacter", "Normal", "PawHome_ShopPhone"],
  ];
  // The game limits how fast commands may come in (it answers "request limit exceeded" and the
  // rows after that are lost; seen 2026-10-22 with about 90 quick calls). So the setup is paced and
  // a refused call is tried again. Appending a row whose id exists REPLACES it (verified), so rows
  // need no existence check; only the menu lists do, because a list append just adds an entry.
  const PACE_MS = 110, RETRIES = 6;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  async function paced(id, params) {
    for (let attempt = 0; ; attempt++) {
      await sleep(PACE_MS);
      try {
        return await cli(id, params);
      } catch (err) {
        if (attempt >= RETRIES) throw err;
        await sleep(300 * (attempt + 1));
      }
    }
  }
  (async () => {
    const menus = [];
    const known = {};                                           // selection set -> its JSON text
    for (const [set, stateGroup, bag] of SHOP_MENUS) {
      if (!(set in known)) {
        const r = await paced("data.table_get", { alias: "ObjectSelectionSet", row: set }).catch(() => null);
        known[set] = r && r.success ? JSON.stringify(r) : null;
      }
      if (known[set] === null || known[set].indexOf('"' + bag + '"') >= 0) continue;     // missing set, or there already
      menus.push([set, { query: `ObjectSelectionSet[Id=${set}].SelectionSets[StateGroupId=${stateGroup}].InteractionBagList`, value: bag }]);
    }
    let failed = 0;
    for (const [alias, id, row] of GAME_DATA.concat(SHOP_DATA)) {
      try {
        const r = await paced("data.patch", { method: "Append", query: alias, value: JSON.stringify(row) });
        if (!r || !r.success) { failed++; report("data.patch " + alias + "/" + id + " failed: " + JSON.stringify(r)); }
      } catch (err) { failed++; report("data.patch " + alias + "/" + id + " threw: " + JSON.stringify(err)); }
    }
    for (const [set, m] of menus) {
      try {
        const r = await paced("data.patch", { method: "Append", query: m.query, value: m.value });
        if (!r || !r.success) { failed++; report("menu " + set + " " + m.value + " failed: " + JSON.stringify(r)); }
      } catch (err) { failed++; report("menu " + set + " " + m.value + " threw: " + JSON.stringify(err)); }
    }
    report("game data ready (" + (GAME_DATA.length + SHOP_DATA.length) + " rows, " + menus.length + " menu entries, " + failed + " failed)");
  })();

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
  let openHandler = null;   // app.js: show the shop

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
    } else if (e.channel === "pawhome:open") {
      let entry = {};
      try { entry = JSON.parse(data || "{}"); } catch (err) { /* open with defaults */ }
      if (openHandler) openHandler(entry);
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

  // A page that starts (or is reloaded) in the middle of a game missed the hello B2 sent earlier and
  // would wait up to a minute for the next one; this asks B2 to say it again at once.
  function wakeB2() {
    outbox.push({ seq: nextSeq++, channel: "pawhome:wake", payload: "-|" });
    while (outbox.length > KEEP) outbox.shift();
    cfgSave("to_sim", encodeMailbox([{ seq: 0, channel: "epoch", payload: epoch }, ...outbox])).catch(() => {});
  }

  let pollTimer = null, polling = false, fastUntil = 0;
  const pollDelay = () => (waiting.size > 0 || Date.now() < fastUntil ? POLL_FAST_MS : POLL_SLOW_MS);
  function schedulePoll(ms) {
    if (pollTimer) clearTimeout(pollTimer);
    pollTimer = setTimeout(poll, ms);
  }
  function wake() {        // something is about to happen: look at the mailbox now and then quickly
    fastUntil = Date.now() + FAST_FOR_MS;
    if (!polling) schedulePoll(0);
  }

  let lastPollError = null;
  async function poll() {
    polling = true;
    pollTimer = null;
    try {
      const entries = decodeMailbox(await cfgLoad("to_ui"));
      const head = entries.find((e) => e.seq === 0 && e.channel === "epoch");
      const ep = head ? head.payload : null;
      if (skipBefore === null) {
        // first read: everything already there belongs to an earlier load
        relayEpoch = ep;
        lastSeen = entries.reduce((m, e) => Math.max(m, e.seq), 0);
        skipBefore = true;
        wakeB2();
      } else if (ep !== relayEpoch) {
        relayEpoch = ep;
        lastSeen = 0;
      }
      for (const e of entries) {
        if (e.seq > lastSeen) { lastSeen = e.seq; handle(e); }
      }
      answerHello();
    } catch (err) {
      const text = "poll failed: " + (err && err.message || JSON.stringify(err));
      if (text !== lastPollError) { lastPollError = text; report(text); }
    } finally {
      polling = false;
      schedulePoll(pollDelay());
    }
  }
  poll();

  // how long a call takes, from pressing the button to the answer (shown in the page log)
  const rtt = { n: 0, sum: 0, last: 0 };
  function recordRtt(ms) {
    rtt.n++; rtt.sum += ms; rtt.last = ms;
    if (rtt.n % 8 === 1) report("rpc round trip: last " + ms + " ms, average " + Math.round(rtt.sum / rtt.n) + " ms over " + rtt.n + " calls");
  }

  function call(method, args = {}) {
    if (!session || answered !== session) return Promise.reject(new Error("not_ready"));
    const id = nextRpc++;
    const t0 = Date.now();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiting.delete(id); reject(new Error("timeout")); }, RPC_TIMEOUT_MS);
      waiting.set(id, { resolve: (v) => { recordRtt(Date.now() - t0); resolve(v); }, reject, timer });
      wake();
      send("pawhome:rpc", JSON.stringify({ id, method, args })).then(wake, reject);
    });
  }

  return { call, preview: false, ready: () => !!session && answered === session, onOpen: (fn) => { openHandler = fn; } };
})();
