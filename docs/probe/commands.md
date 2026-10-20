# P1：CLI 指令清單（從 ModKit 附帶的 `cli_catalog.json` 產生）

> 來源：`C:\Games\inZOIModKit\inZOIModKit\Data\Tools\mcp\modkit\cli_catalog.json`（ModKit `20261011.16078`），2026-10-20 讀取。
> 這份是**目錄**，不是遊戲內實測：指令在遊戲裡能不能成功、回傳什麼，要到 P2–P6 才驗證。
> 產生方式：一支只做關鍵字篩選與排版的 Python 腳本（不在 repo 內；重產時對照本頁規則即可）。

- 總數 **406** 個；`access`：`Public` 146、`ScriptCheat` 111、`UserCheat` 149。
- 目錄自己有 `access` 欄位，回答了「Public／非 Public」：`Public` 一般可用；`UserCheat`／`ScriptCheat` 是作弊層級（CLAUDE.md 規則 3：弄清楚之前不依賴）。目錄中 `ambition.complete` 的說明寫著 *cheat; no-op in shipping builds*，所以**作弊層級在正式版可能直接無效**——要實測。
- `scope`：`B2Authority`（模擬層）、`B1Standalone`／`B1Multicast`（呈現層）、`Both`。
- 沒有 `pet`／`animal`／`cat` 類別。說明裡提到動物的只有 `simulation.set_density` 的 `animal`（0–5）密度。
- 命中關鍵字的指令共 **85** 個（Public 排前面）。

## 關鍵字命中的指令

關鍵字：`pet`、`animal`、`cat`、`coexist`、`spawn`、`teleport`、`move`、`follow`、`relationship`、`need`、`buff`、`mood`、`emotion`、`notif`、`toast`、`popup`、`save`、`timer`、`time`、`event`、`interaction`、`motion`。pet／animal／cat／coexist／spawn 比對 id、名稱與說明；其餘只比對 id、名稱、別名（避免說明裡的常見字灌水）。

| 指令 ID | access | scope | 參數（`?`＝選填） | 說明（截短） | 命中 |
|---|---|---|---|---|---|
| `autonomy.diagnose_interaction` | Public | B2Authority | bag_id, entity_id?, target_entity_id? | Diagnose why an interaction bag is or is not an autonomy candidate. | interaction |
| `build.get_mode_state` | Public | B1Standalone | include_options? | Returns whether build mode is active and which lifecycle phase it is in. Entering is asynchronous (packet round-trip, streaming grid load... | spawn |
| `character.possess` | Public | B1Standalone | character_id, household_id? | Switches play to the specified character. Same household -> avatar swap; different household -> household switch. Handles camera, spawn, ... | spawn |
| `emotion.get_current` | Public | B2Authority | entity_id? | Returns the current emotion type and level for the target character. | emotion |
| `emotion.list_all` | Public | B2Authority | — | Returns all emotion types with localized names, tendency, and max level. | emotion |
| `entity.get_simulate_state` | Public | B2Authority | entity_id?, entity_ids? | Check whether a character entity is currently simulated (spawned on-screen). Supports batch query via comma-separated entity_ids. | spawn |
| `environment.get_time` | Public | B1Standalone | — | Returns the current in-game time (hour, minute, day). Runs locally on B1. | time |
| `event.describe` | Public | B1Standalone | name | Returns the payload schema of a specific game event | event |
| `event.list` | Public | B1Standalone | — | Returns all registered game events with their payload schemas | event |
| `game.list_move_in_sites` | Public | B1Standalone | only_affordable?, limit? | Lists unowned residence sites the current household could move into, cheapest affordable first. Reads the world map UI data when the map ... | move |
| `game.list_saves` | Public | B1Standalone | include_autosave?, include_broken?, limit?, offset?, refresh? | Returns save slots sorted by saved_time descending (newest first), one page at a time. Feed 'folder' (and 'file' when it differs) into ga... | save |
| `household.possess` | Public | B1Standalone | household_id | Switches play to the specified household via normal client flow. Handles camera, spawn, and UI transition. | spawn |
| `household_biz.get_remain_time` | Public | B2Authority | household_biz_id? | Returns the remaining operating time for a household business today. | time |
| `household_biz.get_restaurant_task_status` | Public | B2Authority | household_biz_id? | Returns whether a household business is a restaurant template and whether its reconciler TimeTask is currently registered, plus configure... | spawn |
| `interaction.get_current` | Public | B2Authority | entity_id? | Returns information about the character's currently playing interaction: interaction_bag_id, state (Waiting/StandBy/Playing), action_type... | interaction |
| `interaction.get_queue` | Public | B2Authority | entity_id? | Returns the interaction queue status: queue count, whether it's empty, and the currently playing interaction info. | interaction |
| `interaction.list_available` | Public | B2Authority | entity_id?, target_entity_id | Lists all available interactions for a target entity. Returns interaction_bag_id values that can be passed to interaction.execute. For ob... | interaction |
| `interaction.search` | Public | B2Authority | keyword, max_results? | Searches InteractionBag data table by keyword. Matches against row ID, category, and tags. Returns interaction_bag_id values usable with ... | interaction |
| `movement.approach` | Public | B2Authority | entity_id | Walks the possessed character toward the specified target entity. | move |
| `movement.get_site_move_interaction` | Public | B2Authority | site_id?, target_entity_id?, entity_id? | Returns an interaction.execute descriptor for walking a single character to a target site without creating a Zoi group. | move, interaction |
| `movement.summon` | Public | B2Authority | entity_id | Teleports the target character to near the possessed character. | move |
| `movement.summon_batch` | Public | B2Authority | entity_ids | Teleports multiple characters to near the possessed character. Possessed character is automatically excluded. | move |
| `movement.teleport_to` | Public | B2Authority | entity_id | Teleports the possessed character near the specified target entity. | teleport, move |
| `relationships.get_value` | Public | B2Authority | entity_id, relationship_id? | Returns relationship stat values for the target entity. | relationship |
| `relationships.get_value_between` | Public | B2Authority | owner_id, target_id, relationship_id? | Returns relationship stat values from owner toward target. Unlike relationships.get_value, the owner is explicitly specified instead of d... | relationship |
| `relationships.list` | Public | B2Authority | owner_id, min_value? | Returns all relationships a character has, with each partner's name and relationship stats. Use min_value to filter out weak (e.g. crowd)... | relationship |
| `simulation.get_settings` | Public | B1Standalone | — | Returns current simulation settings: preset, population/business/vehicle/animal density, disaster/ghost toggles, temperature effect, cost... | animal |
| `social_event.debug` | Public | B2Authority | entity_id? | Prints on-screen debug summary/roles of the social event the given entity participates in. Defaults to possessed character. | event |
| `social_event.debug_by_id` | Public | B2Authority | social_event_id | Prints on-screen debug summary/roles of a social event by its runtime SiteEvent id. | event |
| `toast.clear` | Public | B1Standalone | — | Clear every queued and currently visible toast message on the local client. | toast |
| `toast.show` | Public | B1Standalone | message, lifetime?, immediate? | Display a transient system-message toast on the local client. Purely presentational: no save, no broadcast, no gameplay effect. Default l... | toast |
| `ui.get_blocking` | Public | B1Standalone | — | Returns a snapshot of everything currently blocking gameplay input: loading screens, modal popups, the cat-talk tutorial overlay, coach m... | cat |
| `uimod.cfg_save` | Public | B1Standalone | mod_id, section, key, value | Saves a value to a file under the mod's cfg directory. | save |
| `asset.preview` | ScriptCheat | B1Standalone | path, x?, y?, yaw? | TEST-PLACE a catalog asset (by ObjectPath) to visually confirm it is the right asset. This is a TRANSIENT PREVIEW, NOT a permanent placem... | spawn |
| `buff.add` | ScriptCheat | B2Authority | entity_id?, buff_id, duration_minutes? | Adds a buff to the target character. Optionally overrides its lifetime with duration_minutes (finite-duration buffs only; omit to use the... | buff |
| `buff.remove` | ScriptCheat | B2Authority | entity_id?, buff_id | Removes a buff from the target character. | buff |
| `build.enter_mode` | UserCheat | B1Standalone | site_id?, need_map_mode_open? | Requests entry into build mode for a site. This is ASYNCHRONOUS and returns as soon as the request is accepted: the entry runs a packet r... | spawn |
| `building.move_object` | ScriptCheat | B1Standalone | entity_id, loc_x?, loc_y?, loc_z?, pitch?, yaw?, roll?, scale?, scale_x?, scale_y?, scale_z?, floor_level?, clean_floor? | [Build Mode Only] Moves, rotates, rescales and/or re-floors a single placed object through the build undo/redo stack (revert with buildin... | move |
| `building.reset_site_to_last_saved` | ScriptCheat | B1Standalone | confirm_phrase | [Build Mode Only] DESTRUCTIVE. Discards every edit made in this build-mode session and restores the site (objects, walls and household in... | save |
| `emotion.set` | ScriptCheat | B2Authority | entity_id?, type, level? | Sets the cheat emotion on the target character. Use 'Normal' or empty to clear. e.g. type=Happy level=3 | emotion |
| `entity.attach_prop` | UserCheat | B1Multicast | entity_id?, action?, object_id?, type?, bone?, filter?, prop_index?, x?, y?, z?, rx?, ry?, rz?, sx?, sy?, sz? | Spawn an object or vehicle and attach it to a character bone. action=list_sockets [filter=<kw>]: list mesh sockets. action=attach object_... | spawn |
| `environment.set_time` | UserCheat | B2Authority | day?, hour?, minute?, allow_rewind? | Jumps to a specific in-game time. With only hour/minute it moves to the next occurrence (forward). With 'day' it jumps to that absolute i... | time |
| `environment.time_skip` | UserCheat | B2Authority | days?, hours?, minutes? | Skips game time forward by the given days/hours/minutes. | time |
| `environment.time_speed` | UserCheat | B2Authority | speed | Sets the global time speed multiplier. | time |
| `fx.spawn` | UserCheat | B2Authority | fx_id, entity_id?, socket?, x?, y?, z?, pitch?, yaw?, roll?, scale?, scale_x?, scale_y?, scale_z?, with_handle? | Spawns an FX table entry at an explicit world transform or attached to an entity. Spawner-backed montage FX are played through a transien... | spawn |
| `game.continue` | UserCheat | B1Standalone | include_autosave? | Loads the most recently saved (by saved_time) non-broken save. AutoSave slots are skipped by default. Saves written by a NEWER build are ... | save |
| `game.load` | UserCheat | B1Standalone | folder, file? | Loads a specific save slot. This is ASYNCHRONOUS and returns as soon as the request is accepted: poll game.get_state until phase == 'in_g... | save |
| `game.move_in` | UserCheat | B1Standalone | site_id, mortgage?, family_option?, site_option? | Moves the newly registered household into a residence site during the initial site selection, possesses a character and starts play. Requ... | move |
| `household_biz.set_work_time` | UserCheat | B2Authority | start_hhmm, end_hhmm, household_biz_id? | Sets the daily operating start/end time (HHMM, e.g. 900, 1800) for a household business. | time |
| `household_biz.spawn_random_employee` | UserCheat | B2Authority | household_biz_id? | Generates and hires a random employee candidate for a household business. | spawn |
| `interaction.cancel` | UserCheat | B2Authority | entity_id? | Cancels the currently playing interaction. Does NOT disable autonomy (unlike zoi.freeze). The character will proceed to the next queued i... | interaction |
| `interaction.clear_queue` | UserCheat | B2Authority | entity_id?, cancel_current? | Clears all queued interactions. By default keeps the currently playing interaction; set cancel_current=true to also cancel it. | interaction |
| `interaction.execute` | UserCheat | B2Authority | entity_id?, interaction_bag_id, target_entity_id?, smartzoi?, insert_front? | Queues a specific interaction on a character by InteractionBagId. The character will walk to the target and perform the interaction. | interaction |
| `interaction.set_reward` | UserCheat | B2Authority | interaction_bag_id, reward | Overrides InteractionRewards.Reward (autonomy selection weight) of an InteractionBag at runtime, applied to all its reward entries. For t... | interaction |
| `motion.get_current` | UserCheat | B2Authority | entity_id? | Get the motion(s) currently playing on the target Zoi. Returns playing=false if idle, otherwise an array of active montage instances with... | motion |
| `motion.get_info` | UserCheat | B2Authority | anim_id, entity_id? | Get metadata for a motion: total_length, loop_length, rate_scale, blend_out_time, sections (with names, start times, loop flags, next-sec... | motion |
| `motion.list` | UserCheat | B2Authority | filter?, max?, validate?, entity_id? | List CharacterAnim DataTable row IDs that can be played on a Zoi. IMPORTANT -- filter is effectively REQUIRED: the table holds thousands ... | motion |
| `motion.play` | UserCheat | B2Authority | anim_id, entity_id?, section?, position? | Play a character animation on the target Zoi. anim_id: CharacterAnim row name (use motion.list to find). section: start section name (Def... | motion |
| `motion.play_random` | UserCheat | B2Authority | filter, entity_id?, section?, position? | Pick a random motion matching the filter and play it on the target Zoi. Only motions playable by the character (gender/age/posture compat... | motion |
| `motion.stop` | UserCheat | B2Authority | entity_id?, anim_id? | Stop a playing animation on the target Zoi. Omit anim_id to stop all currently playing motions. | motion |
| `movement.go_home` | UserCheat | B2Authority | entity_id? | Teleports the specified character to their home site. | move |
| `movement.reset_zoi` | UserCheat | B2Authority | entity_id?, teleport?, gated? | Force-recovers a stuck/bugged character: clears current+queued interactions, stops action/anim, resets movement/path, releases grab, clea... | spawn, move |
| `movement.set_speed` | UserCheat | B1Multicast | entity_id?, action?, speed? | Get, set, or reset MaxWalkSpeed (cm/s). Default walk=190, sprint=400. action=get: returns current and default values. action=set speed=<f... | move |
| `movement.teleport` | UserCheat | B2Authority | destination?, x?, y?, z?, entity_id? | Teleports the specified character to a destination site or world coordinates. | teleport, move |
| `movement.teleport_npc_to` | UserCheat | B2Authority | entity_id, target_entity_id | Teleports a character to near another character. Unlike movement.teleport_to, neither character needs to be possessed. | teleport, move |
| `needs.freeze_all` | UserCheat | B2Authority | entity_id?, enable | Freezes or unfreezes need decay for the target character. | need |
| `needs.freeze_all_system` | UserCheat | B2Authority | enable | Freezes or unfreezes the needs system globally. | need |
| `needs.set_full` | UserCheat | B2Authority | category?, entity_id? | Fills the specified need category on the target character, or all needs when category is empty. | need |
| `relationships.obliviate` | UserCheat | B2Authority | — | Reset all relationships for the possessed character. | relationship |
| `relationships.set_full` | UserCheat | B2Authority | entity_id, relationship_id? | Max out relationship value for an entity. | relationship |
| `relationships.set_value` | UserCheat | B2Authority | entity_id, value, relationship_id? | Set relationship value for an entity. | relationship |
| `relationships.set_value_between` | UserCheat | B2Authority | owner_id, target_id, value, relationship_id? | Sets relationship stat value between any two characters (always bidirectional). Romance stat is guarded by IsLovable; family stat require... | relationship |
| `relationships.set_worst` | UserCheat | B2Authority | entity_id, relationship_id? | Minimize relationship value for an entity. | relationship |
| `relationships.unlock_profile` | UserCheat | B2Authority | entity_id | Unlock profile for the given entity. | relationship |
| `simulation.set_density` | ScriptCheat | B1Standalone | kind, value | Set an individual density level for a simulation category. Kinds: population (0-10), biz_customer (0-10), vehicle (0-10), animal (0-5). C... | animal |
| `smartbuild.import_and_place_mesh` | ScriptCheat | B1Standalone | file_path, x, y, yaw? | Runtime-import a 3D mesh file (.glb/.gltf) and spawn it at the world location under the given screen pixel. Used by the file drag-and-dro... | spawn |
| `smartbuild.shape` | ScriptCheat | B1Standalone | action?, shape?, handle?, x?, y?, z?, rx?, ry?, rz?, sx?, sy?, sz?, r?, g?, b?, label?, all? | Spawn primitive shapes (cube/sphere/cylinder/cone/plane) at world coordinates and control their transform/color/lifetime via a handle. Us... | spawn |
| `social_event.apply` | UserCheat | B2Authority | social_event_id, group_type?, site_id? | Cheat-creates a social event (SiteEvent) at the possessed character's site using the given template id. Mirrors UB2CheatManager::B2ApplyS... | event |
| `social_event.cancel_role_check` | UserCheat | B2Authority | social_event_id | Forces re-evaluation of role conditions for all members of a social event, removing or canceling members that fail. | event |
| `ui.click_popup_button` | UserCheat | B1Standalone | popup_id?, list_key?, index? | Clicks a button on an opened popup through the normal path (closes the popup, runs the bound script and delegate). 'index' is a BUTTON in... | popup |
| `ui.close_cat_talk` | UserCheat | B1Standalone | — | Closes the cat-talk (Psycat) overlay that gates the intro tutorial. Fails when there is no world, or when the overlay is not currently vi... | cat |
| `ui.dismiss` | UserCheat | B1Standalone | max_steps? | Closes the top-most blocking UI, up to max_steps elements in one call. Priority: coach mark -> cat talk -> popup -> ESC stack -> cutscene... | cat |
| `visual.hide_cat_eye` | UserCheat | B2Authority | enable | Hides the cat eye camera overlay. | cat |
| `zoi_group.follow` | UserCheat | B2Authority | entity_id? | Makes all non-leader group members walk to the leader's current position. Call repeatedly to keep members following as the leader moves. ... | follow |
| `zoi_group.move_to` | UserCheat | B2Authority | entity_id?, destination | Makes the entire Zoi group walk together to a destination site. Members gather near the leader first, then move as a group. Far members a... | move |
