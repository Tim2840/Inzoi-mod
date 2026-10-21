"""In-game smoke test of the dev mod, without saving anything.

  py -I tools/ingame_smoke.py <owner> [--folder F --file F] [--expect TEXT ...] [--keep]

Steps: take the game lock -> build the dev mod from this checkout -> (lobby) remount Lua and
enable the UI -> load the save -> resume time -> wait for the B2 handshake in the relay log ->
check every --expect text appears -> back to the lobby WITHOUT saving -> unmount -> release.
--keep stays in the game afterwards (the lock stays yours; release it yourself).
Exit code 0 = every check passed. The game must already be running and in the lobby.
"""
import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
MOD_ID = "PawHomeDev_A5BI7C"
MOD_ROOT = pathlib.Path.home() / "Documents" / "inZOI" / "Mods" / "InGame" / MOD_ID
DEFAULT_SAVE = ("20260609-050535", "20260609-050535")    # the Gangnam test household


def run(script, *args):
    out = subprocess.run([sys.executable, "-I", str(HERE / script), *args],
                         capture_output=True, text=True, encoding="utf-8")
    return out.returncode, (out.stdout or "") + (out.stderr or "")


def game(tool, args=None, limit="200000"):
    code, text = run("game_mcp.py", tool, json.dumps(args or {}), limit)
    return code, text


def state():
    code, text = game("game_get_state")
    try:
        return json.loads(text[text.index("{"):])
    except ValueError:
        return {}


def wait(cond, seconds, every=5):
    end = time.time() + seconds
    while time.time() < end:
        s = state()
        if cond(s):
            return s
        time.sleep(every)
    return None


def relay_log():
    code, text = run("mod_log.py", "b1", "--tail", "200")
    return text


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    owner, folder, file, expects, keep = argv[0], *DEFAULT_SAVE, [], False
    i = 1
    while i < len(argv):
        if argv[i] == "--folder": folder = argv[i + 1]; i += 2
        elif argv[i] == "--file": file = argv[i + 1]; i += 2
        elif argv[i] == "--expect": expects.append(argv[i + 1]); i += 2
        elif argv[i] == "--keep": keep = True; i += 1
        else: print("unknown argument " + argv[i]); return 2
    expects = expects or ["state received", "status:"]

    code, text = run("game_lock.py", "acquire", owner, "30", "ingame_smoke")
    print(text.strip())
    if code != 0:
        return 1
    ok = False
    try:
        s = state()
        if not s.get("is_lobby") or s.get("loading"):
            print("game is not idle in the lobby (phase %s); stopping" % s.get("phase"))
            return 1
        code, text = run("build_modkit.py", str(MOD_ROOT))
        print(text.strip().splitlines()[-1] if text.strip() else "build: no output")
        if code != 0:
            return 1
        print(game("luamod_remount", {"mod_id": MOD_ID})[1].strip()[:120])
        print(game("uimod_enable", {"Keyword": "PawHomeDev"})[1].strip()[:120])
        print(game("game_load", {"folder": folder, "file": file})[1].strip()[:120])
        if not wait(lambda s: s.get("phase") == "in_game", 600, 10):
            print("save did not finish loading")
            return 1
        time.sleep(5)
        game("ui_dismiss")                       # a loaded save can sit behind the ESC menu, paused
        game("environment_time_speed", {"speed": 1})
        end = time.time() + 120
        log = ""
        while time.time() < end:
            log = relay_log()
            if all(e in log for e in expects):
                break
            time.sleep(5)
        missing = [e for e in expects if e not in log]
        print("\n".join(log.strip().splitlines()[-15:]))
        print("MISSING: " + ", ".join(missing) if missing else "all checks passed")
        ok = not missing
        return 0 if ok else 1
    finally:
        if not keep:
            s = state()
            if not s.get("is_lobby"):
                game("game_goto_lobby", {"save": False})
                wait(lambda s: s.get("is_lobby") and not s.get("loading"), 300, 5)
            game("luamod_unmount", {"mod_id": MOD_ID})
            game("uimod_disable", {"Keyword": "PawHomeDev"})
            print(run("game_lock.py", "release", owner)[1].strip())
        else:
            print("kept in game; the lock is still held by " + owner)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
