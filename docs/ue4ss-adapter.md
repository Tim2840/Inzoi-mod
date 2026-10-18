# UE4SS adapter (`adapters/ue4ss.lua`)

Runs the Paw Home engine inside inZOI through UE4SS (the route the ZoiPets project
verified), instead of the official ModKit Lua runtime. Branch: `ue4ss-adapter`
(to be pushed as `feat/ue4ss-adapter`).

## Operating the mod

| Feature | How |
|---|---|
| Startup banner | First `[PawHome]` line in `UE4SS.log`: mod version, Lua version, build fingerprint, `verified` / `SAFE MODE`, caps, debug flag |
| Kill switch | Create `pawhome_disabled.txt` in `ue4ss\Mods\PawHome\` → nothing starts (no loop, no keys, saves untouched). Delete it to re-enable |
| Safe mode | Build fingerprint = size of `inZOI-Win64-Shipping.exe`. Unless that fingerprint is listed in `pawhome_verified_builds.txt` (one `size:<n> <note>` per line), every cap is forced off. Add a line **only after** M1-3b evidence for that build |
| Save backups | Each save keeps `.bak1` (newest) … `.bak3`. Recovery: close the game, rename the wanted `.bakN` to the `.sav` name |
| Rollback | `scripts\install-ue4ss.ps1 -Uninstall` removes the scripts and keeps saves; restore a `.bakN` if a save is bad |

Debug keys (DEBUG = true in `main.lua`): Shift+F7 dump properties/functions of the
first `BP_Pet_Customize_01_C` → `pawhome_dump.txt`; Shift+F8 discovery scan →
`pawhome_discovery.txt`; Shift+F9 adopt the first shelter offer; Shift+F10 print pets.

## Files

| File | Role |
|---|---|
| `mod/lua/pawhome/adapters/ue4ss.lua` | Adapter (contract in `core/api.lua`) + read-only discovery scan |
| `mod/ue4ss/PawHome/Scripts/main.lua` | UE4SS entry point: starts the engine, hourly tick, debug keys |
| `mod/ue4ss/PawHome/enabled.txt` | Makes UE4SS load the mod |
| `scripts/install-ue4ss.ps1` | Copies the entry point + engine into `ue4ss\Mods\PawHome` (`-Uninstall` to remove) |
| `tests/test_ue4ss.lua` | 13 offline tests (storage, backup rotation, slots, caps/safe mode, build fingerprint, object dump, wallet, virtual-pet adoption, discovery) |
| `tests/test_ue4ss_main.lua` | 9 offline tests of the entry point with stubbed UE4SS globals (hourly tick, swallowed errors, banner, safe mode, kill switch, debug keys) |

## Verification status

Evidence comes from the ZoiPets run on **inZOI v0.10.0** (build 20260915.15331,
2026-09-25). **v0.11.0 (build 20261013.16166) has not been re-tested.**

| Adapter function | Status | Evidence / blocker |
|---|---|---|
| `saveGet` / `saveSet` (files in the mod folder) | Verified on v0.10.0 | ZoiPets wrote its save file via `io.open` |
| `logSink` (print -> UE4SS.log) | Verified on v0.10.0 | `[ZoiPets] loaded` lines in UE4SS.log |
| `discover` (ForEachUObject scan) | Verified on v0.10.0 (main menu) | found `BP_Pet_Customize_01_C`, `B1TimeManager` |
| `now` (game clock) | **Unverified** | debug clock only; candidate `B1TimeManager` needs an in-save probe (V3) |
| save slot id | **Unverified** | constant `"debug"`; needs V3 |
| `locale` | **Unverified** | constant `zh-TW` |
| `notify` | Log only | no in-game toast API found |
| `funds` / `charge` | Debug wallet only | real money API not found |
| `householdMembers`, `addBuff`, `listStrays`, `bringStray`, `spawnPet`, `entityExists`, `despawnPet`, `releaseStray`, `playAnimation` | Not implemented | need in-save probes V2–V5 |
| `caps` | all `false` | nothing spawn/move/animate-related has been tested |
| Debug keys Shift+F7/F8/F9/F10 | **Unverified** | registered the same way as ZoiPets' keys, never pressed in-game |
| `dumpObject` (ForEachProperty / ForEachFunction / GetSuperStruct), `FindFirstOf` | **Unverified** | never called in inZOI; every call is pcall-wrapped |
| `buildFingerprint` / safe mode | **Unverified** in-game | plain `io.open` + `seek`, same API family as the verified save I/O |

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

Not known yet (do not build on these):
- Whether city stray cats use this class. `Operator` suggests the lobby cat belongs to the
  "cat operator" presentation; strays were not loaded at the main menu.
- Any property values, callable functions or anim-blueprint variables: the scan only
  records object names, it never dumped properties or functions.
- Whether a cat has an AI controller or behaviour tree. The scan would have listed
  names like `AIC_Cat` (none appeared), but it does not search for AI classes in
  general, so this is **no evidence either way**.
- Whether spawning `BP_Pet_Customize_01_C` in a save works, moves, or gets written
  into the game's own save file.

## Engine notes for the owner (no engine rules were changed)

1. Adoption calls `Api.funds`, so without a money API in-game adoption only works
   through the debug wallet (`DEBUG_FUNDS` in `main.lua`).
2. `householdId` / `zoiId` are constants (1 / 1) in the entry point until the
   in-save probes find the real ids.
3. **Known limitation – save-slot switch.** The adapter stores files per slot, but
   `App` reads the state once in `App.new`. If the player loads a different save
   while the game keeps running, the engine keeps the old state and writes it into
   the new slot. Today the slot is the constant `"debug"`, so this cannot trigger
   yet; it must be fixed before a real slot id is wired in. Proposed fix (needs the
   contract owner): an optional game→engine event such as `slot_changed` that makes
   `App` reload (raised as a major in the review of `docs/proposals/adapter-contract-physical-cat.md`).

## Tests

`py -I tests\run.py` needs `lupa`. Plain Lua 5.4 works too:

```
lua -e "package.path='mod/lua/?.lua;tests/?.lua;'..package.path" tests/run.lua
```
