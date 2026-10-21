"""Assemble the Paw Home ModKit Lua folder from the repo.

Usage: py -I tools/build_modkit.py <mod_root>
Writes <mod_root>/lua/ :
  lua_manifest.json, B2/Main.lua, B2/PawHomeBind/*, B1/Main.lua, B1/PawHomeBind/*  (mod/modkit/lua)
  B2/pawhome/**            the whole engine (mod/lua/pawhome), without the UE4SS adapter
  B1/pawhome/adapters/*    only what the B1 relay needs
  {B2,B1}/pawhome/modkit_config.lua   MOD_ID = <mod_root folder name>
and <mod_root>/ui/pawhome/ (page files, icons, uimod_manifest.json over the game's scaffold),
<mod_root>/l10n/<culture>_mod/PawHome.po (labels for the game's menus) and the NonAssets list.
Existing files under <mod_root>/lua are replaced; nothing else outside these paths is touched.
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
B1_FILES = ["inzoi_wire.lua", "inzoi_relay.lua", "inzoi_coats.lua", "inzoi_platform.lua", "inzoi_b1.lua", "inzoi_cat_b1.lua"]


def resolve_vars(text, css):
    """Replace var(--name[, fallback]) with the value from the first :root block of css."""
    block = re.search(r":root\s*\{(.*?)\}", css, re.S)
    values = dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", block.group(1))) if block else {}

    def sub(m):
        name, fallback = m.group(1), (m.group(2) or "").strip()
        return values.get(name, fallback or m.group(0)).strip()

    return re.sub(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^)]*))?\)", sub, text)


# our localization file -> the game's culture folder name (l10n/<culture>_mod/)
CULTURES = {"en": "en", "zh_TW": "zh-TW"}
GAME_PREFIX = "mod_PawHome_"


def game_strings():
    """{culture: [(text id, text)]} from the `game = { key = "text", ... }` block of each localization file."""
    out = {}
    for name, culture in CULTURES.items():
        src = (ENGINE / "localization" / (name + ".lua")).read_text(encoding="utf-8")
        block = re.search(r"\n    game = \{(.*?)\n    \},", src, re.S)
        if not block:
            continue
        pairs = re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block.group(1))
        out[culture] = [(GAME_PREFIX + k, v.replace('\\"', '"').replace("\\\\", "\\")) for k, v in pairs]
    return out


def to_po(entries):
    esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    return "".join('msgctxt "%s"\nmsgid "%s"\nmsgstr "%s"\n\n' % (k, esc(v), esc(v)) for k, v in entries)


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
        for name in ("app.js", "bridge.js", "icons.js"):
            shutil.copyfile(REPO / "mod" / "ui" / name, app / name)
        # The game's browser ignores CSS custom properties (seen in 20261019.16318.W): the
        # in-game copies get the dark theme's values written in place of var(--name).
        css = (REPO / "mod" / "ui" / "style.css").read_text(encoding="utf-8")
        page = (REPO / "mod" / "modkit" / "ui" / "index.html").read_text(encoding="utf-8")
        (app / "style.css").write_text(resolve_vars(css, css), encoding="utf-8")
        (app / "index.html").write_text(resolve_vars(page, css), encoding="utf-8")
        # triggers (launcher view during play + entries in the game's interaction menus)
        shutil.copyfile(REPO / "mod" / "modkit" / "ui" / "uimod_manifest.json", app / "uimod_manifest.json")
        print(f"wrote UI to {app}")
    # labels for the game's own menus: localization `game` block -> l10n/<culture>_mod/PawHome.po
    for culture, entries in game_strings().items():
        po = root / "l10n" / (culture + "_mod") / "PawHome.po"
        po.parent.mkdir(parents=True, exist_ok=True)
        po.write_text(to_po(entries), encoding="utf-8")
        print(f"wrote {len(entries)} labels to {po.relative_to(root)}")
    # mod_manifest.json lists the mod's loose files ("NonAssets"); keep it in step with what we wrote
    manifest_path = root / "mod_manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        files = sorted("/" + p.relative_to(root).as_posix()
                       for sub in ("lua", "ui", "l10n") if (root / sub).is_dir()
                       for p in (root / sub).rglob("*") if p.is_file())
        manifest["NonAssets"] = files
        manifest_path.write_text(json.dumps(manifest, indent="\t", ensure_ascii=False), encoding="utf-8")
        print(f"listed {len(files)} files in {manifest_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
