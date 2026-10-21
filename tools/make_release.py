"""Build the installable Paw Home folder (and a zip of it) from the repo.

  py -I tools/make_release.py [--name PawHome_XXXXXXXX] [--version 1.0.0] [--author NAME] [--out dist]

Writes dist/<name>/ (lua/, ui/, l10n/, <name>.uplugin, mod_manifest.json) with tools/build_modkit.py,
then dist/<name>-<version>.zip. The folder name is the mod's id: B1/B2 use it as MOD_ID, so build with
the id the game will know the mod by (ModKit adds an 8-character code to the project name when you
create the project; use that exact folder name for the final package).

This is the hand-made layout the game also reads from Documents\\inZOI\\Mods\\InGame\\<name>. The
official package for CurseForge is made by ModKit (modkit_package), which also writes
mod_assethash.json; see docs/packaging.md. Nothing here publishes anything.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
DESCRIPTION = ("Paw Home adds cat adoption and care to inZOI: adopt a cat, feed and play with it, "
               "watch it grow, keep it healthy. Includes an online pet shop on the phone and computer. "
               "毛孩之家：領養、照顧、陪玩、養大貓咪，手機與電腦都有線上寵物店。")


def arg(argv, flag, default):
    return argv[argv.index(flag) + 1] if flag in argv else default


def main(argv):
    name = arg(argv, "--name", "PawHome")
    version = arg(argv, "--version", "1.0.0")
    author = arg(argv, "--author", "")
    out = REPO / arg(argv, "--out", "dist")
    root = out / name
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)

    uplugin = {
        "FileVersion": 3, "Version": 1, "VersionName": version, "FriendlyName": "PawHome",
        "Description": DESCRIPTION, "Category": "UGC", "CreatedBy": author, "CreatedByURL": "",
        "DocsURL": "", "MarketplaceURL": "", "SupportURL": "", "CanContainContent": False,
        "IsBetaVersion": False, "IsExperimentalVersion": False, "Installed": False,
    }
    (root / f"{name}.uplugin").write_text(json.dumps(uplugin, indent="\t", ensure_ascii=False), encoding="utf-8")
    manifest = {
        "ProjectName": name, "FriendlyName": "PawHome", "Description": DESCRIPTION, "Author": author,
        "Version": version, "Url": "", "Dependencies": [], "Assets": [], "Maps": [], "NonAssets": [],
    }
    (root / "mod_manifest.json").write_text(json.dumps(manifest, indent="\t", ensure_ascii=False), encoding="utf-8")

    done = subprocess.run([sys.executable, "-I", str(REPO / "tools" / "build_modkit.py"), str(root)],
                          capture_output=True, text=True, encoding="utf-8")
    print(done.stdout.strip())
    if done.returncode != 0:
        print(done.stderr.strip())
        return 1

    files = sorted(p for p in root.rglob("*") if p.is_file())
    zip_path = out / f"{name}-{version}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, name + "/" + p.relative_to(root).as_posix())
    mb = sum(p.stat().st_size for p in files) / 1e6
    print(f"{len(files)} files, {mb:.2f} MB -> {zip_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
