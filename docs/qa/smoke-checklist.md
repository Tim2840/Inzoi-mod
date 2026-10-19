# Smoke checklist (UE4SS route)

Consent levels are in `docs/engineering-workflow.md` §9. Results go to
`docs/qa/results/<date>-<build>.md`. Paths below use the Steam install:
`<Win64>` = `C:\Program Files (x86)\Steam\steamapps\common\inZOI\BlueClient\Binaries\Win64`,
`<Mod>` = `<Win64>\ue4ss\Mods\PawHome`.

## T1 – main menu (automated)

Run `scripts\smoke-t1.ps1` (PO consent once per game build). It installs the mod,
starts the game, stays on the main menu, checks V1/V6 from the log and writes the
result file. Nothing below is needed for T1.

**Nobody touches the game while T1 runs** (about 5 minutes): no clicks, no keys, do
not press Continue. At the end the script sends a normal close request (the same as
clicking X); if someone had loaded a save the game would handle that close itself,
and the run would no longer be a main-menu-only T1.

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

### M1-3a – in-world discovery (ran once on 2026-10-20: `docs/qa/results/2026-10-20-t2-m1-3a-20261013.16166.W-334313.md`)

Agent prepares (T0): create `<Mod>\pawhome_debug.txt` and `<Mod>\pawhome_autoexplore.txt`.
With auto-explore armed, the mod runs the discovery scan and the animal dumps by itself
60 s after a map load (one scan at a time, at most 3 scans per session), so the PO does not
need keys. Since the first run it also does the **b0 observation** right after each scan:
the existing city cat `Void_Cat1_C` is found with `FindFirstOf`, its controller and
`BrainComponent` are logged, the controller is dumped, and its position is sampled every 5 s
for 60 s. This spawns and removes nothing and cannot touch the save. Evidence b0 (in
`UE4SS.log` and `pawhome_dump.txt`): `observe Void_Cat1_C: <full name> (existing game actor, will not be
removed)`, `controller: ...`, `BrainComponent: <name or nil>`, `controller dump written`, 13 lines
`pos t=...`, and `movement: ... -> MOVED|STATIONARY`. For a meaningful answer the PO should
stay in the city for at least 3 minutes after it appears and **keep that cat near the camera
and not interact with it** during the 60 s (if the cat is not in the loaded area the log says
`no instance loaded`). Shift+F5 repeats the observation on demand.

PO steps (about 5 minutes):
1. Start the game, load any save (City Decoration → Animals: cats **on**).
2. Walk the Zoi near stray cats; wait at least 2 minutes after the city appears.
3. Optional: press **Shift+F8** once while a stray cat is on screen (same scan + dumps,
   right now; the game hitches for a few seconds).
4. Quit to the main menu normally, then close the game.

Evidence the agent collects afterwards (no game needed):

| # | Evidence | Where | What it should look like |
|---|---|---|---|
| a1 | Stray-cat class name(s) | `<Mod>\pawhome_discovery.txt`, `## animal - level instances` | lines like `<ClassName> /Game/Map/<City>.<City>:PersistentLevel.<Actor>`; record every class seen |
| a2 | Time manager instance | same file, `## time - level instances` | a `B1TimeManager` (or similar) instance inside the city level |
| a3 | Save / household objects | same file, `## save` | candidates for the slot id and household id |
| a4 | Dump of a cat | `<Mod>\pawhome_dump.txt` | `object: ...`, `## class ...`, `prop <name> : <Type> = <value>` lines; note Controller / AIControllerClass if present |
| a5 | Log | `<Win64>\ue4ss\UE4SS.log` | `[PawHome] auto-explore armed`, `auto-explore auto #1 scheduled in 60 s`, `discovery (auto #1): <n> objects -> ...`, `dump animal <Class>: <n> lines`; **no** `[PawHome][error]` or `debug key error` |

Write the classes found into `docs/ue4ss-adapter.md` ("What is known about in-game
cats") with the build number, and the result into `docs/qa/results/`.

### M1-3b – spawn experiment (tool exists; written, not run in-game)

Tool: **Shift+F6** (debug mode only). First press spawns the class 150 units in front of
the player, logs b1/b2 and samples the position every 5 s for 60 s (b3); second press
removes it (b4). Default class: the city cat Character `/Game/Characters/Void/Void_Cat/Void_Cat1.Void_Cat1_C`
(found by M1-3a). To try another class, the agent writes its full object path as the first
line of `<Mod>\pawhome_spawn_class.txt`. A placed `Void_Cat1_C` has an `AIController`, but by
Unreal convention a runtime spawn may get none (`AutoPossessAI = 1`); `controller: nil`
after the spawn is then **not** evidence that the game has no AI for it. Create
`<Mod>\pawhome_possess.txt` to make the tool call `SpawnDefaultController()` when the pawn
has no controller (b2 is then logged before and after). Do M1-3b only after the b0
observation has answered whether the existing cat moves by itself.

**Risk the PO must be told before agreeing (put it in the T2 consent):** the spawned cat
is *not* removed automatically (the PO removes it with a second Shift+F6; the 5-minute
stability check of b4 then runs after the removal). If the game
is saved, or the world is left, while it is still alive, the actor might be written into the
game's own save. That is why the experiment runs only on a **throwaway copy** of a save and
only after the backup in step 0.

PO steps:
1. Backup saves (step 0). Load a **throwaway** save (a copy, not the main one).
2. Press **Shift+F6** once; do not interact with the cat.
3. Wait 60 seconds without moving the camera far away. When sampling ends the UE4SS
   console prints `WARNING: actor still alive - press Shift+F6 to remove it BEFORE saving
   or leaving the world`.
4. Press **Shift+F6** again (remove). **Do not save or leave the world before this.**
   Wait 5 minutes in game (normal speed).
5. Only now save the game, quit to the main menu, load the same save again, then quit.

The five pieces of evidence (workflow §14, M1-3b):

| # | Evidence | Expected log shape |
|---|---|---|
| b1 | Spawn result | `[PawHome] spawn <class path>: <actor full name>` or `[PawHome] spawn <class path>: failed (<reason>)` |
| b2 | Controller | `[PawHome] controller: <full name or nil>`, `[PawHome] AIControllerClass: <class or nil>` |
| b3 | Movement | 13 lines `[PawHome] pos t=<s> x=<x> y=<y> z=<z>` (t = 0 … 60), then `[PawHome] movement: <n> samples, total distance <d> units -> MOVED|STATIONARY` (MOVED = more than 100 units) |
| b4 | Stability | `[PawHome] removed <actor>`; game still running 5 minutes later; no `[PawHome][error]` |
| b5 | Not in the native save | after reload, a Shift+F8 scan shows **no** instance of the spawned actor name; compare save-folder sizes before/after |

Conclusion (plan A / B / C) goes into an ADR; only then may a cap be set true and the
build be added to `<Mod>\pawhome_verified_builds.txt`.

### Rollback if anything goes wrong

1. Close the game. 2. Restore the save folders from `backups\<date>-pre-T2\`.
3. `scripts\install-ue4ss.ps1 -Uninstall` (keeps PawHome saves) or create
   `<Mod>\pawhome_disabled.txt` (kill switch). 4. Note what happened in the result file.
