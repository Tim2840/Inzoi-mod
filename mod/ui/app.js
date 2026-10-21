// Paw Home UI: a small pink cat-eared phone that SHOWS how the cat is doing, plus a round launcher.
// Care itself happens in the game: the player clicks the cat and uses its interaction menu
// (Pet Gently, Give Snack, Play, ...). This page only displays mood, needs, what the cat wants,
// the gift album, adoption and the settings. docs/design/gameplay-v2.md.
//  - phone: opened from the launcher or the Zoi's phone; drag it by the top strip
//  - mini:  a small round launcher sticker with Mochi the cat; drag it anywhere, press it to open
// All text comes from the Lua side (view.ui and the labels in every pet / offer), so adding a
// language never touches this file. Icons are our own drawings (icons.js).
(() => {
  const NEED_ICON = { hunger: "food", energy: "energy", fun: "play", bladder: "litter" };
  const WANT_ICON = { feed: "food", play: "play", cuddle: "cuddle", clean_litter: "litter" };
  const TABS = [["pets", "cat"], ["adopt", "adopt"], ["album", "album"], ["settings", "settings"]];
  const SIZE = { phone: [300, 540], mini: [56, 56] };

  // (no URLSearchParams in the game's browser)
  const param = (name) => {
    const m = (location.search || "").match(new RegExp("[?&]" + name + "=([^&]*)"));
    return m ? decodeURIComponent(m[1]) : null;
  };
  const state = {
    snap: null, tab: "pets", petId: null, offers: null, strays: null,
    shell: null, focusStray: null,
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
  function toast(text, kind) {
    if (!text) return;
    for (const t of toasts.children) if (t.textContent === text) return; // no duplicates
    const el = h("div", { class: "toast" + (kind ? " " + kind : "") },
      icon("cat", { mood: kind === "err" ? "sad" : "happy" }), h("span", {}, text));
    toasts.appendChild(el);
    while (toasts.children.length > MAX_TOASTS) detach(toasts.firstChild); // keep the newest
    setTimeout(() => detach(el), 3600);
  }

  // One call at a time, in the order they were made (a press is never thrown away).
  let chain = Promise.resolve();
  function call(method, args) {
    const run = async () => {
      try {
        const data = await Bridge.call(method, args);
        state.snap = data;
        for (const n of data.notifications || []) toast(n.text);
        if (data.result && data.result.message) toast(data.result.message, data.result.ok === false ? "err" : null);
        for (const n of (data.result && data.result.notifications) || []) toast(n.text);
        return data;
      } catch (e) {
        toast(e.message, "err");
        return null;
      }
    };
    const p = chain.then(run);
    chain = p;
    return p;
  }

  // ------------------------------------------------------------ the window: phone or launcher
  function viewport() {
    return [window.innerWidth || document.documentElement.clientWidth || 1920,
            window.innerHeight || document.documentElement.clientHeight || 1080];
  }
  const where = {};   // where the launcher sits (kept while the phone is open)
  function clampPos(p, w, hgt) {
    const [W, H] = viewport();
    return [Math.max(0, Math.min(p[0], W - w)), Math.max(0, Math.min(p[1], H - hgt))];
  }
  function defaultPos(shell) {
    // right side, below the game's top bar and clear of its left-hand task list; the phone opens to the launcher's left
    const [W, H] = viewport();
    return shell === "mini" ? [Math.max(0, W - 150), Math.round(H * 0.2)] : [Math.max(0, W - 460), 24];
  }
  // the phone opens next to the launcher, on the side with room
  function besideLauncher(m) {
    const [W] = viewport(), [w, hgt] = SIZE.phone;
    const right = m[0] + SIZE.mini[0] + 8;
    return clampPos([right + w <= W ? right : m[0] - w - 8, m[1]], w, hgt);
  }

  function setShell(shell) {
    const was = state.shell;
    if (was === "mini" && root.style.left) where.mini = [parseFloat(root.style.left), parseFloat(root.style.top)];
    state.shell = shell;
    root.className = "pw-" + shell;
    const [w, hgt] = SIZE[shell];
    let p;
    if (shell === "mini") p = where.mini || defaultPos("mini");
    else p = besideLauncher(where.mini || defaultPos("mini"));
    p = clampPos(p, w, hgt);
    root.style.width = w + "px";
    root.style.height = hgt + "px";
    root.style.left = p[0] + "px";
    root.style.top = p[1] + "px";
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
        icon("ear", { cls: "pw-ear l" }), icon("ear-r", { cls: "pw-ear r" }),
        h("div", { class: "pw-case-top" }));
      setChildren(titleText,
        h("span", { class: "pw-clock" }, (state.snap && state.snap.time) || ""),
        h("span", { class: "pw-grip" }, h("i"), h("i"), h("i")),
        h("span", { class: "pw-status" }));
    } else {
      setChildren(deco);
      setChildren(titleText);
    }
  }

  // The launcher is dragged by hand (window.js only moves the phone's title bar): a press that
  // moves is a drag, a press that stays put opens the phone.
  let drag = null;
  function launcherOf(el) {
    while (el && el !== document) {
      if (el.className && String(el.className).indexOf("pw-launch") >= 0) return el;
      el = el.parentNode;
    }
    return null;
  }
  document.addEventListener("mousedown", (e) => {
    if (state.shell !== "mini" || !launcherOf(e.target)) return;
    drag = { x: e.clientX, y: e.clientY, left: parseFloat(root.style.left) || 0, top: parseFloat(root.style.top) || 0, moved: false };
  });
  document.addEventListener("mousemove", (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!drag.moved && Math.abs(dx) + Math.abs(dy) < 5) return;
    drag.moved = true;
    root._wasDragged = true;
    const p = clampPos([drag.left + dx, drag.top + dy], SIZE.mini[0], SIZE.mini[1]);
    root.style.left = p[0] + "px";
    root.style.top = p[1] + "px";
  });
  document.addEventListener("mouseup", () => {
    if (!drag) return;
    const d = drag;
    drag = null;
    if (d.moved) {
      where.mini = [parseFloat(root.style.left), parseFloat(root.style.top)];
      if (typeof root._saveWindowState === "function") root._saveWindowState();
    } else {
      setShell("phone");
    }
  });

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
        class: "btn", disabled: !r.ready, style: "margin-top:8px;width:100%",
        onclick: async () => { await call("redeem", { petId: pet.id }); render(); },
      }, r.ready ? u.redeem : fmt(u.redeem_wait, { hours: r.waitHours })));
  }

  function renderIllness(pet, u) {
    const ill = pet.illness;
    return h("div", { class: "ill" },
      h("div", { class: "section-title" }, icon("vet"), h("span", {}, ill.name)),
      h("div", { class: "sub" }, ill.desc),
      h("button", {
        class: "btn", style: "margin-top:6px;width:100%",
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
        h("div", { class: "avatar" }, icon(away ? "shelter" : "cat", { mood: pet.mood, coat: pet.coat })),
        h("div", {},
          h("h2", { text: pet.name }),
          h("div", { class: "sub" }, `${pet.stageLabel} · ${pet.ageLabel}`),
          away ? h("div", { class: "away" }, pet.statusLabel) : h("span", { class: "mood" }, pet.moodLabel))),
      !away && pet.want ? h("div", { class: "thought" }, icon(WANT_ICON[pet.want.id] || "paw"),
        h("div", {}, h("div", {}, pet.want.text), h("div", { class: "sub" }, u.want_hint))) : null,
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
        h("span", { class: "val sub", style: "width:28px;text-align:right" }, pet.bond)));
  }

  function traitsCard(pet, view) {
    const u = view.ui;
    return h("section", { class: "card" },
      h("div", { class: "section-title" }, icon("get_to_know"), h("span", { class: "grow" }, u.traits), h("span", { class: "sub" }, view.training.label)),
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
          h("button", { class: "btn", style: "margin-top:8px", onclick: () => { state.tab = "adopt"; render(); } }, u.adopt)));
    }
    const pet = currentPet();
    state.petId = pet.id;
    const noBox = pet.status === "home" && pet.litterBox === false;
    return h("div", {},
      backupCard(view),
      view.pets.length > 1
        ? h("div", { class: "chips", style: "margin-bottom:6px" }, view.pets.map((p) =>
            h("button", { class: "chip pet", "aria-pressed": p.id === pet.id, onclick: () => { state.petId = p.id; render(); } },
              icon("cat", { mood: p.mood, coat: p.coat }), p.name)))
        : null,
      petCard(pet, u),
      pet.status === "home" ? h("div", { class: "card tip" }, h("div", { class: "sub" }, u.tip),
        noBox
          ? [h("div", { class: "sub", style: "margin-top:4px" }, u.litter_hint),
             h("button", { class: "btn", style: "margin-top:6px;width:100%",
               onclick: async () => { await call("placeLitterBox", {}); render(); } }, u.place_litter)]
          : h("button", { class: "btn ghost", style: "margin-top:6px;width:100%",
              onclick: async () => { await call("perform", { petId: pet.id, action: "clean_litter" }); render(); } }, u.use_litter)) : null,
      traitsCard(pet, view),
      furnitureCard(view));
  }

  // the cat's coat is random: what you see is what you get
  function renderOffer(o, u) {
    const input = h("input", { type: "text", value: o.name, maxlength: 24, "aria-label": u.name_label });
    return h("div", { class: "cell" }, h("section", { class: "card offer" },
      h("div", { class: "who" },
        h("div", { class: "avatar" }, icon("cat", { mood: "content", coat: o.coat })),
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

  // the gifts the cats brought (real items that went into the Zoi's bag)
  function renderAlbum(view) {
    const u = view.ui, a = view.album || { items: [], owned: 0, total: 0 };
    return h("div", {},
      h("section", { class: "card" },
        h("div", { class: "album-top" }, icon("album"),
          h("div", {}, h("b", {}, u.album), h("div", { class: "sub" }, fmt(u.album_progress, { owned: a.owned, total: a.total })))),
        h("div", { class: "sub", style: "margin-bottom:8px" }, u.album_hint),
        h("div", { class: "album" }, a.items.map((it) =>
          h("div", { class: "gift r-" + it.rarity + (it.owned ? "" : " locked") },
            h("div", { class: "tile", title: it.rarityLabel },
              icon(it.owned ? it.id : "mystery"),
              h("span", { class: "nm" }, it.name),
              it.owned ? h("span", { class: "rar" }, it.rarityLabel) : null,
              it.count > 1 ? h("span", { class: "cnt" }, "x" + it.count) : null))))));
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
    return h("div", { class: "devbar" },
      h("span", { style: "width:100%" }, "Preview tools · 預覽工具"),
      adv("+1h", 60), adv("+6h", 360), adv("+1d", 1440), adv("+3d", 4320),
      h("button", { class: "btn ghost", onclick: async () => { state.offers = state.strays = null; state.petId = null; await call("reset", { locale: state.snap.view.locale }); render(); } }, "Reset"),
      h("button", { class: "btn ghost", onclick: async () => { await call("sicken", { id: "fleas" }); render(); } }, "sick"),
      h("button", { class: "btn ghost", onclick: async () => { await call("fakeBackup", {}); state.petId = null; render(); } }, "backup"),
      h("button", { class: "btn ghost", onclick: () => openEntry({ tab: "adopt", stray: "s2" }) }, "cat menu"));
  }

  function body(view) {
    const u = view.ui;
    if (view.noSave && state.tab !== "settings") return h("div", { class: "card empty" }, icon("cat", { mood: "sleep" }), u.no_save);
    return state.tab === "pets" ? renderPets(view) : state.tab === "adopt" ? renderAdopt(view)
      : state.tab === "album" ? renderAlbum(view) : renderSettings(view);
  }

  function tabButtons(u) {
    return TABS.map(([id, ic]) => h("button", {
      class: "tab", role: "tab", "aria-selected": state.tab === id,
      onclick: async () => { state.tab = id; await render(); },
    }, icon(ic, { mood: id === "pets" && currentPet() ? currentPet().mood : null, coat: id === "pets" && currentPet() ? currentPet().coat : null }),
      h("span", {}, u[id])));
  }

  function launcher() {
    const pet = currentPet();
    const alert = pets().some((p) => p.status === "impounded" || p.illness || p.needs.some((n) => n.state === "critical"));
    const wants = pets().some((p) => p.want);
    return h("div", { class: "pw-launch", title: ui().open || "", "aria-label": ui().open || "", role: "button" },
      icon("cat", { mood: pet ? pet.mood : "content", coat: pet ? pet.coat : null }),
      h("span", { class: "pw-badge" + (alert ? " alert" : wants ? " want" : "") }, icon("paw")));
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
    if (state.shell === "mini") {
      setChildren(app, launcher());
      return;
    }
    const scroller = h("div", { class: "pw-body", "data-tab": state.tab }, body(view), renderDevBar());
    setChildren(app,
      h("header", { class: "pw-head" },
        icon("cat", { cls: "pw-mascot", mood: currentPet() ? currentPet().mood : "happy", coat: currentPet() ? currentPet().coat : null }),
        h("div", { class: "pw-brand" }, h("b", {}, view.title), h("span", {}, u.tagline)),
        coins()),
      scroller,
      h("nav", { class: "pw-tabs", role: "tablist" }, tabButtons(u)));
    scroller.scrollTop = keep;
  }

  // ------------------------------------------------------------ entry points
  // An entry opens the phone on a tab; `stray` is the city cat the player picked in the world.
  function openEntry(e) {
    if (e.tab) state.tab = e.tab;
    if (e.stray != null) { state.focusStray = e.stray; state.strays = null; }
    setShell("phone");
  }
  // the interaction-menu triggers in uimod_manifest.json (mod/modkit/ui), keyed by trigger id
  const TRIGGERS = {
    pawhome_phone: {},
    pawhome_cat: { tab: "adopt" },
  };
  if (window.inzoi && window.inzoi.trigger) {
    window.inzoi.trigger.onActivated((t) => {
      const id = t && (t.triggerId || t.trigger_id || t.id);
      const e = TRIGGERS[id];
      if (!e) return;
      const target = t.target_entity_id || t.targetEntityId || t.entity_id || null;
      openEntry({ tab: e.tab, stray: e.tab === "adopt" && target != null ? "cat" + target : null });
    });
  }
  // The Lua side opens the shop with "pawhome:open" (a JSON entry such as {"tab":"adopt"}),
  // e.g. when the Zoi starts our phone interaction or "adopt" on a city cat (bridge.js SHOP_DATA).
  if (Bridge.onOpen) Bridge.onOpen((e) => openEntry(e || {}));

  // Keep the mood, the cat's wants and the badge current: care happens in the game, so the page
  // has to ask. Often while the phone is open, rarely behind the launcher. Skipped while the
  // player types a name or drags the launcher, so a refresh never wipes an input.
  function refreshLoop() {
    const typing = document.activeElement && /INPUT|SELECT/.test(document.activeElement.tagName);
    const idle = !state.snap || typing || drag || Bridge.preview;
    const next = state.shell === "mini" ? 20000 : 4000;
    if (idle) { setTimeout(refreshLoop, next); return; }
    call("view", {}).then((d) => { if (d) render(); }).then(() => setTimeout(refreshLoop, next));
  }
  setTimeout(refreshLoop, 4000);

  // The game's browser does not pass the page font on to form controls (font-family: inherit
  // has no effect there), so copy the body's font to them.
  try {
    const ff = window.getComputedStyle(document.body).fontFamily;
    if (ff) {
      const st = document.createElement("style");
      st.textContent = "button, input, select, option { font-family: " + ff + "; }";
      document.head.appendChild(st);
    }
  } catch (e) { /* keep the default */ }

  // start: in the game as the launcher once window.js has restored its saved window state
  const startShell = Bridge.preview ? "phone" : "mini";
  function start(tries) {
    if (document.body && document.body.style.visibility === "hidden" && tries > 0) {
      setTimeout(() => start(tries - 1), 150);
      return;
    }
    // the position window.js restored is where the player left the launcher
    if (!Bridge.preview && root.style.left && root.offsetWidth <= 120) where.mini = [parseFloat(root.style.left), parseFloat(root.style.top)];
    setShell(startShell);
  }
  start(30);
  // desktop preview: keep the window on screen when the browser is resized (window.js does this in the game)
  if (Bridge.preview) window.addEventListener("resize", () => setShell(state.shell));
})();
