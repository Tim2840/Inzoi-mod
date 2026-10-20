# P7／P8／P9 桌面研究：Lua 與 UI 模組 API 重點

> 2026-10-20，ModKit `20261011.16078`。來源只有兩種，每條都標出來：
> - **[MCP]**：`inzoi-modkit` MCP 工具的實際回傳（`modkit_list_lua_api_catalog`、`modkit_list_lua_binding_types`、
>   `modkit_list_lua_binding_keys`、`modkit_list_lua_recipes`、`modkit_list_uimod_cli_*`）。
> - **[檔案]**：ModKit 安裝目錄 `C:\Games\inZOIModKit\inZOIModKit\Data\Tools\mcp\modkit\` 裡附的文件與目錄
>   （`workspace_docs/ws_lua_script.md`、`workspace_docs/ws_uimod.md`、`events_catalog.json`、`cli_catalog.json`、
>   `templates/ui/`、`data_asset_schemas/`）。
>
> **全部都是「文件說有」，沒有一條在遊戲裡跑過。** 遊戲端 `inzoi-game` MCP 當時連不上（遊戲沒開）。

## 1. Lua 腳本模組（P7）

### 結構 [檔案 ws_lua_script.md]
- 一個模組只有一個 Script 工作區；檔案放在 `{Plugin}/workspace/lua/`，`B2/`（模擬執行緒）與 `B1/`（呈現執行緒）分開。
- `B2/Main.lua`、`B1/Main.lua` 是開機模組：載入時跑一次、沒有 owner，用來訂閱事件、呼叫 CLI。**不能**登記成綁定。
- 其他腳本靠 `lua_manifest.json` 的 `bindings` 綁到遊戲實體，回傳 module table（`local M = {} ... return M`）。

### 綁定類型 [MCP `modkit_list_lua_binding_types`]
| env | type | key |
|---|---|---|
| B2／B1 | `Zoi` | `EB1CharacterGroupType` 或 `*` |
| B2／B1 | `ObjectTemplate` | ObjectTemplateId（自由字串）或 `*` |
| B2 | `Household` | HouseholdDtId 或 `*` |
| B2／B1 | `Vehicle` | `EB1VehicleType` |
| B2 | `Component` | `EB2ComponentType`（B1 是元件 UClass 名稱） |
| B2 | `Manager` | `EB2ManagerType`（例如 `Weather`、`Time`） |

### 生命週期回呼
- [MCP] 目錄列出：`on_begin`、`on_tick`、`on_end`、`on_lua_message`、`on_savegame`、`on_loadgame`。
- [檔案] 另外寫了：`on_possessed`／`on_unpossessed`／`on_emotion_changed`（只有 Zoi）、`on_member_enter`／`on_member_leave`（只有 Household）。
- `on_tick(self, owner, dt)` 每一幀呼叫；官方範例「Stat Tracker」用 `dt` 累加做每秒一次的節流 [MCP recipes]。

### `inzoi.*` 命名空間 [MCP]
| 命名空間 | 成員 |
|---|---|
| `inzoi.cli` | `execute` |
| `inzoi.entity` | `describe`、`exists`、`type`、`is_object`、`is_character`、`is_npc`、`is_player`、`is_possessed`、`is_household`、`is_site`、`is_vehicle`、`is_food`、`is_book`、`is_carriable` |
| `inzoi.event` | `on`、`off` |
| `inzoi.message` | `send`、`send_to_client`、`send_to_sim` |
| `inzoi.getB2Manager`、`inzoi.getB2Subsystem` | 取得管理器／子系統實例，例如 `getB2Manager("FB2EntityManager")` |

- [檔案] Lua 的 CLI 呼叫形式：`local ok, msg, data = inzoi.cli.execute("id key=value ...")`——**一個字串**進去，
  三個值出來，`data` 是 **JSON 字串或 nil**。（UI 模組的 JS 形式不同，見第 3 節。）
- [檔案] C++ 類別方法不在目錄裡，要用 `modkit_validate_lua_script`（BlueLuaKit 靜態分析）檢查。
- 對我們的影響：`data` 是 JSON 字串，而 CLAUDE.md 規則 10 說官方 Lua 不一定有 JSON 解析器——**要實測 Lua 環境有沒有 json 函式庫**；
  沒有的話，只取少數欄位可以自己寫最小解析，或盡量用不需要回傳資料的指令。

### 遊戲事件（`inzoi.event.on` 用）[檔案 events_catalog.json，26 個]
和寵物模組直接相關的：

| 事件 | scope | 參數 | 用途 |
|---|---|---|---|
| `time.hour_changed` | B2 | `hour` | **P7 計時器**：每遊戲小時一次，需求衰減的時鐘 |
| `time.day_changed` | B2 | `day_of_week` | 每日結算（成長、老化、疏於照顧判定） |
| `simulation.pause_changed` | B2 | `is_paused`、`reason` | 暫停時不扣需求 |
| `interaction.started`／`finished`／`canceled`／`failed` | B2 | `entity_id`、`interaction_bag_id`、`target_entity_id`（＋`reason`） | 偵測 Zoi 對貓做了原版互動 |
| `need.state_changed` | B2 | `entity_id`、`need_id`、`from_state`、`to_state` | Zoi 需求（不是寵物） |
| `zoi.died`、`zoi.born`、`zoi.growth_changed` | B2 | | 飼主死亡時寵物歸屬 |
| `character.overlap_begin`／`end` | B1 | `other_entity_id` | 只有角色，看起來不含物件 |

其餘：`buff.added/removed`、`emotion.changed/level_changed`、`relationship.level_changed`、`season.changed`、
`skill.level_changed`、`time.day_night_changed`、`weather.changed`、`zoi.married/divorced/pregnancy_*`。

### 存資料（P7 第二半）
- `on_savegame`／`on_loadgame` 存在 [MCP]，「任何綁定類型都能用」[檔案]。**但文件沒說資料要存到哪裡**
  （沒有看到 Lua 端的 save/load 儲存 API）。→ 遊戲內要測：`self` 上的欄位、模組層級變數，存檔讀檔後還在不在。
- UI 端有明確的跨存檔機制（第 3 節 `wf.state`）。**如果 Lua 端存不了，備案是讓 UI 端持有存檔資料**，
  Lua 透過訊息讀寫——前提是 Lua 與 UI 之間有通道（見第 4 節的未知）。

## 2. 和貓有關的遊戲資料

### ObjectTemplate 綁定鍵裡的動物範本 [MCP `modkit_list_lua_binding_keys(B2, ObjectTemplate)`，共 1415 個鍵]
- 動物：`DEV_AnimalObjectTemplate`、`DEV_AnimalObjectVoidCatTemplate`、`DEV_E01_AnimalObjectVoidCatTemplate`，
  以及 `...VoidLabrador`、`...VoidFox`、`...VoidRaccoon`、`...VoidRat`、`...VoidSquirrel`、`...VoidDeer`、
  `...VoidCrocodile`、`...VoidSeaTurtle`、`...VoidBabyTurtle`；另有 `DEV_VoidPanda_Template`。
- 貓用品（名稱推測用途，**未驗證**）：`CatPuree01_Template`（貓肉泥？）、`CatToy01_Template`、`CatSandSpray01_Template`、
  `CatLeaf01_Template`、`CatShop01_Template`、`Purrson01_Template`、`CatStatue02_Template`、`Statue_GoldCat01/02_Template`。
- **意義**：城市貓若真的是 `DEV_AnimalObjectVoidCatTemplate` 的物件實例，就能用 `ObjectTemplate` 綁定讓我們的 Lua
  在每隻貓身上收到 `on_begin`／`on_tick`／`on_end`——這是方案 A「辨識並追蹤一隻真的貓」的入口。
  和 UE4SS 時期觀察到的 `BP_AnimalObjectTemplate → B1GameObject` 繼承鏈吻合（推論，未驗證）。
- 注意：用 `modkit_get_row` 在 `Object`、`ObjectTemplate` 資料表查 `DEV_AnimalObjectVoidCatTemplate` 都**查不到**；`DEV_E01_AnimalObjectVoidCatTemplate` 加 `dlc=E01` 也查不到
  （`ObjectTemplate` 表只有 1018 列，鍵清單有 1415 個；差額可能在 DLC 或別的來源）。內容要在遊戲裡用
  `entity.get_object_info` 看。

### 動物的生成方式 [檔案 data_asset_schemas]
- `B1CityEditDataAsset.WorldVATSpawnInfoList`（分類 `Animal`）：「每個世界的 VAT 物件生成資訊，用於動物生成」。
  → 城市動物是 **VAT（頂點動畫貼圖）物件**，由呈現層（B1）的城市編輯資料決定生成，不是角色。
- `B1DataLogDataAsset.AnimalInteractionIdList`：被歸類為動物互動的 ID，預設值開頭是
  `Object_Void_Cat_Dev`、`Object_Karma_AnimalScare`…（截斷）。→ 貓的原版互動 ID 線索，P6 用 `interaction.search` 確認。
- CLI `simulation.set_density` 有 `animal`（0–5）密度；`simulation.get_settings`（Public）回傳 `animal_density`。

## 3. UI 模組（P8）[檔案 ws_uimod.md、templates/ui]

- 一個模組一個 UIMod 工作區，裡面可有多個 app；每個 app 是 `uimod_manifest.json`＋`index.html`＋`window.js`＋`app.js`。
- `index.html` 必須依序載入 `coui://inzoi/cohtml.js`、`coui://inzoi/mod/inzoi-sdk.js`、`window.js`、`app.js`。
- manifest：`display.input_policy` 有 `overlay`（可點、遊戲繼續）／`modal`（可點、遊戲暫停）／`passthrough`（不可點）。
  有按鈕就用 `overlay`。
- 觸發：`always_on`、`keybind`（`key`＋`modifiers`）、`command`、`game_mode`（`gameplay` 等）、`game_event`、`ui_event`、
  **`interaction_menu`**（`target`、`label_key`；文件只示範 `target: "character"`）。
- JS SDK（`window.inzoi`）：`cli.execute(id, params)` 回 Promise；`data.query/subscribe/onPush`；`event.fire`；
  `trigger.onActivated`；`view.show/hide/hover/resize`；`debug.log`；`types`。
- **存資料**：
  - `wf.state`：範本註解說「跨遊戲存讀檔自動保存」——存檔時 C++ 呼叫 `__uimod_collectSaveState()`，
    把內容序列化進**存檔檔案的 UIMD 區塊**；讀檔時 `__uimod_deliverLoadedState()` 還原並呼叫 `window._onStateLoaded(state)`。
    → **每個存檔各自一份**，正是寵物資料需要的。
  - `uimod.cfg_save`／`uimod.cfg_load`（Public）：寫在模組自己的 cfg 資料夾——**全域**，不分存檔。適合設定頁，不適合寵物資料。
- P8 要用的 Public 指令：`toast.show`（`message`、`lifetime?`、`immediate?`；純顯示、不存檔）。

## 4. P9 與官方路線的未知（遊戲內要測）

| # | 問題 | 怎麼測 |
|---|---|---|
| U1 | 城市貓是不是 `DEV_AnimalObjectVoidCatTemplate` 的實例？實體 ID 穩不穩定？ | `entity.scan_objects` → `entity.get_object_info` |
| U2 | `ObjectTemplate` 綁定到貓範本，`on_begin` 會不會對每隻貓觸發？ | 最小 Lua 模組＋`print` |
| U3 | 貓有哪些原版互動？`Object_Void_Cat_Dev` 是什麼？ | `interaction.list_available target_entity_id=<貓>`、`interaction.search keyword=cat` |
| U4 | `movement.summon`／`teleport_to`（Public）對物件有沒有用？（說明寫「character」） | 對貓的 entity_id 呼叫 |
| U5 | Lua 的 `on_savegame`／`on_loadgame` 能不能保存資料？ | 存一個值、存檔、讀檔 |
| U6 | Lua 有沒有 JSON 函式庫？ | `print(type(json))`、`pcall(require, "json")` |
| U7 | Lua ↔ UI 有沒有通道？（`inzoi.message.send_to_client` 到得了 UI 嗎？UI 的 `inzoi.data` 讀得到 Lua 嗎？） | 雙向送一則訊息 |
| U8 | `interaction_menu` 觸發能不能用在物件（貓）上？ | manifest 寫 `target: "object"` 試；`modkit_write_uimod_manifest` 驗證會先擋不合法的值 |
| U9 | `UserCheat`／`ScriptCheat` 指令在正式版能不能用？（`ambition.complete` 說明寫 shipping 版無效） | 挑一個無害的 UserCheat 指令試 |

## 5. 遊戲內結果（2026-10-20，遊戲 `20261019.16318.W`）

| # | 結果 | 依據 |
|---|---|---|
| U1 | ✅ 是。綁定觸發時 `GetObjectId()` 為 `Level_Void_Cat` 或 `DEV_Void_Cat`；實體 ID 跨載入不變 | 探勘模組 cat 日誌，兩次載入比對 |
| U2 | ✅ 會，江南 49 隻，每隻各自的 `self` | 同上 |
| U3 | ✅ `Object_Void_Cat_Tickle`、`Object_Void_Cat_Dev`（可用）；搜尋另有 `_Sad_Lv1–3`、`Perspective_Void_Cat_Dev`、`Ghost_Object_Void_Cat_Dev` | `interaction.list_available`、`interaction.search` |
| U4 | 未測；B2 有 `FB2Actor:SetLocationOnlySimul`（說明：只動 B2，要通知 B1 用 `Teleport()`，但 `Teleport` 沒匯出） | luals-defs |
| U5 | ❌ `on_savegame`／`on_loadgame` 沒觸發（Main、Manager=Time、ObjectTemplate；ModKit 預覽模式） | 2 次存檔、3 次載入 |
| U6 | ❌ 沒有 json（B1、B2 都是 Lua 5.4） | `rawget(_G, "json")` |
| U7 | ❌（目前）：`send_to_client(entity_id, ...)` 不報錯，但 B1 Main 與 B1 Zoi 綁定都收不到；B1 訂閱 B2 事件也收不到。B1／B2 互相不能呼叫對方的 CLI 指令 | env／b1／b1zoi 日誌 |
| U8 | 未測 | |
| U9 | 主選單 ❌（CheatManager not available）；遊戲內 ✅（`environment.time_skip`、`interaction.execute`、`game.goto_lobby`） | 第四輪 |

官方 LuaLS 定義檔在遊戲目錄 `BlueClient/Content/Data/Lua/luals-defs/`（`sandbox.lua` 寫明：擋 `dofile`／`loadfile`／`loadstring`，
擋 `io`／`os`／`debug`／`File` 的成員存取，擋 `http`／`socket`／`ssl` 模組）。遊戲 MCP 另有 `lua_api_lookup` 可查型別。
