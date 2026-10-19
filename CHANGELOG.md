# Changelog
All notable changes are listed here ([Keep a Changelog](https://keepachangelog.com/), [SemVer](https://semver.org/)). Versions below 1.0 make no compatibility promise.

## [Unreleased]
### Added
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
