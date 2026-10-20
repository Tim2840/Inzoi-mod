"""One game, several sessions: who may change the running game right now.

The lock lives outside the repo so every worktree sees the same file:
  %LOCALAPPDATA%\\PawHome\\game.lock

  py -I tools/game_lock.py status
  py -I tools/game_lock.py acquire <owner> [minutes] [note...]   exit 1 when someone else holds it
  py -I tools/game_lock.py renew <owner> [minutes]
  py -I tools/game_lock.py release <owner>

Hold the lock for anything that changes the game: loading or leaving a save, mounting mods,
writing the dev mod folder, data patches, cheats, spawning. Read-only queries (data.table_get,
cli_help, get_state, scans) need no lock. An expired lock may be taken over.
"""
import datetime as dt
import json
import os
import pathlib
import sys

LOCK = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "PawHome" / "game.lock"
DEFAULT_MINUTES = 45


def now():
    return dt.datetime.now().replace(microsecond=0)


def read():
    try:
        data = json.loads(LOCK.read_text(encoding="utf-8"))
        data["until_dt"] = dt.datetime.fromisoformat(data["until"])
        return data
    except (OSError, ValueError, KeyError):
        return None


def write(owner, minutes, note):
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    data = {"owner": owner, "since": now().isoformat(), "until": (now() + dt.timedelta(minutes=minutes)).isoformat(),
            "note": note}
    LOCK.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def describe(data):
    left = int((data["until_dt"] - now()).total_seconds() // 60)
    state = f"{left} min left" if left >= 0 else "expired"
    return f"held by {data['owner']} since {data['since']} ({state}) {data.get('note', '')}".rstrip()


def main(argv):
    if not argv or argv[0] not in ("status", "acquire", "renew", "release"):
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    cur = read()
    if cmd == "status":
        print(describe(cur) if cur else "free")
        return 0
    if not rest:
        print("owner required")
        return 2
    owner = rest[0]
    minutes = int(rest[1]) if len(rest) > 1 and rest[1].isdigit() else DEFAULT_MINUTES
    note = " ".join(rest[2:] if len(rest) > 1 and rest[1].isdigit() else rest[1:])
    mine = cur is not None and cur["owner"] == owner
    expired = cur is not None and cur["until_dt"] < now()
    if cmd == "release":
        if mine:
            LOCK.unlink()
            print("released")
            return 0
        print("not yours: " + (describe(cur) if cur else "free"))
        return 1
    if cmd == "renew" and not mine:
        print("not yours: " + (describe(cur) if cur else "free"))
        return 1
    if cur is None or mine or expired:
        write(owner, minutes, note if cmd == "acquire" else cur.get("note", "") if cur else "")
        print(f"{owner} holds the game for {minutes} min")
        return 0
    print(describe(cur))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
