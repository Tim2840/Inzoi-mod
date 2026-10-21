# 官方 ModKit 執行期架構（ADR 0007、0008 的實作設計）

> 依據：`docs/phase0-results.md` 的遊戲內實測（遊戲 `20261019.16318.W`）。標「未驗證」的呼叫只在定義檔（`luals-defs`）看過，還沒在遊戲裡跑過。

## 1. 三個執行環境

| 環境 | 跑什麼 | 能做 | 不能做 |
|---|---|---|---|
| **B2**（模擬執行緒 Lua） | 寵物引擎 `pawhome.*`＋`adapters/inzoi.lua` | 讀時間、家戶、金錢、貓實體；訂閱 `time.hour_changed`、`interaction.*`；把互動排進 Zoi 佇列 | 呼叫 B1 指令（`toast.show`、`uimod.cfg_*`）；存檔 |
| **B1**（遊戲執行緒 Lua） | 中繼 `Relay.lua`（綁 `Zoi/ResidenceFamily`） | 收 B2 訊息、`toast.show`、`uimod.cfg_save/load` | 呼叫 B2 指令、收 B2 事件 |
| **UI**（Overlay，JS） | 面板 `mod/ui/*`＋`bridge.js` | 顯示、按鈕、`wf.state`（寫進存檔）、`uimod.cfg_*`、B1／B2 Public 指令 | 收遊戲事件（`game_event` 觸發實測沒送到） |

## 2. 資料通道（全部實測過）

```
B2 引擎 ──send_to_client(數字實體ID, "pawhome:<頻道>", 內容)──▶ B1 Relay（同一 Zoi 的綁定）
B1 Relay ──uimod.cfg_save(section="bridge", key="to_ui")──▶ 檔案 ◀──uimod.cfg_load 輪詢── UI
UI ──uimod.cfg_save(section="bridge", key="to_sim")──▶ 檔案 ◀──cfg_load 輪詢── B1 Relay ──send_to_sim──▶ B2
UI ──wf.state──▶ 遊戲存檔（UIMD 區塊）
```

- 訊息頻道一律 `pawhome:` 開頭；同一實體上其他模組的訊息也會送進來，**只處理自己的頻道**。
- 內容一律是字串（實測數字會被轉成字串）。大內容分段：`<序號>/<總數>|<片段>`，接收端組回來（訊息長度上限未知，保守切 900 字元）。
- cfg 檔是**全域**的（不分存檔），只當郵筒用；每封信帶 `session`（B2 啟動時產生），收件端丟掉不是本 session 的信。

## 3. 存檔（沿用 `Api.slotId()` 的暫停機制）

1. 讀檔後 B2 引擎啟動，adapter 的 `slotId()` 先回 **nil** → 引擎暫停，不讀不寫。
2. B2 送 `pawhome:hello <session>`；UI 收到後把 `wf.state.pawhome`（序列化字串）回傳 `pawhome:state`。
3. adapter 收到完整內容 → 放進快取、`slotId()` 回傳 session → 引擎讀檔、開始運作。新存檔（UI 沒資料）回傳空字串。
4. `saveSet` 更新快取並送 `pawhome:save`；UI 寫進 `wf.state.pawhome`，下次遊戲存檔時一起存。
5. UI 沒回應（UI 模組被停用）時引擎維持暫停，不會產生沒存檔的假狀態。
6. **存檔外備份**：存檔時沒掛 UI 模組，`wf.state` 的寵物資料會消失（2026-10-21 實際發生）。B2 每 30 秒最多一次把資料連同家戶 ID 送給 B1（`pawhome:backup`），B1 以 `uimod.cfg_save`（區段 `backup`、鍵 `h<家戶ID>`）存在存檔之外；沒有寵物的資料不送，避免空白新開局蓋掉好的備份。讀到沒有寵物資料的存檔時 B2 問 B1（`pawhome:backup_get` → `pawhome:backup_data`），面板提示，玩家按下才還原（RPC `restoreBackup`）。✅ 已驗證（2026-10-21）：領養 → 20 秒內寫入備份 → 不存檔重讀 → 提示「第 1029 天：Mochi」→ 還原成功。

## 4. adapter 函式對照（2026-10-21 遊戲 `20261019.16318.W` 實測）

| 函式 | 實作 | 狀態 |
|---|---|---|
| `now()` | `FB2TimeManager:GetDay()*1440 + GetHour()*60 + GetMinute()` | ✅ 已驗證 |
| `slotId` / `saveGet` / `saveSet` | 第 3 節（握手、`wf.state`） | ✅ 已驗證，含存檔→讀檔 |
| `notify` | `pawhome:toast` → B1 `toast.show` | ✅（toast 本身已驗證） |
| `householdMembers` / 家戶 | `household.get_members`（回 `household_id`、`members[].entity_id`） | ✅ 已驗證 |
| `funds` | 家戶貨幣元件 `GetCurrency(owner)`（owner＝家戶的 `FB1EntityId`；out 參數不傳） | ✅ 已驗證（₼256） |
| `charge` | `SetCurrency(FB2City.GetCurrencyId(), 餘額-金額, ExpenseDefault, owner, false, owner)`；以前後餘額確認 | ✅ 已驗證（256→106，存檔後仍是 106）。`TrySubtractCurrency` 回 true 但不扣錢 |
| `spawnPet` | 待定代號；Zoi 在家時以 `FB2InteractionComponent:AddInteractionQueueByParam(…, User, false, false, "PawHome", true, false)` 排入 `PawHome_WelcomeCat`（結果 37＝Success）；互動結束後以 `GetAllEntities(GameObject)` 找家裡的新 `DEV_Void_Cat` 綁定 | ✅ 已驗證，綁定跨存檔保留、讀檔後不重複召喚 |
| `entityExists` | 綁定或家裡搜尋得知的貓 | ✅ |
| `despawnPet` | 排入 `PawHome_SendAway`（結束腳本 `DespawnGameObject Target`） | ✅ 互動已驗證：2026-10-21 排入後約 10 秒貓實體消失。Lua 排入佇列的路徑與召喚共用（已驗證） |
| `listStrays` | 城市貓綁定＋`interaction.finished` | 綁定與事件已驗證 |
| `takeCare` | 原版「給零食」（`Object_Void_Cat_Dev`→feed）、「玩」（`Object_Void_Cat_Tickle`→play）結束時記錄，引擎立刻以面板按鈕相同的規則套用 | ✅ 已驗證（2026-10-21）：給零食→`not_hungry`（照規則拒絕），玩→寵物 1 成功 |
| `bringStray` | 不支援（`caps.moveStray = false`） | 實測做不到 |
| `addBuff` | 暫不支援 | — |
| `playAnimation`（`caps.animate`） | 面板照顧動作 → `data/animations.lua` 的 VAT 段落 → `send_to_client(貓實體, "pawhome:anim", "段落|秒數|回到的坐姿")` → B1 貓綁定（`PawHomeBind/Cat.lua` → `adapters/inzoi_cat_b1.lua`）以 `UB1AnimToTexComponent:PlayAnimSequence` 播放，一次性動畫播完回到心情的坐姿待機。原版互動（玩／給零食）給的照顧**不再另播**（遊戲已經播過） | ✅ 已驗證（2026-10-21，朴恩珠存檔、不存檔）：面板「抱抱」→ `ANIM_VoidCat_Being_Patted`，12 秒後回 `ANIM_VoidCat_Sit_Idle_01`（B1 日誌） |
| 心情待機（`petLook`＋閒置計時） | 引擎每次 tick 與讀檔後呼叫 `Api.petLook(貓, {mood, stage, scale})`；adapter 約每 20 遊戲分鐘（±10）依心情送坐姿待機，偶爾（25%）送一次性反應（開心→歡迎／送禮、生氣→哈氣、緊張／難過／生病→受驚）。遊戲互動進行中（`interaction.started` 到結束事件）不送；B1 另外在偵測到不是自己播的動畫後 15 秒內不播、自己的一次性動畫不被打斷 | ✅ 坐姿待機已驗證；「玩」結束後恢復待機、「給零食」期間 B1 擋下（`skipped … (game)`）已驗證。一次性反應走同一路徑，未在畫面上逐一看過 |
| 幼貓尺寸（`caps.scale`） | `data/stages.lua` 的 `scale`（幼貓 0.6、成貓 1.0、老貓 0.95）→ `"pawhome:scale"` → B1 `SetActorScale3D`。B1 在 `on_begin`、其後 1.5 秒與 5 秒各套一次（初期 actor 參考會失效）；B2 隨閒置計時每約 20 遊戲分鐘重送一次（召喚當下 B1 actor 可能還沒好，訊息會遺失） | ✅ 已驗證：召喚的幼貓 109980 縮成 0.6（B1 日誌 `size 0.6`，截圖），Zoi「給零食」時蹲在幼貓前、位置自然。讀檔／actor 重生後的 `cat_begin` 重套路徑未在遊戲裡跑過（重送計時會補上） |

### 實測得到的限制
- 遊戲的實體查詢只收 `FB1EntityId`，不收數字，也沒有建構方式：一律從遊戲物件取得（`GetEntityId()`、`GetHouseholdEntityId()`、`GetObjectKey()`），找不到時以 `GetAllEntities(類型)` 搜尋（TArray，`Num()`，索引從 1）。
- 綁定只涵蓋載入時就存在的實體：熱掛載不會補 `on_begin`；執行中召喚的貓也不會觸發 `ObjectTemplate` 綁定。
- 開發時 `luamod.mount` 要在讀檔前掛上；主選單掛載後 B2 會在模擬開始時拿到腳本。
- 遊戲的靜態分析會**拒絕載入有錯誤的檔案**（例如提到 `loadstring`），也會把名稱像 `Inzoi` 的區域變數當成 `INZOI` 命名空間。
- 遊戲瀏覽器沒有 `replaceChildren`／`append`／`Array.flat`，不吃 CSS 變數，字型沒有 emoji。

## 5. 遊戲資料（每次載入由 UI 以 Public 的 `data.patch` 加入，不寫進存檔）

- `Script`：`PawHome_SpawnCat`（`SpawnGameObjectToFront DEV_Void_Cat`）、`PawHome_DespawnTarget`（`DespawnGameObject Target`）。
- `Interaction`／`InteractionBag`：`PawHome_WelcomeCat`（沿用原版 `Self_Pose_CatHeart` 動作）、`PawHome_SendAway`（沿用 `Object_Void_Cat_Tickle` 動作）。只填必要欄位，其他用預設值（已驗證可行）。不加進任何選單，只由模組排進佇列。
- 待做：`PawHome_Adopt`（城市貓選單的領養入口）。
- `ObjectSelectionSet_Dev[Id=DEV_Void_Cat]…InteractionBagList` 加 `PawHome_Adopt`（Witchcraft 已證明可行）。
- 照顧動作直接沿用原版 `Object_Void_Cat_Dev`（餵零食）、`Object_Void_Cat_Tickle`（玩），由 `interaction.finished` 事件計入（已驗證）。
- 選單文字：資料補丁加的互動只能引用遊戲字串表的文字 ID，新文字要用 ModKit 語言工作區打包；所以選單入口優先研究 UI 模組的 `interaction_menu` 觸發（自訂標籤），見 `docs/research/phone-pc-ui.md`。
- 讀檔後遊戲可能停在暫停（ESC 選單）狀態；B2 要等時間流動才開始握手。

## 6. 測試策略

- 離線：B2 adapter 與 B1 Relay 都以「平台介面」注入遊戲呼叫，測試用假平台跑完整通道（含分段、session、暫停）。
- 遊戲內：`tools/game_mcp.py` 自動跑「載入 → 等待握手 → 召喚 → 照顧 → 存檔 → 讀檔」，日誌經 `uimod.cfg_save`。
