// How the page talks to the mod.
//  - Desktop preview: HTTP calls to tools/preview_server.py, which runs the real Lua engine.
//  - In the game: TODO(P8) route the same calls to the Lua mod through the CLI bridge
//    (window.inzoi.cli.execute). Method names and payloads stay exactly the same.
const Bridge = (() => {
  const inGame = typeof window.inzoi !== "undefined" && !!window.inzoi.cli;

  async function call(method, args = {}) {
    if (inGame) {
      throw new Error("In-game transport is not implemented yet (see docs/phase0-probe.md, P8)");
    }
    const res = await fetch("/api/" + method, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error(data.error || "HTTP " + res.status);
    return data;
  }

  return { call, preview: !inGame };
})();
