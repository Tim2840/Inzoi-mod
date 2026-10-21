"""Call the mod's RPC from outside, as if the panel had pressed a button (for in-game tests).

  py -I tools/ui_rpc.py <method> ['<json args>'] [--timeout S]

Adds one pawhome:rpc entry to the page's mailbox (bridge/to_sim) and waits for the
pawhome:rpc_result in bridge/to_ui. Needs a loaded save with the dev mod running and the
handshake done. The page rewrites its mailbox when it sends something itself; if that
happens before the relay polls (every 2 s) the call is lost and this times out: run it again.
Prints the result JSON. Exit code 1 on timeout.
"""
import json
import pathlib
import random
import subprocess
import sys
import time
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent
MOD_ID = "PawHomeDev_A5BI7C"


def cfg(tool, key, value=None):
    args = {"mod_id": MOD_ID, "section": "bridge", "key": key}
    if value is not None:
        args["value"] = value
    out = subprocess.run([sys.executable, "-I", str(HERE / "game_mcp.py"), tool, json.dumps(args), "500000"],
                         capture_output=True, text=True, encoding="utf-8").stdout
    if value is not None:
        return out
    start = out.find("{")
    try:
        data = json.loads(out[start:]) if start >= 0 else {}
    except ValueError:
        return ""
    return data.get("value", data.get("data", {}).get("value", "")) if isinstance(data, dict) else ""


def esc(s):
    return urllib.parse.quote(str(s), safe="-._~")


def decode(text):
    out = []
    for item in (text or "").split(";"):
        parts = item.split(",", 2)
        if len(parts) == 3 and parts[0].isdigit():
            out.append((int(parts[0]), urllib.parse.unquote(parts[1]), urllib.parse.unquote(parts[2])))
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    method = argv[0]
    args = json.loads(argv[1]) if len(argv) > 1 and not argv[1].startswith("--") else {}
    timeout = float(argv[argv.index("--timeout") + 1]) if "--timeout" in argv else 30

    hellos = [p for _, ch, p in decode(cfg("uimod_cfg_load", "to_ui")) if ch == "pawhome:hello"]
    if not hellos:
        print("no hello from B2 in the mailbox yet")
        return 1
    session = hellos[-1].split("|", 1)[0]
    rid = random.randint(900000, 999999)
    entries = decode(cfg("uimod_cfg_load", "to_sim"))
    if not entries or entries[0][1] != "epoch":
        entries = [(0, "epoch", "tool%d" % rid)]
    seq = max(e[0] for e in entries) + 1
    entries.append((seq, "pawhome:rpc", session + "|" + json.dumps({"id": rid, "method": method, "args": args})))
    cfg("uimod_cfg_save", "to_sim", ";".join("%d,%s,%s" % (s, esc(c), esc(p)) for s, c, p in entries))

    end = time.time() + timeout
    while time.time() < end:
        for _, ch, p in decode(cfg("uimod_cfg_load", "to_ui")):
            if ch == "pawhome:rpc_result" and p.startswith(session + "|"):
                try:
                    t = json.loads(p.split("|", 1)[1])
                except ValueError:
                    continue
                if t.get("id") == rid:
                    print(json.dumps(t.get("result"), ensure_ascii=False))
                    return 0
        time.sleep(1)
    print("timeout: no result for %s (id %d)" % (method, rid))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
