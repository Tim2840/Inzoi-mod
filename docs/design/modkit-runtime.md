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

## 4. adapter 函式對照

| 函式 | 實作 | 狀態 |
|---|---|---|
| `now()` | `FB2TimeManager:GetDay()*1440 + GetHour()*60 + GetMinute()` | 未驗證（方法在定義檔） |
| `slotId` / `saveGet` / `saveSet` | 第 3 節 | 通道已驗證，協定待實作 |
| `subscribe("slot_changed")` | 收到 `pawhome:state` 時觸發 | — |
| `notify` | `pawhome:toast` → B1 `toast.show` | `toast.show` 已驗證 |
| `householdMembers` | `FB2Household:GetHouseholdMembers()` | 未驗證 |
| `funds` / `charge` | `FB2CurrencyComponent:GetCurrencyAmount` / `TrySubtractCurrency` | 未驗證 |
| `spawnPet` | 把自訂互動 `PawHome_WelcomeCat` 排進 Zoi 佇列（`FB2InteractionComponent:AddInteractionQueueByParam`）；互動結束腳本 `SpawnGameObjectToFront S1=DEV_Void_Cat`；新貓由 `ObjectTemplate` 綁定的 `on_begin` 回報實體 ID。**非同步**：回傳 nil，下一個小時引擎再問 `entityExists` | 生成已驗證；排佇列未驗證 |
| `entityExists` | 貓綁定的 `on_begin`／`on_end` 維護的集合 | 綁定已驗證 |
| `despawnPet` | 排入互動 `PawHome_SendAway`，結束腳本 `DespawnGameObject BaseObject=Target` | 移除已驗證；排佇列未驗證 |
| `listStrays` | 城市貓綁定記錄的實體 ID 與座標 | 已驗證 |
| `bringStray` | 不支援（`caps.moveStray = false`） | 實測做不到 |
| `addBuff` / `playAnimation` | 暫不支援 | — |

## 5. 資料補丁（隨模組出貨，`non_ufs/JsonPatch`，需 ModKit 資料工作區）

- `Script`：`PawHome_SpawnCat`（`SpawnGameObjectToFront DEV_Void_Cat`）、`PawHome_DespawnTarget`（`DespawnGameObject Target`）。
- `Interaction`／`InteractionBag`／`Action_Interaction`：`PawHome_WelcomeCat`（對自己）、`PawHome_SendAway`（對貓）、`PawHome_Adopt`（對城市貓）。
- `ObjectSelectionSet_Dev[Id=DEV_Void_Cat]…InteractionBagList` 加 `PawHome_Adopt`（Witchcraft 已證明可行）。
- 照顧動作直接沿用原版 `Object_Void_Cat_Dev`（餵零食）、`Object_Void_Cat_Tickle`（玩），由 `interaction.finished` 事件計入。

## 6. 測試策略

- 離線：B2 adapter 與 B1 Relay 都以「平台介面」注入遊戲呼叫，測試用假平台跑完整通道（含分段、session、暫停）。
- 遊戲內：`tools/game_mcp.py` 自動跑「載入 → 等待握手 → 召喚 → 照顧 → 存檔 → 讀檔」，日誌經 `uimod.cfg_save`。
