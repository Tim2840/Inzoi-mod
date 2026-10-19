# Changelog
All notable changes are listed here ([Keep a Changelog](https://keepachangelog.com/), [SemVer](https://semver.org/)). Versions below 1.0 make no compatibility promise.

## [Unreleased]
### Added
- UE4SS route (`adapters/ue4ss.lua`, `mod/ue4ss/PawHome`, `scripts/install-ue4ss.ps1`): runs the engine inside inZOI through UE4SS with all caps off (virtual pet). Safe mode for unknown game builds, kill switch, startup banner, three save generations, debug mode only with `pawhome_debug.txt`. T1 main-menu smoke passed twice on inZOI v0.11.0 (first write, read-back and `.bak` rotation verified in-game); everything that touches the game world is written but **unverified** (`docs/ue4ss-adapter.md`).
- M1-3 tooling: object dump (Shift+F7), discovery scan with animal dumps (Shift+F8) and opt-in auto-explore after a map load (all ran in the city on inZOI v0.11.0, 2026-10-20: two city cat classes, a stock AIController on `Void_Cat1_C`, `B1TimeManager`). Not run in-game yet: the b0 observation of the existing city cat (Shift+F5 and after each auto scan: controller and brain dump, 60 s of position samples, spawns and removes nothing) and the spawn probe (Shift+F6, optional `SpawnDefaultController`).
- `scripts/smoke-t1.ps1` (automated T1 run, writes `docs/qa/results/`) and `docs/qa/smoke-checklist.md` (T2 steps and evidence).
- Optional adapter function `saveGetBackup(key, n)`: when the current save cannot be read, the mod restores the newest readable older generation instead of starting fresh.
### Changed
- A cat that is missing from the world is replaced at most once per game hour, the old reference is despawned first (no duplicates), and after five failures in a row the pet is left alone until the next game day.
- CI also runs the tests on Windows.

### Fixed
- If the game clock goes backwards (an older game save is loaded, or a debug clock restarts) every stored timer is shifted, so the remaining time of cooldowns, the shelter wait and the rehoming countdown is unchanged.
- Switching savegame slots no longer reads or writes the wrong slot: the mod now follows `slotId()` and never writes the old state into the new slot (new optional adapter functions `slotId` and `subscribe`). A slot-aware adapter that reports "no save loaded" (`slotId()` = nil, e.g. a loading screen) pauses the mod: nothing is read, written or charged until a save is loaded.
### Added
- Pet engine: needs, 13 personality traits, life stages, bond, Pet Training, care actions, shelter adoption, stray adoption.
- Neglect model: soft penalty, animal control warning, shelter, paid redemption, rehoming (ADR 0002).
- Desktop preview of the UI, 67 automated tests, setup scripts and documentation.
