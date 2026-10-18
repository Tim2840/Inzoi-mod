"""Desktop preview of the Paw Home UI, backed by the real Lua engine (no game needed).

    pip install lupa
    python3 tools/preview_server.py            # then open http://127.0.0.1:8765/?preview=1

The page's "Preview tools" bar can fast-forward the game clock so you can watch needs
drop, pets grow up, animal control takes neglected pets, and so on.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

try:
    import lupa.lua54 as lupa
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "mod" / "ui"

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    'package.path = "%s/mod/lua/?.lua;%s/tools/?.lua;" .. package.path'
    % (ROOT.as_posix(), ROOT.as_posix())
)
glue = lua.eval('(require("preview_glue"))')
glue.reset("en", 2026)


def to_py(value):
    """Lua table -> dict/list/scalars."""
    if lupa.lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, (int, float)) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(value[k]) for k in sorted(keys)]
    if not keys:
        return []
    return {str(k): to_py(value[k]) for k in keys}


def to_lua(args):
    return lua.table_from({k: v for k, v in args.items()})


TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
         ".css": "text/css; charset=utf-8", ".json": "application/json"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path.startswith("/api/"):
            return self._api(path[5:], {})
        rel = "index.html" if path == "/" else path.lstrip("/")
        file = (UI_DIR / rel).resolve()
        if UI_DIR not in file.parents and file != UI_DIR / "index.html" or not file.is_file():
            return self._send(404, "not found", "text/plain")
        self._send(200, file.read_bytes(), TYPES.get(file.suffix, "application/octet-stream"))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            args = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return self._send(400, '{"error":"bad json"}', "application/json")
        self._api(urlparse(self.path).path[5:], args)

    def _api(self, method, args):
        try:
            result = to_py(glue.handle(method, to_lua(args)))
            self._send(200, json.dumps(result, ensure_ascii=False), "application/json")
        except Exception as exc:  # preview tool: show the problem in the page
            self._send(500, json.dumps({"error": str(exc)}), "application/json")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print("Paw Home preview: http://127.0.0.1:%d/?preview=1" % port)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
