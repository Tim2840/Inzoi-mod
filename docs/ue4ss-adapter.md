# UE4SS adapter (`adapters/ue4ss.lua`)

Runs the Paw Home engine inside inZOI through UE4SS (the route the ZoiPets project
verified), instead of the official ModKit Lua runtime. Branch: `feat/ue4ss-adapter`.

## Operating the mod

| Feature | How |
|---|---|
| Startup banner | First `[PawHome]` line in `UE4SS.log`: mod version, Lua version, build fingerprint, `verified` / `SAFE MODE`, caps, debug flag |
| Debug mode | **Off by default.** Create `pawhome_debug.txt` in `ue4ss\Mods\PawHome\` to turn it on: debug clock, 1000 debug wallet, Shift+F6–F10 keys. Off = no clock, so the engine idles and saves nothing |
| Auto-explore (M1-3a) | Debug mode **and** `pawhome_autoexplore.txt`: 60 s after a map load run the discovery scan and dump every distinct animal actor class found in the level plus `DUMP_CLASSES`. `ClientRestart` can fire several times per load, so only one scan is scheduled at a time (extra triggers are logged and ignored) and the budget of 3 scans counts scans that actually ran. The log gives each scan's duration (`explore (...) took N s`), the first real measurement of the full object scan |
| Spawn class (M1-3b) | First line of `pawhome_spawn_class.txt` = full object path Shift+F6 spawns; default the lobby cat `BP_Pet_Customize_01_C` |
| Kill switch | Create `pawhome_disabled.txt` in `ue4ss\Mods\PawHome\` → nothing starts (no loop, no keys, saves untouched). Delete it to re-enable |
| Safe mode | Build fingerprint = size of `inZOI-Win64-Shipping.exe`. Unless that fingerprint is listed in `pawhome_verified_builds.txt` (one `size:<n> <note>` per line), every cap is forced off. Add a line **only after** M1-3b evidence for that build |
| Save backups | Each save keeps `.bak1` (newest) … `.bak3`. Recovery: close the game, rename the wanted `.bakN` to the `.sav` name |
| Rollback | `scripts\install-ue4ss.ps1 -Uninstall` removes the scripts and keeps saves; restore a `.bakN` if a save is bad |

Debug keys (only with `pawhome_debug.txt`): Shift+F6 spawn experiment (first press:
spawn + 60 s of position samples; second press: remove); Shift+F7 dump the first
instance of `DUMP_CLASSES` (`BP_Pet_Customize_01_C`, `B1TimeManager`) →
`pawhome_dump.txt`; Shift+F8 discovery scan + animal dumps → `pawhome_discovery.txt` /
`pawhome_dump.txt`; Shift+F9 adopt the first shelter offer; Shift+F10 print pets.

## Files

| File | Role |
|---|---|
| `mod/lua/pawhome/adapters/ue4ss.lua` | Adapter (contract in `core/api.lua`) + read-only discovery scan |
| `mod/lua/pawhome/adapters/ue4ss_probe.lua` | M1-3b spawn experiment: spawn, controller (b2), position samples (b3), remove (b4) |
| `mod/ue4ss/PawHome/Scripts/main.lua` | UE4SS entry point: starts the engine, hourly tick, debug keys, auto-explore |
| `mod/ue4ss/PawHome/enabled.txt` | Makes UE4SS load the mod |
| `scripts/install-ue4ss.ps1` | Copies the entry point + engine into `ue4ss\Mods\PawHome` (`-Uninstall` to remove) |
| `tests/test_ue4ss.lua` | offline tests: storage, backup rotation, `saveGetBackup` and corrupt-save recovery, slots, caps/safe mode, build fingerprint, object dump, wallet, virtual-pet adoption, discovery |
| `tests/test_ue4ss_main.lua` | entry point with stubbed UE4SS globals: hourly tick, swallowed errors, banner, safe mode, kill switch, debug opt-in, clock across restarts, debug keys, auto-explore, Shift+F6 |
| `tests/test_ue4ss_probe.lua` | spawn probe with a fake engine: b1–b4 log lines, LoadAsset fallback, failures as log lines, stale references |
| `scripts/smoke-t1.ps1` | T1 main-menu smoke: V1, V6, read-back, rotation; never kills the game unless `-ForceClose` |

## Verification status

Evidence: the ZoiPets run on **inZOI v0.10.0** (build 20260915.15331, 2026-09-25) and the
PawHome T1 smoke on **v0.11.0** (build 20261013.16166, 2026-10-19,
`docs/qa/results/2026-10-19-20261013.16166.W-334313.md`). That first T1 run started with
no previous save (`started (new)`), so only the first write was exercised. A second T1 on
the same build (2026-10-20, `docs/qa/results/2026-10-20-20261013.16166.W-334313.md`) read
the existing save back (`started (loaded)`) and found the previous save in the `.bak`
generations; the game closed normally.

| Adapter function | Status | Evidence / blocker |
|---|---|---|
| `saveSet` first write (`io.open` + rename into place) | Verified on v0.10.0 and v0.11.0 | ZoiPets save file; PawHome T1 save file |
| `saveGet` reading an existing save | Verified on v0.11.0 | second T1: `started (loaded)` |
| `.bak1`–`.bak3` rotation (`os.rename` / `os.remove`) | Verified on v0.11.0 | second T1: `.bak` files are created and one has the pre-run save's content (found as `.bak1` right after the first new save). In that run the four files had four distinct contents and last-write times falling with the generation number, so the match identifies the pre-run save (addendum in the result file). A hash match alone would not prove order if saves were byte-identical; the smoke result now records the number of distinct contents and the times, and the order is only treated as verified when they differ |
| `.bak1` fallback read (main file missing) | **Unverified** | same `io.open` read as `saveGet`, but the fallback branch never ran in-game |
| `saveGetBackup(key, n)` (reads `.bakN`, 1 ≤ n ≤ 3) | **Unverified** | engine uses it only when the current save cannot be parsed (`core/storage.lua`); offline end-to-end test recovers a pet from `.bak1` |
| `logSink` (print -> UE4SS.log) | Verified on v0.10.0 and v0.11.0 | `[PawHome]` lines in the T1 result |
| `discover` (ForEachUObject scan) | Verified on v0.10.0 (main menu) and v0.11.0 (main menu and city) | v0.11.0 city: 584,408 objects in 10.4 s; found `BP_Void_Cat_C`, `Void_Cat1_C`, `B1TimeManager`, `BP_Computer01_C` (T2 result 2026-10-20) |
| `now` (game clock) | **Unverified** | debug clock only. `B1TimeManager` exists (main menu and city, under the game instance) and has `GetCurrentDateTime` / `GetTimeScale`, but neither was called: return type and units unknown |
| `slotId` (save slot id) | **Unverified** | constant `"debug"`; needs V3. `nil` from a slot function = no save loaded → no reads, writes refused |
| `subscribe` | Not implemented | no game event known; the app polls `slotId()` |
| `locale` | **Unverified** | constant `zh-TW` |
| `notify` | Log only | no in-game toast API found |
| `funds` / `charge` | Debug wallet only | real money API not found |
| `householdMembers`, `addBuff`, `listStrays`, `bringStray`, `spawnPet`, `entityExists`, `despawnPet`, `releaseStray`, `playAnimation` | Not implemented | need in-save probes V2–V5 |
| `caps` | all `false` | nothing spawn/move/animate-related has been tested |
| Debug keys Shift+F6/F7/F8/F9/F10 | **Unverified** | registered the same way as ZoiPets' keys, never pressed in-game |
| Spawn probe (`StaticFindObject`, `LoadAsset`, `World:SpawnActor`, `K2_GetActorLocation`, `K2_DestroyActor`, UEHelpers) | **Unverified** | call shapes copied from mods bundled with UE4SS v3.0.1 (BPModLoaderMod, ConsoleCommandsMod); never run by us |
| Auto-explore (`RegisterHook` on `PlayerController:ClientRestart`, `ExecuteWithDelay`, `ExecuteInGameThread`) | Verified on v0.11.0 | T2 2026-10-20: our callback fired at the main menu and again later; pending flag ignored a trigger 7 s after the first; scans ran 60 s after a trigger |
| `dumpObject` (ForEachProperty / ForEachFunction / GetSuperStruct, property reads), `FindFirstOf` | Verified on v0.11.0 | T2 2026-10-20: dumps of 239, 291, 381 and 11 lines, including `ObjectProperty` references and enum/bool values |
| `buildFingerprint` / safe mode | Verified on v0.11.0 | banner showed `build size:289803704 (SAFE MODE)`; matches the exe size |

With every cap off the engine runs as the virtual pet (plan C): shelter adoption,
needs, care, neglect and the shelter all work, but no cat appears in the world.

## What is known about in-game cats (facts only)

Source: ZoiPets discovery scan, **main menu only**, inZOI v0.10.0, 2026-09-25
(two autoruns, same results). Nothing below was observed inside a save.

| Item | Observed |
|---|---|
| Lobby cat actor | `BP_Pet_Customize_01_C` instance `BP_Pet_Customize_01_62` in `/Game/Map/LobbyLevel2` |
| Class asset | `/Game/Characters/Pets/Operator/OP001/Mesh/BP_Pet_Customize_01.BP_Pet_Customize_01_C` |
| Components | `SkeletalMesh` (SkeletalMeshComponent), `Capsule` (CapsuleComponent), two `AudioComponent`s |
| Animation | anim instance `ABP_LobbyCat_C` on the SkeletalMesh |
| Material | `MI_OP002_Body_001_Animated` (MaterialInstanceDynamic) |
| Asset folder | `/Game/Characters/Pets/` exists (only the `Operator/OP001` path has been seen) |

### In the city (T2 / M1-3a, v0.11.0 build 20261013.16166, 2026-10-20)

Full details and the evidence table: `docs/qa/results/2026-10-20-t2-m1-3a-20261013.16166.W-334313.md`.

| Item | Observed |
|---|---|
| `BP_Void_Cat_C` ×7 | `/Game/Blueprint/GameObject/Animal/BP_Void_Cat.BP_Void_Cat_C`; a `B1GameObject` (not a Pawn) with static meshes, baked animation (`B1AnimToTex`), interaction components, no movement component, no Controller property |
| `Void_Cat1_C` ×1 | `/Game/Characters/Void/Void_Cat/Void_Cat1.Void_Cat1_C`; a Character with skeletal mesh, capsule and `CharacterMovementComponent`; `Controller` = a stock `AIController` instance, `AIControllerClass` = `/Script/AIModule.AIController`, `AutoPossessAI = 1` |
| Game clock candidate | `B1TimeManager` under `BP_B1GameInstance_C`; functions `GetCurrentDateTime`, `GetTimeScale` (not called yet) |
| Computer | `BP_Computer01_C` (`/Game/Blueprint/GameObject/Furniture/BP_Computer01.BP_Computer01_C`) |

Not known yet (do not build on these):
- Which of the two city cat classes is the stray cat the player feeds (Coexistence ≥ 60),
  and whether more `Void_Cat1_C` exist outside the loaded area. The lobby cat
  `BP_Pet_Customize_01_C` is not loaded in the city.
- What drives the `AIController` of `Void_Cat1_C` (the controller was not dumped; no
  behaviour tree / blackboard property showed on the pawn) and whether that cat walks by itself.
- Whether a *spawned* `Void_Cat1_C` gets a controller. By standard Unreal semantics
  `AutoPossessAI = 1` would mean placed-in-world only (unverified here), so a spawned one
  may have none until `SpawnDefaultController()` is called; the probe does not call it yet.
- Whether spawning any of these classes works, moves, or ends up in the game's own save.
- The return type and units of `GetCurrentDateTime` / `GetTimeScale`, any save-slot id or
  household id source, whether the computer's interaction menu can be extended.

## Engine notes for the owner (no engine rules were changed)

1. Adoption calls `Api.funds`, so without a money API in-game adoption only works
   through the debug wallet (`DEBUG_FUNDS` in `main.lua`).
2. `householdId` / `zoiId` are constants (1 / 1) in the entry point until the
   in-save probes find the real ids.
3. **Debug clock (known limitation).** It counts from a fixed epoch (2026-01-01 UTC),
   so it keeps increasing across restarts instead of restarting at 0. Side effect:
   real time while the game was closed also counts as game time; the engine caps the
   catch-up at `catchupCapHours`. Only the debug flow has this clock.
4. `sanitize()` maps `a/b` and `a_b` to the same file name. Real slot ids are not
   known yet (V3); check for collisions when they are.
5. **Save-slot switch – handled.** `App` now polls `Api.slotId()` and reloads the
   state when the slot changes (engine fix a240f2f). The adapter implements
   `slotId()`; `subscribe()` is not implemented (no "save loaded" game event is
   known, polling covers it). When a slot function is given and it returns `nil`
   (no save loaded, e.g. a loading screen), the adapter reads nothing and refuses
   writes instead of falling back to another slot's file. The real slot id is still
   **unverified** (V3); the entry point uses the constant `"debug"`.

## Tests

`py -I tests\run.py` needs `lupa`. Plain Lua 5.4 works too:

```
lua -e "package.path='mod/lua/?.lua;tests/?.lua;'..package.path" tests/run.lua
```
