"""Assemble the Paw Home ModKit Lua folder from the repo.

Usage: py -I tools/build_modkit.py <mod_root>
Writes <mod_root>/lua/ :
  lua_manifest.json, B2/Main.lua, B2/PawHomeBind/*, B1/Main.lua, B1/PawHomeBind/*  (mod/modkit/lua)
  B2/pawhome/**            the whole engine (mod/lua/pawhome), without the UE4SS adapter
  B1/pawhome/adapters/*    only what the B1 relay needs
  {B2,B1}/pawhome/modkit_config.lua   MOD_ID = <mod_root folder name>
Existing files under <mod_root>/lua are replaced; nothing outside it is touched.
"""
import json
import pathlib
import re
import shutil
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ENGINE = REPO / "mod" / "lua" / "pawhome"
BINDINGS = REPO / "mod" / "modkit" / "lua"
B2_SKIP = {"ue4ss.lua", "ue4ss_probe.lua", "mock.lua"}
B1_FILES = ["inzoi_wire.lua", "inzoi_relay.lua", "inzoi_platform.lua", "inzoi_b1.lua", "inzoi_cat_b1.lua"]


def resolve_vars(text, css):
    """Replace var(--name[, fallback]) with the value from the first :root block of css."""
    block = re.search(r":root\s*\{(.*?)\}", css, re.S)
    values = dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", block.group(1))) if block else {}

    def sub(m):
        name, fallback = m.group(1), (m.group(2) or "").strip()
        return values.get(name, fallback or m.group(0)).strip()

    return re.sub(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^)]*))?\)", sub, text)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    lua = root / "lua"
    if lua.exists():
        shutil.rmtree(lua)
    shutil.copytree(BINDINGS, lua)
    for src in ENGINE.rglob("*.lua"):
        if src.name in B2_SKIP:
            continue
        dst = lua / "B2" / "pawhome" / src.relative_to(ENGINE)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    for name in B1_FILES:
        dst = lua / "B1" / "pawhome" / "adapters" / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ENGINE / "adapters" / name, dst)
    # the mod id (folder name) is the key of the uimod.cfg_* mailboxes on both threads
    config = 'return { MOD_ID = "%s" }\n' % root.name
    for env in ("B2", "B1"):
        (lua / env / "pawhome" / "modkit_config.lua").write_text(config, encoding="utf-8")
    count = sum(1 for _ in lua.rglob("*.lua"))
    print(f"wrote {count} Lua files to {lua}")
    # UI: the app folder must already exist (created by the game's uimod_scaffold, which
    # provides window.js and uimod_manifest.json); our page files are copied over it.
    app = root / "ui" / "pawhome"
    if app.is_dir():
        for name in ("app.js", "bridge.js"):
            shutil.copyfile(REPO / "mod" / "ui" / name, app / name)
        # The game's browser ignores CSS custom properties (seen in 20261019.16318.W): the
        # in-game copies get the dark theme's values written in place of var(--name).
        css = (REPO / "mod" / "ui" / "style.css").read_text(encoding="utf-8")
        page = (REPO / "mod" / "modkit" / "ui" / "index.html").read_text(encoding="utf-8")
        (app / "style.css").write_text(resolve_vars(css, css), encoding="utf-8")
        (app / "index.html").write_text(resolve_vars(page, css), encoding="utf-8")
        print(f"wrote UI to {app}")
    # mod_manifest.json lists the mod's loose files ("NonAssets"); keep it in step with what we wrote
    manifest_path = root / "mod_manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        files = sorted("/" + p.relative_to(root).as_posix()
                       for sub in ("lua", "ui") if (root / sub).is_dir()
                       for p in (root / sub).rglob("*") if p.is_file())
        manifest["NonAssets"] = files
        manifest_path.write_text(json.dumps(manifest, indent="\t", ensure_ascii=False), encoding="utf-8")
        print(f"listed {len(files)} files in {manifest_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
