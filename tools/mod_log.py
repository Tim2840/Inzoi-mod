"""Print the dev mod's in-game logs (written with uimod.cfg_save, section "log").

  py -I tools/mod_log.py [b1|b2|ui ...] [--tail N] [--mod MOD_ID]

b1 = B1 relay (also carries the B2 lines sent as pawhome:diag), b2 = B2 log flushed at
session end, ui = page errors. Needs the game running (tools/game_mcp.py).
"""
import json
import pathlib
import subprocess
import sys
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_MOD = "PawHomeDev_A5BI7C"


def load(mod, key):
    args = json.dumps({"mod_id": mod, "section": "log", "key": key})
    out = subprocess.run([sys.executable, "-I", str(HERE / "game_mcp.py"), "uimod_cfg_load", args],
                         capture_output=True, text=True, encoding="utf-8").stdout
    start = out.find("{")
    if start < 0:
        return out.strip()
    try:
        data = json.loads(out[start:])
    except ValueError:
        return out.strip()
    value = data.get("value", data.get("data", {}).get("value", "")) if isinstance(data, dict) else ""
    return urllib.parse.unquote(value)


def main(argv):
    keys, tail, mod = [], 40, DEFAULT_MOD
    i = 0
    while i < len(argv):
        if argv[i] == "--tail":
            tail = int(argv[i + 1]); i += 2
        elif argv[i] == "--mod":
            mod = argv[i + 1]; i += 2
        else:
            keys.append(argv[i]); i += 1
    for key in keys or ["b1"]:
        lines = load(mod, key).splitlines()
        print(f"--- {key} ({len(lines)} lines)")
        print("\n".join(lines[-tail:]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
