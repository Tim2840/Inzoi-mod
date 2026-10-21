# Changelog
All notable changes are listed here ([Keep a Changelog](https://keepachangelog.com/), [SemVer](https://semver.org/)). Versions below 1.0 make no compatibility promise.

## [Unreleased]
### Added
- Food bowl and litter box menus (game-verified 2026-10-22 through the CLI): "Fill the Food Bowl" / "Let the Cat Eat from the Bowl" on a Paw Home food bowl, "Add Cat Litter" / "Clean Litter Box" on the litter box. Hungry cats eat from a filled bowl by themselves and are put in front of it. Results show as game toasts. Save format v6.
- Called cats land on the Zoi's floor (not under a deck) and in a spot clear of furniture.
- Cat Moments (`docs/design/gameplay-v2.md`): cats have wants (feed, play, cuddle, clean the litter) shown as a thought bubble; meeting a want is a happy moment (needs, bond and training gain more, the cat reacts at once). No cooldowns; repeating one action gives less each time (`data/care.lua`). Save format v5 (`album`).
- Keepsakes: a happy moment can make the cat bring a gift, which is a real game item (stone, catnip candy, cat treat, cat toy, plush, bouquet, ribbon, amethyst, aquamarine, emerald) put in the Zoi's bag with a data script (`PawHome_Gift_*`, verified in game 2026-10-22: the cat treat made "Give Treat to Cat" usable). Keepsake album tab in the panel.
- Care from the cat's own interaction menu: Pet Gently, Give Treat, Give Catnip Candy (vanilla bags appended to `DEV_Void_Cat`) count like Give Snack and Play; the panel only shows mood, needs and the album (verified in game 2026-10-22).
- Litter now needs a litter box on the lot (`PawHome_LitterBox`, engine side done and tested). Without a box the litter need does not decay and is hidden. The box object itself still has to be modelled in ModKit (not done).
- Smaller, phone-only panel (300x540) with a small draggable launcher; the computer layout and shop computer entry are gone.
- Faster buttons: the relay polls four times a second and the page answers within about 0.3 s (measured in game 2026-10-22); the game data setup is paced so the game's request limit no longer drops rows; a late-starting page asks B2 to say hello at once.
- Menu labels for our own interactions are written as `StringTableExport/mod_ST_InteractionBag_<code>.json` (unverified: needs a game restart; labels showed as raw ids before).
- `tools/make_release.py` builds the installable folder and zip; `docs/packaging.md` (format, open decisions, steps) and a bilingual `docs/player-guide.md`.
- Fixed coat: the four game coats (orange tabby, brown tabby, calico, tuxedo) are chosen when adopting and kept in the pet's data (save format v4); the B1 side sets the cat's `Color Tex` whenever the cat's actor appears and retries if the material is not ready. Coat buttons in the adoption cards, own coat-coloured cat icons. Verified in game 2026-10-22 (summon, leaving the lot and returning); reloading a saved game not yet verified.
- The home cat looks alive without walking: care from the panel plays the matching baked animation, the cat shows a mood-dependent sitting idle (now and then a short reaction such as hissing when angry), never over the game's own Play / Give Snack animations; kittens are shown at 0.6 size, elders at 0.95 (`data/animations.lua`, `data/stages.lua`; verified in game 2026-10-21).
- "Online pet shop" redesign: one UI in three shells (cat-eared phone, browser-style computer window, round launcher with Mochi the mascot), own SVG icon set (`mod/ui/icons.js`, sheet `mod/ui/icons.html`), vet button, illness toggle, cat-furniture card, backup-restore card. Launcher and phone view verified in game; icons are inline SVG because SVG `data:` URLs do not render there (`docs/research/phone-pc-ui.md`).
- Shop entries in the game's own menus as runtime data rows (`bridge.js` `SHOP_DATA`): "Paw Home pet shop" in the Zoi's phone group and "Browse the Paw Home pet shop" on computers/laptops; the phone interaction runs in game, menu visibility and labels unverified. Labels come from the localization `game` block, written by `tools/build_modkit.py` to `l10n/<culture>_mod/PawHome.po`.
- `pawhome:open` channel in the UI bridge so the Lua side can open the shop in the phone or computer shell.
- Research W1, walking cat (`docs/research/walking-cat.md`, probe in `tools/walk_probe/`): the cat is a VAT mesh with nine baked animations and no walk or run; the walk/run animations are not packaged in the game, so a smoothly walking cat is not possible with game assets. B1 Lua can move, rotate and scale the cat actor and play its baked animations (verified in game 20261019.16318.W, 2026-10-21).
- Fixed coats: every pet keeps one of the game cat's four coats (orange tabby, brown tabby, calico, tuxedo), shown in the shelter offer and choosable at adoption (`adoptOffer`/`adoptStray` take an optional `coat`). The game re-rolls a cat's coat whenever its actor is created; a B1 cat binding sets the `Color Tex` texture back (verified in game 2026-10-21, `docs/research/fixed-coat.md`). Save format v4 (older pets get a coat by id).
- Care given with the game's own cat interactions (Give Snack, Play) counts in the engine like the panel's buttons, with the same cooldowns and conditions (verified in game 2026-10-21).
- Cat furniture: the game's buildable Cat Tower, Cat Scratcher and Cat Wheel on the household's lot slow fun/energy decay; the panel lists them (`data/enrichment.lua`, `docs/research/cat-items.md`).
- Illness and the vet: upset tummy, cat cold and fleas; illness speeds up some need decay and shows as the "Unwell" mood; recovery with good care or a paid vet visit; never fatal; can be switched off. Save format v3.
- `tools/game_lock.py` (one game shared by several workers), `tools/mod_log.py` (in-game logs), `tools/ingame_smoke.py` (build, mount, load without saving, check, leave); `docs/roadmap.md` (work lines, owners, dates).
- Official ModKit route runs in the game (20261019.16318.W): B2 engine, B1 relay and the Paw Home panel; adoption charges the household's money; the adopted cat is summoned at home as a visible DEV_Void_Cat and stays bound to the pet across save and load (`docs/design/modkit-runtime.md`).
- `tools/build_modkit.py`: assembles the playable mod folder from the repo.
- ADR 0008: the home pet is a summoned `DEV_Void_Cat` (visible, interactable, persists across save/load, appearance re-randomized on load, removable with `DespawnGameObject`); the PO gives big-direction instructions only.
- ADR 0007: plan C (virtual pet) plus city adoption, engine stays in Lua; phase 0 in-game results (B2/B1/UI data channel, city cats, build-mode placement) in `docs/phase0-results.md`.
- `tools/game_mcp.py`: call the running game's MCP server from the repo (used for automated in-game probing).
- Phase 0 desk research for the official ModKit route (`docs/phase0-results.md`, `docs/probe/commands.md`, `docs/probe/lua-api.md`): CLI catalog by access level, Lua bindings/callbacks/events, UI-mod save state, cat object templates found in the ModKit binding keys. Nothing verified in-game yet.
- UE4SS route (`adapters/ue4ss.lua`, `mod/ue4ss/PawHome`, `scripts/install-ue4ss.ps1`): runs the engine inside inZOI through UE4SS with all caps off (virtual pet). Safe mode for unknown game builds, kill switch, startup banner, three save generations, debug mode only with `pawhome_debug.txt`. T1 main-menu smoke passed twice on inZOI v0.11.0 (first write, read-back and `.bak` rotation verified in-game); everything that touches the game world is written but **unverified** (`docs/ue4ss-adapter.md`).
- M1-3 tooling, never run in-game: object dump (Shift+F7), discovery scan with animal dumps (Shift+F8), opt-in auto-explore after a map load, and a spawn probe (Shift+F6) that logs spawn result, controller, 60 s of position samples and removal.
- `scripts/smoke-t1.ps1` (automated T1 run, writes `docs/qa/results/`) and `docs/qa/smoke-checklist.md` (T2 steps and evidence).
- Optional adapter function `saveGetBackup(key, n)`: when the current save cannot be read, the mod restores the newest readable older generation instead of starting fresh.
### Changed
- Coats are random now and cannot be chosen: the adoption cards show the cat's coat but have no coat buttons.
- Gifts no longer pay coins; actions have no cooldown.
- A cat that is missing from the world is replaced at most once per game hour, the old reference is despawned first (no duplicates), and after five failures in a row the pet is left alone until the next game day.
- CI also runs the tests on Windows.

### Fixed
- Pet and offer names were blank in the panel (`h()` wiped the `text` attribute).
- If the game clock goes backwards (an older game save is loaded, or a debug clock restarts) every stored timer is shifted, so the remaining time of cooldowns, the shelter wait and the rehoming countdown is unchanged.
- Switching savegame slots no longer reads or writes the wrong slot: the mod now follows `slotId()` and never writes the old state into the new slot (new optional adapter functions `slotId` and `subscribe`). A slot-aware adapter that reports "no save loaded" (`slotId()` = nil, e.g. a loading screen) pauses the mod: nothing is read, written or charged until a save is loaded.
### Added
- Pet engine: needs, 13 personality traits, life stages, bond, Pet Training, care actions, shelter adoption, stray adoption.
- Neglect model: soft penalty, animal control warning, shelter, paid redemption, rehoming (ADR 0002).
- Desktop preview of the UI, 67 automated tests, setup scripts and documentation.
