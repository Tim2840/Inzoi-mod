// Paw Home's own icon set: original drawings, no emoji, no stock icons.
// Style: "sticker" icons on a 48x48 grid, warm brown ink outline (2.5) over flat pastel fills.
// Every icon is a plain SVG string, shown as <img src="data:image/svg+xml,..."> so it works in
// the game's browser (Coherent Gameface) as well as in desktop browsers.
const Icons = (() => {
  const INK = "#4a2f23";
  const C = {
    cream: "#fff1dc", peach: "#ffb199", rose: "#ff7a93", blush: "#ffb3c1", honey: "#ffc857",
    amber: "#d9952b", sky: "#8ec5ff", mint: "#9ed9c3", leaf: "#6bbf9f", lilac: "#c6b3f0",
    sand: "#f2d6a2", kibble: "#e9a55b", wood: "#c98b5a", steel: "#b9c6dc", paper: "#ffffff",
    pink: "#f7a1c4", stripe: "#e9a066", bubble: "#e6f2ff", alarm: "#e5566f",
  };
  // stroke attributes; fill first
  const s = (fill, width) =>
    `fill="${fill}" stroke="${INK}" stroke-width="${width || 2.5}" stroke-linejoin="round" stroke-linecap="round"`;
  const line = (width, color) =>
    `fill="none" stroke="${color || INK}" stroke-width="${width || 2.5}" stroke-linejoin="round" stroke-linecap="round"`;

  // ---------------------------------------------------------------- the mascot: Mochi the cat
  const EYES = {
    content: `<ellipse cx="18" cy="25" rx="2.2" ry="2.8" fill="${INK}"/><ellipse cx="30" cy="25" rx="2.2" ry="2.8" fill="${INK}"/>`
      + `<circle cx="18.8" cy="24" r="0.8" fill="#fff"/><circle cx="30.8" cy="24" r="0.8" fill="#fff"/>`,
    happy: `<path d="M15.5 26 Q18 22.2 20.5 26 M27.5 26 Q30 22.2 32.5 26" ${line(2.3)}/>`,
    sleep: `<path d="M15.5 25 Q18 27.6 20.5 25 M27.5 25 Q30 27.6 32.5 25" ${line(2.3)}/>`,
    sad: `<ellipse cx="18" cy="26" rx="2" ry="2.4" fill="${INK}"/><ellipse cx="30" cy="26" rx="2" ry="2.4" fill="${INK}"/>`
      + `<path d="M15 21.2 L20.5 19.4 M27.5 19.4 L33 21.2" ${line(2)}/>`
      + `<path d="M32 29 Q30.4 31.6 32 32.8 Q33.6 31.6 32 29 Z" fill="${C.sky}"/>`,
    grumpy: `<ellipse cx="18" cy="26" rx="2" ry="2.2" fill="${INK}"/><ellipse cx="30" cy="26" rx="2" ry="2.2" fill="${INK}"/>`
      + `<path d="M15 20 L20.5 22 M27.5 22 L33 20" ${line(2)}/>`,
    sick: `<path d="M15.5 25.5 L20.5 25.5 M27.5 25.5 L32.5 25.5" ${line(2.3)}/>`
      + `<rect x="25.5" y="14" width="9.5" height="4.6" rx="2.2" transform="rotate(-18 30 16)" ${s("#ffe3b3", 1.4)}/>`
      + `<path d="M35.5 21 Q34 23.5 35.5 24.6 Q37 23.5 35.5 21 Z" fill="${C.sky}"/>`,
  };
  const MOUTH = {
    content: `<path d="M24 30.6 Q22.6 33.4 20.4 32.2 M24 30.6 Q25.4 33.4 27.6 32.2" ${line(1.8)}/>`,
    sad: `<path d="M21 33.4 Q24 31 27 33.4" ${line(1.8)}/>`,
    grumpy: `<path d="M21.4 32.6 H26.6" ${line(1.8)}/>`,
    sick: `<path d="M20.4 33 Q22.2 31.6 24 33 Q25.8 34.4 27.6 33" ${line(1.8)}/>`,
  };
  const FACE_OF = {
    happy: "happy", playful: "happy", energized: "happy", content: "content", asleep: "sleep",
    sad: "sad", uncomfortable: "grumpy", tense: "grumpy", angry: "grumpy", sick: "sick",
  };
  // fur of the four game coats (data/coats.lua ids); anything else is the plain cream cat
  const COAT = {
    orange_tabby: { fur: "#f2a65e", stripe: "#c97a2e", ear: "#ffb199" },
    brown_tabby: { fur: "#b98d66", stripe: "#7d5535", ear: "#e2a99a" },
    calico: { fur: "#fff4e4", stripe: "#e9a066", ear: "#ffb3c1" },
    tuxedo: { fur: "#4f5262", stripe: "#3b3d4b", ear: "#f7a1c4" },
  };
  // extra markings drawn over the head (calico patches, the tuxedo's white muzzle)
  const MARKS = {
    calico: `<path d="M10 21 L11.5 8.5 Q12.2 6 14.5 7.2 L21 12.2 Q17 16 15 24 Q11 24 10 21 Z" fill="#f2a65e"/>`
      + `<path d="M38 21 L36.5 8.5 Q35.8 6 33.5 7.2 L30 10.4 Q35 14 35.5 22 Q37.5 22 38 21 Z" fill="#6b5a52"/>`
      + `<ellipse cx="33" cy="35" rx="5.5" ry="4" fill="#f2a65e"/>`,
    tuxedo: `<ellipse cx="24" cy="31" rx="12.5" ry="10.5" fill="#ffffff"/>`
      + `<path d="M24 14 L27 24 H21 Z" fill="#ffffff"/>`,
  };

  function cat(mood, coat) {
    const face = FACE_OF[mood] || (EYES[mood] ? mood : "content");
    const k = COAT[coat] || { fur: C.cream, stripe: C.stripe, ear: C.peach };
    return `<path d="M10 21 L11.5 8.5 Q12.2 6 14.5 7.2 L21 12.2 Q24 11.6 27 12.2 L33.5 7.2 Q35.8 6 36.5 8.5 L38 21 Q41.5 28 37.5 34 Q32.5 41.5 24 41.5 Q15.5 41.5 10.5 34 Q6.5 28 10 21 Z" ${s(k.fur)}/>`
      + (MARKS[coat] || "")
      + `<path d="M14 11 L19.5 14.5 L14.8 17.5 Z M34 11 L28.5 14.5 L33.2 17.5 Z" fill="${k.ear}"/>`
      + (coat === "tuxedo" ? "" : `<path d="M21 14.6 L21.9 17.6 M24 13.8 V17.4 M27 14.6 L26.1 17.6" ${line(1.8, k.stripe)}/>`)
      + `<circle cx="14.4" cy="30.6" r="2.6" fill="${C.blush}"/><circle cx="33.6" cy="30.6" r="2.6" fill="${C.blush}"/>`
      + EYES[face]
      + `<path d="M22.4 28.6 H25.6 L24 30.6 Z" ${s("#f2738c", 1.2)}/>`
      + (MOUTH[face] || MOUTH.content);
  }

  // ---------------------------------------------------------------- generated shapes
  function star(cx, cy, R, r) {
    let d = "";
    for (let k = 0; k < 10; k++) {
      const a = (-90 + k * 36) * Math.PI / 180, rad = k % 2 ? r : R;
      d += (k ? " L" : "M") + (cx + rad * Math.cos(a)).toFixed(1) + " " + (cy + rad * Math.sin(a)).toFixed(1);
    }
    return d + " Z";
  }
  function gearTeeth() {
    let out = "";
    for (let k = 0; k < 8; k++) {
      out += `<rect x="20.5" y="3.5" width="7" height="10" rx="2.4" transform="rotate(${k * 45} 24 24)" ${s(C.steel)}/>`;
    }
    return out;
  }
  const bubble = (fill) =>
    `<path d="M8 12 Q8 7 13 7 H35 Q40 7 40 12 V26 Q40 31 35 31 H22.5 L14.5 38.5 V31 H13 Q8 31 8 26 Z" ${s(fill)}/>`;

  // ---------------------------------------------------------------- the set
  const ICONS = {
    paw: `<ellipse cx="11.5" cy="22.5" rx="4" ry="5" transform="rotate(-22 11.5 22.5)" ${s(C.peach)}/>`
      + `<ellipse cx="19" cy="13.8" rx="4.3" ry="5.4" transform="rotate(-8 19 13.8)" ${s(C.peach)}/>`
      + `<ellipse cx="29" cy="13.8" rx="4.3" ry="5.4" transform="rotate(8 29 13.8)" ${s(C.peach)}/>`
      + `<ellipse cx="36.5" cy="22.5" rx="4" ry="5" transform="rotate(22 36.5 22.5)" ${s(C.peach)}/>`
      + `<path d="M24 41.5 C16 41.5 12.5 37 14.6 32.4 C16.6 28 20 25.6 24 25.6 C28 25.6 31.4 28 33.4 32.4 C35.5 37 32 41.5 24 41.5 Z" ${s(C.peach)}/>`,
    adopt: `<path d="M12.6 18.6 L13 9.5 L19.5 13.6 Z M35.4 18.6 L35 9.5 L28.5 13.6 Z" ${s(C.sand)}/>`
      + `<path d="M9 21.5 L24 9.5 L39 21.5 V38.5 Q39 41 36.5 41 H11.5 Q9 41 9 38.5 Z" ${s(C.sand)}/>`
      + `<path d="M24 35.5 C18 31.5 16.6 28 18.6 25.6 C20.4 23.6 23 24.2 24 26.4 C25 24.2 27.6 23.6 29.4 25.6 C31.4 28 30 31.5 24 35.5 Z" ${s(C.rose, 2)}/>`,
    food: `<path d="M11 26 Q12.5 19.5 18 21 Q21 16.5 25.5 19.5 Q30.5 16.5 33 21 Q37.5 20 37 26 Z" ${s(C.kibble)}/>`
      + `<path d="M6.5 26 H41.5 Q41 37.5 31 40.5 H17 Q7 37.5 6.5 26 Z" ${s(C.sky)}/>`
      + `<path d="M18.5 32.5 Q23 28.8 27.5 32.5 Q23 36.2 18.5 32.5 Z M27.5 32.5 L31 30 V35 Z" ${s(C.paper, 1.6)}/>`,
    play: `<circle cx="23" cy="23" r="14" ${s(C.pink)}/>`
      + `<path d="M12.5 15.5 Q23 21 33 12.5 M9.6 24.5 Q23 28 36.6 19.5 M12.8 32 Q24 34 35.4 27" ${line(1.8)}/>`
      + `<path d="M34.5 33.5 Q41 36 39.6 40.4 Q38.6 44 43.4 44.4" ${line(2.5)}/>`,
    litter: `<path d="M33 5.5 L37.6 15" ${line(3)}/>`
      + `<path d="M33.5 14 L41.5 10.5 L44.5 17.5 L37 21 Z" ${s(C.paper)}/>`
      + `<path d="M8.5 24 Q12 19.5 16.5 22.5 Q20.5 18.5 25 21.5 Q29.5 18.5 33 21.5 Q37 19.5 39.5 24 Z" ${s(C.sand)}/>`
      + `<path d="M5.5 24 H42.5 L39.5 39.5 Q39 41.5 36.8 41.5 H11.2 Q9 41.5 8.5 39.5 Z" ${s(C.mint)}/>`
      + `<circle cx="24" cy="34.4" r="3" fill="${C.leaf}"/><circle cx="19.8" cy="30.2" r="1.4" fill="${C.leaf}"/>`
      + `<circle cx="22.6" cy="28.6" r="1.4" fill="${C.leaf}"/><circle cx="25.4" cy="28.6" r="1.4" fill="${C.leaf}"/>`
      + `<circle cx="28.2" cy="30.2" r="1.4" fill="${C.leaf}"/>`,
    energy: `<path d="M27 6.5 A17.5 17.5 0 1 0 41.5 31 A14 14 0 0 1 27 6.5 Z" ${s(C.lilac)}/>`
      + `<circle cx="18" cy="27" r="1.6" fill="${INK}"/><path d="M14.5 32 Q17 34 19.5 32" ${line(1.6)}/>`
      + `<path d="M31 8 H37 L31 14 H37" ${line(2.2)}/><path d="M39.5 17 H43 L39.5 20.5 H43" ${line(1.8)}/>`,
    heart: `<path d="M24 41 C10.5 32.5 5.5 24.5 8.5 16.5 C11.5 9.5 20 8.8 24 15.2 C28 8.8 36.5 9.5 39.5 16.5 C42.5 24.5 37.5 32.5 24 41 Z" ${s(C.rose)}/>`
      + `<ellipse cx="15" cy="18" rx="2.4" ry="3.6" transform="rotate(30 15 18)" fill="#fff" opacity="0.75"/>`,
    coin: `<circle cx="24" cy="24" r="17" ${s(C.honey)}/>`
      + `<circle cx="24" cy="24" r="12.5" fill="none" stroke="${C.amber}" stroke-width="2"/>`
      + `<ellipse cx="24" cy="28.4" rx="5" ry="4" fill="${C.amber}"/>`
      + `<circle cx="18.6" cy="22.6" r="2" fill="${C.amber}"/><circle cx="22" cy="19.4" r="2" fill="${C.amber}"/>`
      + `<circle cx="26" cy="19.4" r="2" fill="${C.amber}"/><circle cx="29.4" cy="22.6" r="2" fill="${C.amber}"/>`,
    settings: gearTeeth()
      + `<circle cx="24" cy="24" r="13.5" ${s(C.steel)}/>`
      + `<path d="M18.5 22 L19 15.8 L22 18.4 H26 L29 15.8 L29.5 22 Q31 28 24 30.6 Q17 28 18.5 22 Z" ${s(C.cream, 2)}/>`
      + `<circle cx="21.6" cy="23.2" r="1.1" fill="${INK}"/><circle cx="26.4" cy="23.2" r="1.1" fill="${INK}"/>`,
    shelter: `<path d="M4 40.5 H44" ${line(2.5)}/>`
      + `<path d="M7 40.5 V19 L24 8 L41 19 V40.5 Z" ${s("#ffe3b3")}/>`
      + `<path d="M19.5 40.5 V32 Q19.5 27.5 24 27.5 Q28.5 27.5 28.5 32 V40.5 Z" ${s(C.wood)}/>`
      + `<circle cx="24" cy="18.5" r="5" ${s(C.paper, 2)}/>`
      + `<path d="M24 15.8 V21.2 M21.3 18.5 H26.7" ${line(2.2, "#f2738c")}/>`,
    close: `<circle cx="24" cy="24" r="17" ${s("#ffe1e6")}/>`
      + `<path d="M17.5 17.5 L30.5 30.5 M30.5 17.5 L17.5 30.5" ${line(3.5)}/>`,
    cuddle: `<path d="M24 36 C13 29 9.5 22.5 12 16.5 C14.5 11 21 10.6 24 15.6 C27 10.6 33.5 11 36 16.5 C38.5 22.5 35 29 24 36 Z" ${s(C.rose)}/>`
      + `<circle cx="12.5" cy="34" r="5.5" ${s(C.cream)}/><circle cx="35.5" cy="34" r="5.5" ${s(C.cream)}/>`
      + `<path d="M10.5 31.5 V33.5 M13.5 31 V33 M33.5 31.5 V33.5 M36.5 31 V33" ${line(1.4)}/>`,
    groom: `<rect x="5" y="30" width="22" height="7" rx="3.5" transform="rotate(-45 16 33.5)" ${s(C.wood)}/>`
      + `<rect x="19" y="9" width="22" height="14" rx="6" transform="rotate(-45 30 16)" ${s(C.mint)}/>`
      + `<path d="M25.5 15.5 L27.5 13.5 M29 19 L31 17 M32.5 22.5 L34.5 20.5 M29 12 L31 10 M32.5 15.5 L34.5 13.5" ${line(1.8)}/>`,
    praise: `<path d="${star(24, 25, 18, 8.2)}" ${s("#ffd166")}/>`
      + `<circle cx="20.5" cy="25" r="1.4" fill="${INK}"/><circle cx="27.5" cy="25" r="1.4" fill="${INK}"/>`
      + `<path d="M21.6 28.4 Q24 30.6 26.4 28.4" ${line(1.6)}/>`,
    scold: bubble(C.paper)
      + `<path d="M24 12.5 V20.5" ${line(3.6, C.alarm)}/><circle cx="24" cy="25.5" r="2.1" fill="${C.alarm}"/>`,
    get_to_know: bubble(C.bubble)
      + `<path d="M19.6 15 Q19.6 10.6 24 10.6 Q28.4 10.6 28.4 14.4 Q28.4 17.4 24 18.8 V20.6" ${line(3)}/>`
      + `<circle cx="24" cy="25.4" r="1.9" fill="${INK}"/>`,
    vet: `<path d="M18 15 V11.5 Q18 8 21.5 8 H26.5 Q30 8 30 11.5 V15" ${line(2.5)}/>`
      + `<rect x="6" y="15" width="36" height="26" rx="6" ${s(C.paper)}/>`
      + `<path d="M6 22 H42" ${line(2)}/>`
      + `<path d="M24 25.5 V36.5 M18.5 31 H29.5" ${line(4, "#f2738c")}/>`,
    CatScratcher01: `<path d="M30 12 L36.5 20" ${line(1.8)}/><circle cx="37.5" cy="22.5" r="3" ${s(C.rose, 2)}/>`
      + `<rect x="18" y="9" width="12" height="30" rx="2.5" ${s(C.sand)}/>`
      + `<path d="M18 15 L30 18 M18 21 L30 24 M18 27 L30 30 M18 33 L30 36" ${line(1.6, C.wood)}/>`
      + `<rect x="8" y="38" width="32" height="6" rx="3" ${s(C.wood)}/>`,
    CatTower01: `<rect x="12" y="14" width="5" height="27" ${s(C.sand, 2)}/><rect x="31" y="24" width="5" height="17" ${s(C.sand, 2)}/>`
      + `<rect x="5" y="9" width="21" height="6.5" rx="3.2" ${s(C.pink)}/>`
      + `<rect x="23" y="19.5" width="21" height="6.5" rx="3.2" ${s(C.lilac)}/>`
      + `<path d="M9 9 L10.5 4.5 L13.5 8 M18 8 L20.5 4.5 L22 9" ${s(C.cream, 1.8)}/>`
      + `<rect x="5" y="40" width="38" height="5" rx="2.5" ${s(C.wood)}/>`,
    CatWheel01: `<path d="M13 44 L24 26 L35 44" ${line(3)}/>`
      + `<circle cx="24" cy="22" r="17" ${s(C.sky)}/><circle cx="24" cy="22" r="11.5" ${s(C.cream, 2)}/>`
      + `<path d="M24 10.5 V33.5 M12.5 22 H35.5" ${line(1.6, C.steel)}/>`
      + `<circle cx="24" cy="22" r="2.4" fill="${INK}"/>`,
    phone: `<rect x="13" y="5" width="22" height="38" rx="6" ${s(C.blush)}/>`
      + `<rect x="16.5" y="10" width="15" height="26" rx="3" fill="${C.cream}"/>`
      + `<ellipse cx="24" cy="25" rx="3.4" ry="2.8" fill="${C.peach}"/><circle cx="20.4" cy="21" r="1.4" fill="${C.peach}"/>`
      + `<circle cx="23" cy="19.4" r="1.4" fill="${C.peach}"/><circle cx="25.6" cy="19.4" r="1.4" fill="${C.peach}"/>`
      + `<circle cx="27.6" cy="21" r="1.4" fill="${C.peach}"/><path d="M21.5 39.5 H26.5" ${line(2)}/>`,
    // ---- keepsakes: the little gifts a cat brings (album)
    feather: `<path d="M10 41 Q10 18 36 7 Q42 26 24 37 Q17 41 10 41 Z" ${s("#c6b3f0")}/>`
      + `<path d="M10 41 Q22 24 35 10" ${line(2)}/><path d="M17 31 L24 33 M21 25 L29 27 M26 19 L33 21" ${line(1.6)}/>`,
    yarn: `<circle cx="22" cy="23" r="15" ${s(C.pink)}/>`
      + `<path d="M9 19 Q22 27 35 15 M8 26 Q22 33 36 22 M12 12 Q24 19 33 10" ${line(1.8)}/>`
      + `<path d="M31 35 Q40 36 38 42 Q36 46 43 44" ${line(2.4)}/>`,
    leaf: `<path d="M9 39 Q5 13 37 8 Q43 37 14 40 Z" ${s(C.leaf)}/>`
      + `<path d="M9 39 Q22 25 36 11" ${line(2)}/><path d="M18 31 L16 24 M25 25 L24 18 M30 19 L34 19" ${line(1.6)}/>`,
    button: `<circle cx="24" cy="24" r="17" ${s(C.sky)}/>`
      + `<circle cx="24" cy="24" r="11" fill="none" stroke="${INK}" stroke-width="1.6"/>`
      + `<circle cx="20.5" cy="21" r="2" fill="${INK}"/><circle cx="27.5" cy="21" r="2" fill="${INK}"/>`
      + `<circle cx="20.5" cy="28" r="2" fill="${INK}"/><circle cx="27.5" cy="28" r="2" fill="${INK}"/>`,
    pebble: `<path d="M7 31 Q5 19 17 15 Q33 9 41 23 Q45 36 31 38 Q12 42 7 31 Z" ${s("#d9d2e3")}/>`
      + `<path d="M15 22 Q19 18 24 18" ${line(2, "#ffffff")}/><circle cx="31" cy="30" r="1.5" fill="#b9b0c8"/>`,
    bell: `<circle cx="24" cy="8.5" r="3.5" ${s(C.honey, 2)}/>`
      + `<path d="M11 33 Q11 13 24 12 Q37 13 37 33 Z" ${s(C.honey)}/>`
      + `<path d="M8 34 H40" ${line(3)}/><circle cx="24" cy="38.5" r="3.4" ${s(C.amber, 2)}/>`
      + `<path d="M17 24 Q18 18 22 16" ${line(2, "#fff4cf")}/>`,
    fishbone: `<path d="M9 24 H35" ${line(2.6)}/>`
      + `<path d="M15 24 L11 14 M22 24 L18 12 M29 24 L25 14 M15 24 L11 34 M22 24 L18 36 M29 24 L25 34" ${line(2.2)}/>`
      + `<path d="M35 18 Q44 20 44 24 Q44 28 35 30 Q31 24 35 18 Z" ${s(C.paper)}/>`
      + `<path d="M9 24 L3 17 L3 31 Z" ${s(C.paper, 2)}/><circle cx="40" cy="22.5" r="1.3" fill="${INK}"/>`,
    mouse: `<path d="M12 33 Q8 41 3 40" ${line(2.4)}/>`
      + `<ellipse cx="23" cy="29" rx="15" ry="10.5" ${s("#cfd6e6")}/>`
      + `<circle cx="31" cy="17" r="5.5" ${s(C.blush, 2)}/><circle cx="38" cy="22" r="4.6" ${s(C.blush, 2)}/>`
      + `<circle cx="34" cy="28" r="1.7" fill="${INK}"/><circle cx="39.5" cy="31" r="1.9" fill="#f2738c"/>`,
    flower: `<path d="M24 28 V43" ${line(2.6)}/><path d="M24 36 Q31 31 36 35" ${line(2.2)}/>`
      + `<circle cx="24" cy="10.5" r="6.2" ${s(C.pink, 2)}/><circle cx="35.5" cy="18" r="6.2" ${s(C.pink, 2)}/>`
      + `<circle cx="31.5" cy="30" r="6.2" ${s(C.pink, 2)}/><circle cx="16.5" cy="30" r="6.2" ${s(C.pink, 2)}/>`
      + `<circle cx="12.5" cy="18" r="6.2" ${s(C.pink, 2)}/><circle cx="24" cy="22" r="6" ${s(C.honey, 2)}/>`,
    star: `<path d="M24 3 V8" ${line(2.4)}/><circle cx="24" cy="5" r="2.6" ${s(C.honey, 1.6)}/>`
      + `<path d="${star(24, 28, 17, 7.6)}" ${s("#ffd166")}/><path d="M19 24 L23 22" ${line(2, "#fff6d6")}/>`,
    album: `<rect x="8" y="6" width="32" height="36" rx="5" ${s(C.peach)}/>`
      + `<path d="M13 6 V42" ${line(2)}/>`
      + `<ellipse cx="27" cy="27" rx="5.2" ry="4.2" ${s(C.cream, 1.8)}/>`
      + `<circle cx="21.5" cy="20.5" r="2" ${s(C.cream, 1.6)}/><circle cx="25.2" cy="18" r="2" ${s(C.cream, 1.6)}/>`
      + `<circle cx="29.2" cy="18" r="2" ${s(C.cream, 1.6)}/><circle cx="32.8" cy="20.5" r="2" ${s(C.cream, 1.6)}/>`,
    mystery: `<rect x="9" y="9" width="30" height="30" rx="8" ${s("#d8cdbf")}/>`
      + `<path d="M18.5 20 Q18.5 13.5 24 13.5 Q29.5 13.5 29.5 19 Q29.5 22.5 24 25 V28" ${line(3)}/>`
      + `<circle cx="24" cy="33.5" r="2" fill="${INK}"/>`,
  };
  // aliases used by the engine's ids
  const ALIAS = {
    feed: "food", hunger: "food", fun: "play", bladder: "litter", clean_litter: "litter",
    bond: "heart", money: "coin", pets: "cat", stray: "cat",
  };

  // the phone case's cat ear (64 x 44); "ear-r" is the mirror image
  function ear(right) {
    const flip = right ? ` transform="translate(64 0) scale(-1 1)"` : "";
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 44" width="64" height="44"><g${flip}>`
      + `<path d="M3 46 Q9 22 17 7 Q20 1.5 25 4.5 Q43 18 62 46 Z" fill="#ffb4c2" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/>`
      + `<path d="M13 44 Q17 26 21 14 Q33 25 47 44 Z" fill="#f58fa3"/></g></svg>`;
  }

  function markup(name, mood, coat) {
    if (name === "ear" || name === "ear-r") return ear(name === "ear-r");
    const key = ALIAS[name] || name;
    const body = key === "cat" ? cat(mood, coat) : ICONS[key];
    if (!body) return null;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">${body}</svg>`;
  }
  const cache = {};
  function url(name, mood, coat) {
    const k = name + "/" + (mood || "") + "/" + (coat || "");
    if (!(k in cache)) {
      const m = markup(name, mood, coat);
      cache[k] = m ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(m) : null;
    }
    return cache[k];
  }
  // Inline <svg> in a <span class="ico">; decorative unless a label is given.
  // In the game's browser inline SVG and .svg files render, but SVG data: URLs do not
  // (verified in game 20261019.16318.W, 2026-10-21), so the page never uses url() for icons.
  function img(name, opts) {
    const o = opts || {};
    const el = document.createElement("span");
    el.className = "ico" + (o.cls ? " " + o.cls : "");
    el.innerHTML = markup(name, o.mood, o.coat) || "";
    if (o.label) { el.setAttribute("role", "img"); el.setAttribute("aria-label", o.label); }
    else el.setAttribute("aria-hidden", "true");
    return el;
  }
  const names = () => Object.keys(ICONS).concat(["cat"]);
  return { img, url, markup, names, moods: Object.keys(EYES), coats: Object.keys(COAT) };
})();
