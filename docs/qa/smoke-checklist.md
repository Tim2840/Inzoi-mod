# Smoke checklist (UE4SS route)

Consent levels are in `docs/engineering-workflow.md` §9. Results go to
`docs/qa/results/<date>-<build>.md`. Paths below use the Steam install:
`<Win64>` = `C:\Program Files (x86)\Steam\steamapps\common\inZOI\BlueClient\Binaries\Win64`,
`<Mod>` = `<Win64>\ue4ss\Mods\PawHome`.

## T1 – main menu (automated)

Run `scripts\smoke-t1.ps1` (PO consent once per game build). It installs the mod,
starts the game, stays on the main menu, checks V1/V6 from the log and writes the
result file. Nothing below is needed for T1.

## T2 – inside a save (M1-3a / M1-3b)

T2 needs the PO at the computer or explicit consent, a save backup first, and the
game **not** in any online session. The desktop-control permission must be granted
by the PO in person, so in practice the PO drives the game and the agent reads files.

### 0. Before starting (agent, T0)

1. Backup both save folders (copy, never move):
   - `%USERPROFILE%\Documents\inZOI\SaveGames`
   - `%LOCALAPPDATA%\BlueClient\Saved\SaveGames`
   to `backups\<date>-pre-T2\` outside the game folders. Record the copy size.
2. T1 for this build must be PASS (`docs/compatibility.md`).
3. Note the build fingerprint from the T1 result (`size:<n>`).

### M1-3a – in-world discovery (tools exist today)

PO steps (about 5 minutes):
1. Start the game, load any save (City Decoration → Animals: cats **on**).
2. Walk the Zoi near stray cats; wait until at least one is visible.
3. Press **Shift+F8** (discovery scan; the game hitches for a few seconds).
4. Press **Shift+F7** (dump the first `BP_Pet_Customize_01_C`; it may say "no
   instance loaded" in a city – that is a result too).
5. Quit to the main menu normally, then close the game.

Evidence the agent collects afterwards (no game needed):

| # | Evidence | Where | What it should look like |
|---|---|---|---|
| a1 | Stray-cat class name(s) | `<Mod>\pawhome_discovery.txt`, `## animal - level instances` | lines like `<ClassName> /Game/Map/<City>.<City>:PersistentLevel.<Actor>`; record every class seen |
| a2 | Time manager instance | same file, `## time - level instances` | a `B1TimeManager` (or similar) instance inside the city level |
| a3 | Save / household objects | same file, `## save` | candidates for the slot id and household id |
| a4 | Dump of a cat | `<Mod>\pawhome_dump.txt` | `object: ...`, `## class ...`, `prop <name> : <Type> = <value>` lines; note Controller / AIControllerClass if present |
| a5 | Log | `<Win64>\ue4ss\UE4SS.log` | `[PawHome] discovery: <n> objects -> ...`, `[PawHome] dump ...`; **no** `[PawHome][error]` or `debug key error` |

Write the classes found into `docs/ue4ss-adapter.md` ("What is known about in-game
cats") with the build number, and the result into `docs/qa/results/`.

### M1-3b – spawn experiment (needs a spawn tool that is NOT built yet)

Prerequisite (T0, agent): a debug key that spawns the class found in a1 next to the
active Zoi, logs its full name, samples its position, and removes it again. Until that
exists this section cannot run.

PO steps once the tool exists:
1. Backup saves (step 0). Load a **throwaway** save (a copy, not the main one).
2. Press the spawn key once; do not interact with the cat.
3. Wait 60 seconds without moving the camera far away.
4. Press the remove key. Wait 5 minutes in game (normal speed).
5. Save the game, quit to the main menu, load the same save again, then quit.

The five pieces of evidence (workflow §14, M1-3b):

| # | Evidence | Expected log shape |
|---|---|---|
| b1 | Spawn result | `[PawHome] spawn <Class>: <actor full name>` or `[PawHome] spawn <Class>: failed (<reason>)` |
| b2 | Controller | `[PawHome] controller: <full name or nil>`, `AIControllerClass: <class or nil>` |
| b3 | Movement | 12 lines `[PawHome] pos t=<s> x=<x> y=<y> z=<z>` at 5 s intervals; moving = total distance > 100 units |
| b4 | Stability | `[PawHome] removed <actor>`; game still running 5 minutes later; no `[PawHome][error]` |
| b5 | Not in the native save | after reload, a Shift+F8 scan shows **no** instance of the spawned actor name; compare save-folder sizes before/after |

Conclusion (plan A / B / C) goes into an ADR; only then may a cap be set true and the
build be added to `<Mod>\pawhome_verified_builds.txt`.

### Rollback if anything goes wrong

1. Close the game. 2. Restore the save folders from `backups\<date>-pre-T2\`.
3. `scripts\install-ue4ss.ps1 -Uninstall` (keeps PawHome saves) or create
   `<Mod>\pawhome_disabled.txt` (kill switch). 4. Note what happened in the result file.
