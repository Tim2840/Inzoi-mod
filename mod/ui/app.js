// Paw Home UI. All text comes from the Lua side (view.ui, labels in every pet / offer),
// so adding a language never touches this file.
(() => {
  const ACTION_ICON = {
    feed: "🍗", play: "🧶", cuddle: "🤗", groom: "🧼",
    clean_litter: "🧹", praise: "👍", scold: "☝️", get_to_know: "🔍",
  };
  const MOOD_FACE = {
    happy: "😸", playful: "😼", energized: "😺", content: "🐱", asleep: "😴",
    sad: "😿", uncomfortable: "😾", tense: "🙀", angry: "😾",
  };
  const STAGE_FACE = { kitten: "🐱", adult: "🐈", elder: "🐈‍⬛" };

  const state = { snap: null, tab: "pets", petId: null, offers: null, strays: null, busy: false };
  const root = document.getElementById("app");
  const toasts = document.getElementById("toasts");

  // ------------------------------------------------------------ helpers
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === false || v == null) continue;
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (k === "text") el.textContent = v;
      else el.setAttribute(k, v === true ? "" : v);
    }
    for (const c of children.flat()) {
      if (c == null || c === false) continue;
      el.append(c.nodeType ? c : document.createTextNode(String(c)));
    }
    return el;
  }
  const fmt = (s, params) => String(s).replace(/\{(\w+)\}/g, (_, k) => (params && k in params ? params[k] : `{${k}}`));
  const ui = () => (state.snap && state.snap.view.ui) || {};

  const MAX_TOASTS = 4;
  function toast(text, isError) {
    for (const t of toasts.children) if (t.textContent === text) return; // no duplicates
    const el = h("div", { class: "toast" + (isError ? " err" : "") }, text);
    toasts.append(el);
    while (toasts.children.length > MAX_TOASTS) toasts.firstChild.remove(); // keep the newest
    setTimeout(() => el.remove(), 3600);
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

  // ------------------------------------------------------------ views
  function renderShelter(pet, u) {
    const r = pet.redeem;
    return h("div", { class: "shelter" },
      h("div", { class: "sub" }, fmt(u.shelter_days_left, { days: r.daysLeft })),
      h("div", { class: "fee" }, fmt(u.redeem_fee, { fee: r.fee })),
      h("button", {
        class: "btn", disabled: !r.ready, style: "margin-top:10px;width:100%",
        onclick: async () => { await call("redeem", { petId: pet.id }); render(); },
      }, r.ready ? u.redeem : fmt(u.redeem_wait, { hours: r.waitHours })));
  }

  function renderPet(pet, view) {
    const u = view.ui;
    return h("section", { class: "card", "aria-label": pet.name },
      h("div", { class: "pet-head" },
        h("div", { class: "avatar", "aria-hidden": "true" }, pet.status === "impounded" ? "🚐" : MOOD_FACE[pet.mood] || STAGE_FACE[pet.stage]),
        h("div", {},
          h("h2", { text: pet.name }),
          h("div", { class: "sub" }, `${pet.stageLabel} · ${pet.ageLabel}`),
          pet.status === "impounded"
            ? h("div", { class: "away" }, pet.statusLabel)
            : h("span", { class: "mood" }, pet.moodLabel))),
      pet.status === "impounded" ? renderShelter(pet, u) : h("div", { class: "needs" }, pet.needs.map((n) =>
        h("div", { class: "need", "data-state": n.state },
          h("span", {}, n.label),
          h("div", { class: "bar", role: "progressbar", "aria-label": n.label, "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": n.value },
            h("i", { style: `width:${n.value}%` })),
          h("span", { class: "val" }, n.value)))),
      h("div", { class: "bond" },
        h("div", { class: "bond-row" }, h("span", {}, `${u.bond} · ${pet.bondLabel}`), h("span", { class: "sub" }, pet.bond)),
        h("div", { class: "bar" }, h("i", { style: `width:${pet.bond}%` }))),
      h("div", { class: "section-title" }, u.traits),
      h("div", { class: "chips" }, pet.traits.map((t) =>
        h("span", { class: "chip" + (t.known ? "" : " unknown"), title: t.desc || "" }, t.label))),
      h("div", { class: "section-title" }, view.training.label),
      pet.status === "impounded" ? null : h("div", { class: "actions" }, pet.actions.map((a) =>
        h("button", {
          class: "act", title: a.desc, disabled: !a.ready,
          onclick: async () => { await call("perform", { petId: pet.id, action: a.id }); render(); },
        },
          h("span", { class: "ico", "aria-hidden": "true" }, ACTION_ICON[a.id] || "•"),
          h("span", { class: "lbl" }, a.label),
          a.cooldown > 0 ? h("span", { class: "cd" }, fmt(u.cooldown, { min: a.cooldown })) : null))));
  }

  function renderPets(view) {
    if (view.pets.length === 0) return h("div", { class: "card empty" }, view.ui.no_pets);
    if (!view.pets.some((p) => p.id === state.petId)) state.petId = view.pets[0].id;
    const pet = view.pets.find((p) => p.id === state.petId);
    return h("div", {},
      view.pets.length > 1
        ? h("div", { class: "chips", style: "margin-bottom:12px" }, view.pets.map((p) =>
            h("button", { class: "chip pet", "aria-pressed": p.id === state.petId, onclick: () => { state.petId = p.id; render(); } }, p.name)))
        : null,
      renderPet(pet, view));
  }

  function renderOffer(o, u) {
    const input = h("input", { type: "text", value: o.name, maxlength: 24, "aria-label": u.name_label });
    return h("section", { class: "card offer" },
      h("h3", { text: o.name }),
      h("div", { class: "sub" }, o.stageLabel),
      h("div", { class: "chips", style: "margin-top:8px" }, o.traits.map((t) => h("span", { class: "chip", title: t.desc }, t.label))),
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
      h("div", { class: "fee", style: "margin-top:6px" }, o.fee > 0 ? fmt(u.fee, { fee: o.fee }) : u.free));
  }

  function renderStray(s, u) {
    const input = h("input", { type: "text", placeholder: u.name_label, maxlength: 24, "aria-label": u.name_label });
    return h("section", { class: "card offer" },
      h("div", { class: "sub" }, `${STAGE_FACE[s.stage] || "🐈"} ${s.stage}`),
      h("div", { class: "row" },
        input,
        h("button", {
          class: "btn",
          onclick: async () => {
            const data = await call("adoptStray", { strayId: s.id, name: input.value });
            if (data && data.result && data.result.ok) { state.strays = null; state.tab = "pets"; }
            render();
          },
        }, u.confirm)));
  }

  function renderAdopt(view) {
    const u = view.ui;
    const offers = state.offers || [];
    const strays = state.strays || [];
    return h("div", {},
      h("div", { class: "list-head" },
        h("h3", {}, u.shelter),
        h("button", { class: "btn ghost", onclick: async () => { const d = await call("offers", { refresh: true }); if (d) state.offers = d.offers; render(); } }, u.refresh)),
      offers.length ? offers.map((o) => renderOffer(o, u)) : h("div", { class: "card empty" }, u.no_offers),
      h("div", { class: "list-head", style: "margin-top:18px" }, h("h3", {}, u.stray_cats)),
      strays.length ? strays.map((s) => renderStray(s, u)) : h("div", { class: "card empty" }, u.no_strays));
  }

  function toggle(label, key, settings) {
    const input = h("input", { type: "checkbox", checked: !!settings[key], "aria-label": label,
      onchange: async (e) => { await call("setSetting", { key, value: e.target.checked }); render(); } });
    return h("label", { class: "setting" }, h("span", {}, label), h("span", { class: "switch" }, input, h("span")));
  }

  function slider(label, key, min, max, step, settings) {
    const out = h("span", { class: "sub" }, `×${settings[key]}`);
    const input = h("input", { type: "range", class: "range", min, max, step, value: settings[key], "aria-label": label,
      oninput: (e) => { out.textContent = `×${e.target.value}`; },
      onchange: async (e) => { await call("setSetting", { key, value: Number(e.target.value) }); render(); } });
    return h("div", { class: "setting" }, h("span", {}, label), h("span", { style: "display:flex;gap:8px;align-items:center" }, input, out));
  }

  // Whole-number setting shown as a plain count (not a "×" multiplier).
  function countSlider(label, key, min, max, settings) {
    const out = h("span", { class: "sub" }, String(settings[key]));
    const input = h("input", { type: "range", class: "range", min, max, step: 1, value: settings[key], "aria-label": label,
      oninput: (e) => { out.textContent = e.target.value; },
      onchange: async (e) => { await call("setSetting", { key, value: Number(e.target.value) }); render(); } });
    return h("div", { class: "setting" }, h("span", {}, label), h("span", { style: "display:flex;gap:8px;align-items:center" }, input, out));
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
      slider(u.decay, "needDecayScale", 0.25, 2, 0.25, s),
      slider(u.lifescale, "lifeScale", 0.5, 4, 0.5, s),
      countSlider(u.max_pets_setting, "maxPetsPerHousehold", 1, 4, s));
  }

  function renderDevBar() {
    if (!Bridge.preview) return null;
    const adv = (label, minutes) => h("button", { class: "btn ghost", onclick: async () => { await call("advance", { minutes }); render(); } }, label);
    return h("div", { class: "devbar" },
      h("span", {}, "Preview tools · 預覽工具"),
      adv("+1h", 60), adv("+6h", 360), adv("+1d", 1440), adv("+3d", 4320),
      h("button", { class: "btn ghost", onclick: async () => { state.offers = state.strays = null; state.petId = null; await call("reset", { locale: state.snap.view.locale }); render(); } }, "Reset"));
  }

  async function loadTab() {
    if (state.tab === "adopt" && (state.offers === null || state.strays === null)) {
      const o = await call("offers", {});
      if (o) state.offers = o.offers;
      const s = await call("strays", {});
      if (s) state.strays = s.strays;
    }
  }

  async function render() {
    if (!state.snap) {
      const first = await call("view", {});
      if (!first) return root.replaceChildren(h("p", { class: "empty" }, "Cannot reach the mod."));
    }
    await loadTab();
    const view = state.snap.view, u = view.ui;
    document.documentElement.lang = view.locale === "zh-TW" ? "zh-Hant" : "en";
    document.title = view.title;
    const tab = (id, label) => h("button", {
      class: "tab", role: "tab", "aria-selected": state.tab === id,
      onclick: () => { state.tab = id; render(); },
    }, label);
    const body = view.noSave && state.tab !== "settings" ? h("div", { class: "card empty" }, u.no_save)
      : state.tab === "pets" ? renderPets(view) : state.tab === "adopt" ? renderAdopt(view) : renderSettings(view);
    root.replaceChildren(
      h("header", { class: "top" },
        h("h1", {}, "🐾 " + view.title),
        h("div", { class: "meta" }, `$${state.snap.money}`, h("br"), Bridge.preview ? `Day ${state.snap.day} · ${state.snap.time}` : "")),
      h("nav", { class: "tabs", role: "tablist" }, tab("pets", u.pets), tab("adopt", u.adopt), tab("settings", u.settings)),
      body,
      renderDevBar());
  }

  render();
})();
