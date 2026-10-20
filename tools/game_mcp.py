"""Call one tool of the running game's MCP server (inzoi-game, http://localhost:11212/mcp).

Usage (from the repo root):
    py -I tools/game_mcp.py <tool_name> ['{"json": "args"}'] [max_chars]

Prints the tool's text result (truncated to max_chars, default 6000). Exit code 1 on a JSON-RPC
error. Used for phase 0 probing when the inzoi-game MCP server is not connected in the session.
"""
import json
import sys
import urllib.request

URL = "http://localhost:11212/mcp"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    name = sys.argv[1]
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else {}
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 6000
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                       "params": {"name": name, "arguments": args}}).encode("utf-8")
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.loads(r.read().decode("utf-8"))
    sys.stdout.reconfigure(encoding="utf-8")
    if "error" in resp:
        print("RPC ERROR", json.dumps(resp["error"], ensure_ascii=False))
        return 1
    res = resp["result"]
    text = "\n".join(c.get("text", json.dumps(c, ensure_ascii=False)) for c in res.get("content", []))
    if res.get("isError"):
        text = "TOOL ERROR " + text
    if len(text) > limit:
        text = text[:limit] + "\n...[truncated %d chars]" % (len(text) - limit)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
