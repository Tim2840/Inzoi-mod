// Paw Home UI: one "online pet shop" shown in three shells that share the same content.
//  - phone: a pink cat-eared smartphone (opened from the Zoi's phone or the launcher)
//  - pc:    a browser window (opened from a computer or laptop)
//  - mini:  a round launcher sticker with Mochi the cat; the window shrinks to it when closed
// All text comes from the Lua side (view.ui and the labels in every pet / offer), so adding a
// language never touches this file. Icons are our own drawings (icons.js).
(() => {
  const ACTION_ICON = {
    feed: "food", play: "play", cuddle: "cuddle", groom: "groom",
    clean_litter: "litter", praise: "praise", scold: "scold", get_to_know: "get_to_know",
  };
  const NEED_ICON = { hunger: "food", energy: "energy", fun: "play", bladder: "litter" };
  const TABS = [["pets", "cat"], ["adopt", "adopt"], ["settings", "settings"]];
  const SIZE = { phone: [380, 760], pc: [960, 620], mini: [88, 88] };

  const params = new URLSearchParams(location.search);
  const state = {
    snap: null, tab: "pets", petId: null, offers: null, strays: null, busy: false,
    shell: null, lastOpen: "phone", focusStray: null,
  };
  const root = document.getElementById("app-root");
  const titleBar = document.getElementById("title-bar");
  const titleText = document.getElementById("title-text");
  const titleButtons = document.getElementById("title-buttons");
  const app = document.getElementById("app");
  const toasts = document.getElementById("toasts");

  // ------------------------------------------------------------ helpers
  // The game's browser (Coherent Gameface) lacks some newer DOM methods (replaceChildren,
  // append, Array.flat were missing in game 20261019.16318.W), so only long-standing calls are used.
  function flatten(list, out = []) {
    for (const c of list) Array.isArray(c) ? flatten(c, out) : out.push(c);
    return out;
  }
  function detach(el) { if (el && el.parentNode) el.parentNode.removeChild(el); }
  function setChildren(el, ...children) {
    while (el.firstChild) el.removeChild(el.firstChild);
    for (const c of flatten(children)) {
      if (c == null || c === false) continue;
      el.appendChild(c.nodeType ? c : document.createTextNode(String(c)));
    }
  }
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    setChildren(el, children);   // before attributes, so a `text` attribute is not wiped
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === false || v == null) continue;
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (k === "text") el.textContent = v;
      else el.setAttribute(k, v === true ? "" : v);
    }
    return el;
  }
  const icon = (name, opts) => Icons.img(name, opts);
  const fmt = (s, p) => String(s).replace(/\{(\w+)\}/g, (_, k) => (p && k in p ? p[k] : `{${k}}`));
  const ui = () => (state.snap && state.snap.view.ui) || {};
  const pets = () => (state.snap && !state.snap.view.noSave && state.snap.view.pets) || [];
  const currentPet = () => pets().find((p) => p.id === state.petId) || pets()[0] || null;

  const MAX_TOASTS = 3;
  function toast(text, isError) {
    if (!text) return;
    for (const t of toasts.children) if (t.textContent === text) return; // no duplicates
    const el = h("div", { class: "toast" + (isError ? " err" : "") },
      icon("cat", { mood: isError ? "sad" : "happy" }), h("span", {}, text));
    toasts.appendChild(el);
    while (toasts.children.length > MAX_TOASTS) detach(toasts.firstChild); // keep the newest
    setTimeout(() => detach(el), 3600);
  }

  async function call(method, args) {
    if (state.busy) return null;
    state.busy = true;
    try {
      const data = await Bridge.call(method, args);
      state.snap = data;
      for (const n of data.notifications || []) toast(n.text);
      if (data.result && data.result.message) toast(data.result.message, data.result.ok === false);
      for (const n of (data.result && data.result.notifications) || []) toast(n.text);
      return data;
    } catch (e) {
      toast(e.message, true);
      return null;
    } finally {
      state.busy = false;
    }
  }

  // ------------------------------------------------------------ shells (window chrome)
  function viewport() {
    return [window.innerWidth || document.documentElement.clientWidth || 1920,
            window.innerHeight || document.documentElement.clientHeight || 1080];
  }
  const where = {}; // last position of each shell in this session
  function defaultPos(shell) {
    const [W, H] = viewport(), [w, hgt] = SIZE[shell];
    if (shell === "mini") return [24, Math.round(H * 0.38)];
    if (shell === "phone") return [Math.max(8, W - w - 140), Math.max(8, Math.round((H - hgt) / 2))];
    return [Math.max(8, Math.round((W - w) / 2)), Math.max(8, Math.round((H - hgt) / 2))];
  }

  function setShell(shell) {
    if (state.shell && root.style.left) where[state.shell] = [parseFloat(root.style.left), parseFloat(root.style.top)];
    if (shell !== "mini") state.lastOpen = shell;
    state.shell = shell;
    root.className = "pw-" + shell;
    const [w, hgt] = SIZE[shell], [W, H] = viewport();
    const p = where[shell] || defaultPos(shell);
    const x = Math.max(0, Math.min(p[0], W - 60)), y = Math.max(0, Math.min(p[1], H - 60));
    root.style.width = w + "px";
    root.style.height = hgt + "px";
    root.style.left = x + "px";
    root.style.top = y + "px";
    root._savedW = w;            // window.js persists these
    root._savedH = hgt;
    if (typeof root._saveWindowState === "function") root._saveWindowState();
    render();
  }

  let closeBtn = null, deco = null;
  function renderChrome() {
    const u = ui();
    if (!closeBtn) {
      closeBtn = h("button", { class: "pw-x", onclick: () => setShell("mini") }, icon("close"));
      titleButtons.appendChild(closeBtn);
      deco = h("div", { class: "pw-deco" });
      titleBar.insertBefore(deco, titleBar.firstChild);
    }
    closeBtn.setAttribute("title", u.close || "");
    closeBtn.setAttribute("aria-label", u.close || "");
    if (state.shell === "phone") {
      setChildren(deco,
        h("div", { class: "pw-ears" },
          h("img", { class: "pw-ear l", src: Icons.url("ear"), alt: "", draggable: "false" }),
          h("img", { class: "pw-ear r", src: Icons.url("ear-r"), alt: "", draggable: "false" })),
        h("div", { class: "pw-case-top" }));
      setChildren(titleText,
        h("span", { class: "pw-clock" }, (state.snap && state.snap.time) || ""),
        h("span", { class: "pw-notch" }, h("i")),
        h("span", { class: "pw-status" }));
    } else if (state.shell === "pc") {
      setChildren(deco);
      setChildren(titleText,
        h("span", { class: "pw-dots" }, h("i", { style: "background:#ff7a93" }), h("i", { style: "background:#ffc857" }),
          h("i", { style: "background:#7dcfb6" })),
        h("span", { class: "pw-tab" }, icon("paw"), (state.snap && state.snap.view.title) || ""),
        h("span", { class: "pw-url" }, icon("paw"), u.url || ""));
    } else {
      setChildren(deco);
      setChildren(titleText);
    }
  }

  // ------------------------------------------------------------ content
  function coins() {
    return h("span", { class: "pw-coins", title: ui().money || "" }, icon("coin"), String(state.snap ? state.snap.money : ""));
  }

  function renderShelter(pet, u) {
    const r = pet.redeem;
    return h("div", { class: "shelter" },
      h("div", { class: "section-title" }, icon("shelter"), h("span", {}, pet.statusLabel)),
      h("div", { class: "sub" }, fmt(u.shelter_days_left, { days: r.daysLeft })),
      h("div", { class: "fee" }, icon("coin"), fmt(u.redeem_fee, { fee: r.fee })),
      h("button", {
        class: "btn", disabled: !r.ready, style: "margin-top:10px;width:100%",
        onclick: async () => { await call("redeem", { petId: pet.id }); render(); },
      }, r.ready ? u.redeem : fmt(u.redeem_wait, { hours: r.waitHours })));
  }

  function renderIllness(pet, u) {
    const ill = pet.illness;
    return h("div", { class: "ill" },
      h("div", { class: "section-title" }, icon("vet"), h("span", {}, ill.name)),
      h("div", { class: "sub" }, ill.desc),
      h("button", {
        class: "btn", style: "margin-top:8px;width:100%",
        onclick: async () => { await call("vet", { petId: pet.id }); render(); },
      }, fmt(u.vet, { fee: ill.vetFee })));
  }

  // cat furniture found on the household's lot ("home comfort")
  function furnitureCard(view) {
    const u = view.ui, list = view.furniture || [];
    return h("section", { class: "card" },
      h("div", { class: "section-title" }, icon("CatTower01"), h("span", {}, u.furniture)),
      list.length === 0 ? h("div", { class: "sub" }, u.furniture_none)
        : list.map((f) => h("div", { class: "furn" },
            icon(f.id),
            h("div", {}, h("b", {}, f.name),
              h("div", { class: "chips" }, (f.effects || []).map((e) => h("span", { class: "chip" }, e)))))));
  }

  function petCard(pet, u) {
    const away = pet.status === "impounded";
    return h("section", { class: "card", "aria-label": pet.name },
      h("div", { class: "pet-head" },
        h("div", { class: "avatar" }, icon(away ? "shelter" : "cat", { mood: pet.mood })),
        h("div", {},
          h("h2", { text: pet.name }),
          h("div", { class: "sub" }, `${pet.stageLabel} · ${pet.ageLabel}`),
          away ? h("div", { class: "away" }, pet.statusLabel) : h("span", { class: "mood" }, pet.moodLabel))),
      !away && pet.illness ? renderIllness(pet, u) : null,
      away ? renderShelter(pet, u) : h("div", {}, pet.needs.map((n) =>
        h("div", { class: "need", "data-state": n.state },
          icon(NEED_ICON[n.id] || "paw"),
          h("span", { class: "lbl" }, n.label),
          h("div", { class: "bar", role: "progressbar", "aria-label": n.label, "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": n.value },
            h("i", { style: `width:${n.value}%` })),
          h("span", { class: "val" }, n.value)))),
      h("div", { class: "bond", title: u.bond },
        icon("heart"),
        h("span", { class: "lbl" }, pet.bondLabel),
        h("div", { class: "bar" }, h("i", { style: `width:${pet.bond}%` })),
        h("span", { class: "val sub", style: "width:34px;text-align:right" }, pet.bond)));
  }

  function careCard(pet, view) {
    const u = view.ui;
    return h("section", { class: "card" },
      pet.status === "impounded" ? null : [
        h("div", { class: "section-title" }, icon("paw"), h("span", { class: "grow" }, u.care), h("span", { class: "sub" }, view.training.label)),
        h("div", { class: "actions" }, pet.actions.map((a) =>
          h("button", {
            class: "act", title: a.desc, disabled: !a.ready,
            onclick: async () => { await call("perform", { petId: pet.id, action: a.id }); render(); },
          }, h("span", { class: "tile" },
            icon(ACTION_ICON[a.id] || "paw"),
            h("span", { class: "lbl" }, a.label),
            a.cooldown > 0 ? h("span", { class: "cd" }, fmt(u.cooldown, { min: a.cooldown })) : null))))],
      h("div", { class: "section-title", style: "margin-top:6px" }, icon("get_to_know"), h("span", {}, u.traits)),
      h("div", { class: "chips" }, pet.traits.map((t) =>
        h("span", { class: "chip" + (t.known ? "" : " unknown"), title: t.desc || "" }, t.label))));
  }

  // the savegame has no pets but a copy outside it exists (e.g. saved while the UI mod was off)
  function backupCard(view) {
    const b = view.backup;
    if (!b) return null;
    return h("section", { class: "card backup" },
      h("div", { class: "section-title" }, icon("cat", { mood: "happy" }), h("span", {}, b.text)),
      h("button", {
        class: "btn", style: "width:100%",
        onclick: async () => { await call("restoreBackup", {}); state.petId = null; render(); },
      }, view.ui.backup_restore));
  }

  function renderPets(view) {
    const u = view.ui;
    if (view.pets.length === 0) {
      return h("div", {}, backupCard(view),
        h("div", { class: "card empty" }, icon("cat", { mood: "sad" }), h("div", {}, u.no_pets),
          h("button", { class: "btn", style: "margin-top:10px", onclick: () => { state.tab = "adopt"; render(); } }, u.adopt)));
    }
    const pet = currentPet();
    state.petId = pet.id;
    return h("div", {},
      backupCard(view),
      view.pets.length > 1
        ? h("div", { class: "chips", style: "margin-bottom:8px" }, view.pets.map((p) =>
            h("button", { class: "chip pet", "aria-pressed": p.id === pet.id, onclick: () => { state.petId = p.id; render(); } },
              icon("cat", { mood: p.mood }), p.name)))
        : null,
      h("div", { class: "pw-cols" },
        h("div", { class: "pw-col" }, petCard(pet, u)),
        h("div", { class: "pw-col" }, careCard(pet, view), furnitureCard(view))));
  }

  function renderOffer(o, u) {
    const input = h("input", { type: "text", value: o.name, maxlength: 24, "aria-label": u.name_label });
    return h("div", { class: "cell" }, h("section", { class: "card offer" },
      h("div", { class: "who" },
        h("div", { class: "avatar" }, icon("cat", { mood: "content" })),
        h("div", {}, h("h3", { text: o.name }), h("div", { class: "sub" }, o.stageLabel))),
      h("div", { class: "chips" }, o.traits.map((t) => h("span", { class: "chip", title: t.desc }, t.label))),
      h("div", { class: "row" },
        input,
        h("button", {
          class: "btn",
          onclick: async () => {
            const data = await call("adoptOffer", { offerId: o.id, name: input.value });
            if (data && data.result && data.result.ok) { state.offers = null; state.tab = "pets"; }
            render();
          },
        }, u.confirm)),
      h("div", { class: "fee" }, icon("coin"), o.fee > 0 ? fmt(u.fee, { fee: o.fee }) : u.free)));
  }

  function renderStray(s, u) {
    const input = h("input", { type: "text", placeholder: u.name_label, maxlength: 24, "aria-label": u.name_label });
    const focus = state.focusStray != null && String(state.focusStray) === String(s.id);
    return h("div", { class: "cell" }, h("section", { class: "card offer" + (focus ? " focus" : ""), "data-stray": s.id },
      h("div", { class: "who" },
        h("div", { class: "avatar" }, icon("cat", { mood: focus ? "happy" : "content" })),
        h("div", {}, h("h3", {}, s.stageLabel || s.stage), focus ? h("div", { class: "sub" }, u.adopt_this) : null)),
      h("div", { class: "row" },
        input,
        h("button", {
          class: "btn",
          onclick: async () => {
            const data = await call("adoptStray", { strayId: s.id, name: input.value });
            if (data && data.result && data.result.ok) { state.strays = null; state.focusStray = null; state.tab = "pets"; }
            render();
          },
        }, u.confirm))));
  }

  function renderAdopt(view) {
    const u = view.ui;
    const offers = state.offers || [];
    const strays = (state.strays || []).slice();
    // the cat the player picked in the world comes first
    strays.sort((a, b) => (String(b.id) === String(state.focusStray)) - (String(a.id) === String(state.focusStray)));
    const strayList = h("div", { class: "offers" }, strays.map((s) => renderStray(s, u)));
    const offerList = h("div", { class: "offers" }, offers.map((o) => renderOffer(o, u)));
    const shelter = [
      h("div", { class: "section-title" }, icon("shelter"), h("span", { class: "grow" }, u.shelter),
        h("button", { class: "btn ghost", onclick: async () => { const d = await call("offers", { refresh: true }); if (d) state.offers = d.offers; render(); } }, u.refresh)),
      offers.length ? offerList : h("div", { class: "card empty" }, icon("shelter"), u.no_offers)];
    const street = [
      h("div", { class: "section-title" }, icon("paw"), h("span", {}, u.stray_cats)),
      strays.length ? strayList : h("div", { class: "card empty" }, icon("cat", { mood: "sleep" }), u.no_strays)];
    return h("div", {}, state.focusStray != null ? [street, shelter] : [shelter, street]);
  }

  function toggle(label, key, settings) {
    const on = !!settings[key];
    const input = h("input", { type: "checkbox", checked: on, "aria-label": label,
      onchange: async (e) => { await call("setSetting", { key, value: e.target.checked }); render(); } });
    return h("label", { class: "setting" }, h("span", {}, label),
      h("span", { class: "switch" + (on ? " on" : "") }, input, h("span", { class: "track" }), h("span", { class: "knob" })));
  }

  function slider(label, key, min, max, step, settings, prefix) {
    const out = h("span", { class: "sub" }, prefix + settings[key]);
    const input = h("input", { type: "range", class: "range", min, max, step, value: settings[key], "aria-label": label,
      oninput: (e) => { out.textContent = prefix + e.target.value; },
      onchange: async (e) => { await call("setSetting", { key, value: Number(e.target.value) }); render(); } });
    return h("div", { class: "setting" }, h("span", {}, label), h("span", { class: "slider-val" }, input, out));
  }

  function renderSettings(view) {
    const u = view.ui, s = view.settings;
    const lang = h("select", { "aria-label": u.language,
      onchange: async (e) => { await call("setSetting", { key: "language", value: e.target.value }); render(); } },
      h("option", { value: "auto", selected: s.language === "auto" }, u.language_auto),
      h("option", { value: "en", selected: s.language === "en" }, "English"),
      h("option", { value: "zh-TW", selected: s.language === "zh-TW" }, "繁體中文"));
    return h("section", { class: "card" },
      h("div", { class: "setting" }, h("span", {}, u.language), lang),
      toggle(u.aging, "agingEnabled", s),
      toggle(u.misbehavior, "misbehaviorEnabled", s),
      toggle(u.animal_control, "animalControl", s),
      toggle(u.illness, "illnessEnabled", s),
      slider(u.decay, "needDecayScale", 0.25, 2, 0.25, s, "×"),
      slider(u.lifescale, "lifeScale", 0.5, 4, 0.5, s, "×"),
      slider(u.max_pets_setting, "maxPetsPerHousehold", 1, 4, 1, s, ""));
  }

  function renderDevBar() {
    if (!Bridge.preview) return null;
    const adv = (label, minutes) => h("button", { class: "btn ghost", onclick: async () => { await call("advance", { minutes }); render(); } }, label);
    const shell = (name) => h("button", { class: "btn ghost", onclick: () => setShell(name) }, name);
    return h("div", { class: "devbar" },
      h("span", { style: "width:100%" }, "Preview tools · 預覽工具"),
      adv("+1h", 60), adv("+6h", 360), adv("+1d", 1440), adv("+3d", 4320),
      h("button", { class: "btn ghost", onclick: async () => { state.offers = state.strays = null; state.petId = null; await call("reset", { locale: state.snap.view.locale }); render(); } }, "Reset"),
      shell("phone"), shell("pc"), shell("mini"),
      h("button", { class: "btn ghost", onclick: async () => { await call("sicken", { id: "fleas" }); render(); } }, "sick"),
      h("button", { class: "btn ghost", onclick: async () => { await call("fakeBackup", {}); state.petId = null; render(); } }, "backup"),
      ["CatScratcher01", "CatTower01", "CatWheel01"].map((id) =>
        h("button", { class: "btn ghost", onclick: async () => { await call("toggleFurniture", { id }); render(); } }, id.replace("Cat", "").replace("01", ""))),
      h("button", { class: "btn ghost", onclick: () => openEntry({ shell: "phone", tab: "adopt", stray: "s2" }) }, "cat menu"));
  }

  function body(view) {
    const u = view.ui;
    if (view.noSave && state.tab !== "settings") return h("div", { class: "card empty" }, icon("cat", { mood: "sleep" }), u.no_save);
    return state.tab === "pets" ? renderPets(view) : state.tab === "adopt" ? renderAdopt(view) : renderSettings(view);
  }

  function tabButtons(u) {
    return TABS.map(([id, ic]) => h("button", {
      class: "tab", role: "tab", "aria-selected": state.tab === id,
      onclick: async () => { state.tab = id; await render(); },
    }, icon(ic, { mood: id === "pets" && currentPet() ? currentPet().mood : null }), h("span", {}, u[id])));
  }

  function launcher() {
    const pet = currentPet();
    const alert = pets().some((p) => p.status === "impounded" || p.illness || p.needs.some((n) => n.state === "critical"));
    return h("button", { class: "pw-launch", title: ui().open || "", "aria-label": ui().open || "", onclick: () => setShell(state.lastOpen) },
      icon("cat", { mood: pet ? pet.mood : "content" }),
      h("span", { class: "pw-badge" + (alert ? " alert" : "") }, icon("paw")));
  }

  function waiting() {
    // the mod has not answered yet: no text is available before the first view
    return state.shell === "mini" ? launcher() : h("div", { class: "empty", style: "flex:1;justify-content:center" }, icon("cat", { mood: "sleep" }));
  }

  // ------------------------------------------------------------ render
  async function loadTab() {
    if (state.tab === "adopt" && (state.offers === null || state.strays === null)) {
      const o = await call("offers", {});
      if (o) state.offers = o.offers;
      const s = await call("strays", {});
      if (s) state.strays = s.strays;
    }
  }

  let rendering = false, again = false;
  async function render() {
    if (rendering) { again = true; return; }
    rendering = true;
    try { await draw(); } finally {
      rendering = false;
      if (again) { again = false; render(); }
    }
  }

  async function draw() {
    // In the game the mod answers only after the save data has been handed over.
    if (!state.snap && !Bridge.preview && Bridge.ready && !Bridge.ready()) {
      renderChrome();
      setChildren(app, waiting());
      setTimeout(render, 1000);
      return;
    }
    if (!state.snap) {
      const first = await call("view", {});
      if (!first) { renderChrome(); setChildren(app, waiting()); setTimeout(render, 3000); return; }
    }
    if (state.shell !== "mini") await loadTab();
    const view = state.snap.view, u = view.ui;
    document.documentElement.lang = view.locale === "zh-TW" ? "zh-Hant" : "en";
    document.title = view.title;
    renderChrome();
    const old = app.querySelector(".pw-body");
    const keep = old && old.getAttribute("data-tab") === state.tab ? old.scrollTop : 0;
    let scroller = null;
    if (state.shell === "mini") {
      setChildren(app, launcher());
    } else if (state.shell === "phone") {
      scroller = h("div", { class: "pw-body", "data-tab": state.tab }, body(view), renderDevBar());
      setChildren(app,
        h("header", { class: "pw-head" },
          icon("cat", { cls: "pw-mascot", mood: currentPet() ? currentPet().mood : "happy" }),
          h("div", { class: "pw-brand" }, h("b", {}, view.title), h("span", {}, u.tagline)),
          coins()),
        scroller,
        h("nav", { class: "pw-tabs", role: "tablist" }, tabButtons(u)));
    } else {
      scroller = h("div", { class: "pw-body", "data-tab": state.tab }, body(view), renderDevBar());
      setChildren(app,
        h("aside", { class: "pw-side" },
          h("div", { class: "pw-logo" }, icon("cat", { mood: "happy" }),
            h("div", { class: "pw-brand" }, h("b", {}, view.title), h("span", {}, u.tagline))),
          h("nav", { class: "pw-nav", role: "tablist" }, tabButtons(u)),
          coins()),
        h("div", { class: "pw-main" },
          h("div", { class: "pw-title" }, h("h1", {}, u[state.tab])),
          scroller));
    }
    // the picked city cat is sorted to the top of the adopt tab, so a new tab starts at the top
    if (scroller) scroller.scrollTop = keep;
  }

  // ------------------------------------------------------------ entry points
  // An entry opens a shell on a tab; `stray` is the city cat the player picked in the world.
  function openEntry(e) {
    if (e.tab) state.tab = e.tab;
    if (e.stray != null) { state.focusStray = e.stray; state.strays = null; }
    setShell(e.shell || state.lastOpen);
  }
  // the interaction-menu triggers in uimod_manifest.json (mod/modkit/ui), keyed by trigger id
  const TRIGGERS = {
    pawhome_phone: { shell: "phone" },
    pawhome_pc: { shell: "pc" },
    pawhome_cat: { shell: "phone", tab: "adopt" },
  };
  if (window.inzoi && window.inzoi.trigger) {
    window.inzoi.trigger.onActivated((t) => {
      const id = t && (t.triggerId || t.trigger_id || t.id);
      const e = TRIGGERS[id];
      if (!e) return;
      const target = t.target_entity_id || t.targetEntityId || t.entity_id || null;
      openEntry({ shell: e.shell, tab: e.tab, stray: e.tab === "adopt" && target != null ? "cat" + target : null });
    });
  }
  // the Lua side may ask to open the shop too ("pawhome:open" with a JSON entry)
  if (Bridge.onOpen) Bridge.onOpen((e) => openEntry(e || {}));

  // Entries through the game's own menus: our interactions (GAME_DATA in bridge.js) send the
  // Zoi to her phone or to a computer; while she does that, the shop opens in the matching shell.
  const ENTRY_BAGS = { PawHome_ShopPhone: { shell: "phone" }, PawHome_ShopPC: { shell: "pc" } };
  const ENTRY_POLL_MS = 1500;
  let possessed = null, possessedAt = 0, lastBag = null;
  const data = (r) => (r && typeof r.data === "object" && r.data) || r || {};
  async function watchEntries() {
    try {
      if (!possessed || Date.now() - possessedAt > 10000) {
        possessed = data(await window.inzoi.cli.execute("entity.get_possessed", {})).entity_id || null;
        possessedAt = Date.now();
      }
      if (possessed) {
        const cur = data(await window.inzoi.cli.execute("interaction.get_current", { entity_id: possessed }));
        const bag = cur.playing === false ? null : cur.interaction_bag_id || null;
        if (bag !== lastBag) {
          lastBag = bag;
          if (ENTRY_BAGS[bag]) openEntry(ENTRY_BAGS[bag]);
        }
      }
    } catch (e) { possessed = null; } finally { setTimeout(watchEntries, ENTRY_POLL_MS); }
  }
  if (!Bridge.preview && window.inzoi && window.inzoi.cli) watchEntries();

  // start: in the game as the launcher once window.js has restored its saved window state
  const startShell = Bridge.preview ? (SIZE[params.get("shell")] ? params.get("shell") : "phone") : "mini";
  function start(tries) {
    if (document.body && document.body.style.visibility === "hidden" && tries > 0) {
      setTimeout(() => start(tries - 1), 150);
      return;
    }
    setShell(startShell);
  }
  start(30);
  // desktop preview: keep the window on screen when the browser is resized (window.js does this in the game)
  if (Bridge.preview) {
    window.addEventListener("resize", () => {
      const s = state.shell;
      setShell(s);
      where[s] = null;
      setShell(s);
    });
  }
})();
