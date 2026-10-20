# Changelog
All notable changes are listed here ([Keep a Changelog](https://keepachangelog.com/), [SemVer](https://semver.org/)). Versions below 1.0 make no compatibility promise.

## [Unreleased]
### Added
- ADR 0007: plan C (virtual pet) plus city adoption, engine stays in Lua; phase 0 in-game results (B2/B1/UI data channel, city cats, build-mode placement) in `docs/phase0-results.md`.
- `tools/game_mcp.py`: call the running game's MCP server from the repo (used for automated in-game probing).
- Phase 0 desk research for the official ModKit route (`docs/phase0-results.md`, `docs/probe/commands.md`, `docs/probe/lua-api.md`): CLI catalog by access level, Lua bindings/callbacks/events, UI-mod save state, cat object templates found in the ModKit binding keys. Nothing verified in-game yet.
- UE4SS route (`adapters/ue4ss.lua`, `mod/ue4ss/PawHome`, `scripts/install-ue4ss.ps1`): runs the engine inside inZOI through UE4SS with all caps off (virtual pet). Safe mode for unknown game builds, kill switch, startup banner, three save generations, debug mode only with `pawhome_debug.txt`. T1 main-menu smoke passed twice on inZOI v0.11.0 (first write, read-back and `.bak` rotation verified in-game); everything that touches the game world is written but **unverified** (`docs/ue4ss-adapter.md`).
- M1-3 tooling, never run in-game: object dump (Shift+F7), discovery scan with animal dumps (Shift+F8), opt-in auto-explore after a map load, and a spawn probe (Shift+F6) that logs spawn result, controller, 60 s of position samples and removal.
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
