# 第 0 階段結果（官方 ModKit 路線）

> 題目見 `docs/phase0-probe.md`。分兩欄記：**桌面**＝只靠 ModKit MCP 與 ModKit 附帶文件得知（不碰遊戲）；
> **遊戲內**＝在執行中的遊戲實測。判斷方案只看「遊戲內」欄。
> 細節：`docs/probe/commands.md`（P1 指令表）、`docs/probe/lua-api.md`（API 重點、未知清單 U1–U9、遊戲內紀錄）。

環境：遊戲 `20261019.16318.W`（Steam build 25922370，Shipping，UE 5.6.1）；ModKit `20261011.16078`；
存檔：朴恩珠（江南），測前備份 `C:\Dev\backups\2026-10-20-pre-phase0-ingame`（兩個存檔資料夾，檔案數與大小核對一致）。
測試模組：ModKit 專案 `PawHome_Probe_DBA66034`，以 ModKit 預覽掛載（`Mods/ModKitPreview/`，不動已安裝模組；不進 repo）。
UE4SS 維持停用。PO 另外裝了其他 CurseForge 模組（Alimony、Witchcraft 等），測試時都開著。

| 題目 | 桌面（2026-10-20） | 遊戲內（2026-10-20） | 關鍵指令或 API | 備註 |
|---|---|---|---|---|
| P1 指令清單 | ✅ 406 個指令：Public 146／UserCheat 149／ScriptCheat 111 | ✅ 遊戲 MCP 有 414 個工具（406 個 CLI＋8 個腳手架／查詢工具） | `cli_catalog.json` | |
| P2 找到流浪貓 | 部分 | ✅ `ObjectTemplate` 綁定在每隻城市貓上觸發（江南 49 隻）；物件 ID `Level_Void_Cat`／`DEV_Void_Cat`；實體 ID 與座標**跨兩次載入不變**（如 89129、87988、89289） | Lua `ObjectTemplate` 綁定、`owner:GetObjectKey().Value`、`GetLocation()` | B1 的 `entity.get_object_info` 找不到這些 ID（「GameObject not found」） |
| P3 移動或跟隨 | 未知 | ❌（目前）：B2 `SetLocationOnlySimul` 把貓 89129 的模擬座標 X +300 成功，但畫面上的貓沒動（移動前後截圖同位置）。`movement.teleport_to`／`summon` 只接受角色（「Target character not found」） | `FB2Actor:SetLocationOnlySimul` | 能通知畫面的 `Teleport()` 沒匯出給 Lua。城市貓在模擬層本來就不會自己走 |
| P4 生成貓 | ❌ 文件層面沒路 | ✅（召喚）：照 Witchcraft 的手法，用 `data.patch` 新增腳本列 `SpawnGameObjectToFront S1=DEV_Void_Cat F1=110`，掛在互動的 `FinishScriptIdList` 上；Zoi 做完互動後在她面前生成一隻 `DEV_Void_Cat`（2026-10-21 在家裡生成實體 109727，**截圖看得見**：三花貓坐著、有待機動作，原版「玩／餵零食」互動可用）。建造模式 `building.place_object` 也能放（實體 109298），當時沒在畫面上找到，推測是鏡頭框外，未重測 | `SpawnGameObjectToFront`（資料腳本）、`data.patch`（Public，執行中補丁，讀檔即還原） | 召喚位置是 Zoi 前方固定距離，面對牆時會生到牆外。**跨存檔保留 ✅**（2026-10-21，PO 同意後實測）：召喚實體 109546 → `game.goto_lobby save=true` → 重新載入，同一實體 ID、同一座標仍在，看得見、互動可用，且不需要那段執行中補丁（讀檔後補丁已還原）。**花色會在載入時重新隨機**（存檔前橘色虎斑，讀回變三花） |
| P5 存檔後還在 | — | 部分：城市貓的實體 ID 與座標跨 6 次載入都穩定；**外觀不穩定**——同一個實體 89129 前兩次是橘貓、後來是三花 | | 「我的貓」若綁城市貓的實體 ID，花色可能每次讀檔都變 |
| P6 觸發互動或動作 | 部分 | ✅ `interaction.execute interaction_bag_id=Object_Void_Cat_Dev target_entity_id=89129`：Zoi 走到那隻橘貓旁播放餵零食（截圖確認）。`list_available` 回傳 `Object_Void_Cat_Tickle`（遊ぶ）、`Object_Void_Cat_Dev`（おやつをあげる）；共 7 個貓互動 | `interaction.execute`（UserCheat，遊戲內可用）、`interaction.list_available`（Public） | B2 的 `interaction.started/finished` 事件帶 Zoi ID、互動 ID、貓的實體 ID；NPC 對貓的互動也收得到 |
| P7 計時器和存資料 | 計時 ✅；存資料不明 | 計時 ✅：B1 `on_tick` 心跳＋`environment.get_time` 看到 11→12 點；B2 `on_tick` 也跑。存資料 ✅（UI）：`wf.state` 存檔→回主選單→讀檔後取回 `{"pet_name":"咪咪","counter":2}`。❌（Lua）：`on_savegame`／`on_loadgame` 在 Main、Time 管理器、貓綁定都沒觸發（2 次存檔、3 次載入） | `wf.state`、`on_tick`、`inzoi.event.on` | B2 `time.hour_changed` ✅：自然流動逐時觸發（12→13→14→15）；`time_skip` 跳 2 小時只觸發一次 |
| P8 UI 呼叫指令 | ✅ 文件完整 | ✅ overlay 視窗顯示在遊戲內；按鈕 → `toast.show` 跳出通知（PO 目視＋`ui.find` 讀到） | `toast.show` | 預設字型**不支援 emoji**（🐱 顯示成方框） |
| P9 加入互動選單 | 部分 | 間接 ✅：已發佈的 Witchcraft 模組用資料補丁 `Append ObjectSelectionSet_Dev[Id=DEV_Void_Cat].SelectionSets[StateGroupId=Normal].InteractionBagList` 把自訂互動加進城市貓選單（補丁為明文 JSON）；我們自己尚未實作驗證 | 資料補丁（`non_ufs/JsonPatch`） | 另發現：UI manifest 的 `game_event` 觸發**沒有**把事件送進 `inzoi.trigger.onActivated`（always_on app 與只有 game_event 觸發的 app 都試過） |
| P10 狗 | 有範本 | 未測 | | |

## 遊戲內學到的架構限制（影響設計）

1. **B1／B2 嚴格分執行緒**：B2 Lua 呼叫 B1 指令回「is B1-only… Cannot call from sim thread Lua」；B1 Lua 呼叫 B2 指令回「is B2-only… Cannot call from game thread Lua」。
   唯一例外：B2 的 `on_end`（模擬拆除時）呼叫 B1 指令成功過。
2. **B2↔B1 訊息通了（綁定對綁定）**：從 B2 的 `Zoi` 綁定（key `ResidenceFamily`）呼叫
   `inzoi.message.send_to_client(數字實體ID, 頻道, 內容)`，B1 綁在同一個實體上的 `Zoi` 綁定以 `on_lua_message(self, owner, 頻道, 內容)` 收到；
   反方向 `inzoi.message.send_to_sim(實體ID, 頻道, 內容)` 由 B2 綁定收到。內容會被轉成字串。B2 的 Main 送出的訊息也會到 B1 的 Zoi 綁定，
   但 B1 的 Main 收不到。實體 ID 要傳**數字**（`GetEntityId()` 回的結構送出去對方沒收到）。
   **同一個實體上其他模組的訊息也會送進來**（Alimony 等），頻道名必須加前綴、只處理自己的。
   參考：已發佈的 Alimony 模組（manifest 為明文）正是 B2 `Zoi/ResidenceFamily` → B1 `Zoi/ResidenceFamily` → always_on UI 的結構，
   它的診斷訊息顯示資料存在 UI 的存檔區塊（`native_UIMD_state=restored`）。
3. **B1 不能訂閱 B2 事件**：B1 的 `inzoi.event.on("time.hour_changed")` 回 nil、之後也沒收到。
4. **Lua 環境**：B1、B2 都是 Lua 5.4，**沒有 json**；`io` 不存在、`os` 成員被擋；`require` 只能載入白名單模組（BlueLuaKit 規則 `require-not-allowed`）。
5. **Shipping 版不寫遊戲 log**，Lua 的 `print` 看不到。探勘改用 `uimod.cfg_save`（B1）寫檔。
7. **B1↔UI 用檔案輪詢可行**：B1 Lua 用 `uimod.cfg_save` 寫、UI 每 5 秒用 `uimod.cfg_load` 讀，延遲約 5 秒（第六、七輪實測）。
   UI 也能**直接呼叫 B2 的 Public 指令**（`entity.get_possessed`、`interaction.list_available`）和 B1 指令——UI 是兩層都通的客戶端。
6. **UserCheat 指令在主選單無效**（「CheatManager not available」），**在遊戲內可用**（`environment.time_skip`、`environment.time_speed`、`interaction.execute`、`game.load`、`game.goto_lobby`）。

## 初步判斷（不是結論）

- **完整資料通道已實測打通**：B2 綁定 ⇄（訊息）⇄ B1 綁定 ⇄（cfg 檔輪詢）⇄ UI ⇄（`wf.state`）⇄ 存檔。
  → 寵物引擎可以照原設計放在 Lua（B2 讀遊戲事件與貓），狀態交給 UI 存進存檔，UI 也負責畫面。
  需要 PO 決定的取捨：引擎放 B2 Lua（要做 B2→B1→UI 的同步）或 UI 的 JS（UI 輪詢時間、B2 事件經 B1 轉送）。
- **方案 C（虛擬寵物）**：所有底線實測成立，可以開工。
- **方案 A（真領養城市貓）**：辨識、追蹤、互動、偵測都可行；**帶回家（P3）目前做不到**——模擬層移動不會反映到畫面，
  而且城市貓的外觀每次讀檔可能變。可行的折衷：「在城市認養某一隻貓」（牠留在原地，玩家去探望、餵牠，資料記在我們的引擎），
  家裡的部分用虛擬寵物呈現。
- **方案 B（在家生成）**：**有路了**——資料腳本 `SpawnGameObjectToFront` 召喚 `DEV_Void_Cat`，畫面上看得見、可互動（2026-10-21）。跨存檔保留已確認；**移除也可行**（2026-10-21：在「玩」互動的 `FinishScriptIdList` 掛 `DespawnGameObject BaseObject=Target`，結束後該貓實體消失，不存檔離開）。待確認：花色能否固定、能否讓牠移動。

## 自動化

遊戲內測試可以不需要 PO 點擊：`tools/game_mcp.py` 直接呼叫遊戲 MCP（`game.load` → `environment.time_skip` →
`interaction.execute` → `game.goto_lobby save=false`），日誌從 `ModKitPreview/PawHome_Probe_DBA66034/probe/*.cfg` 讀。
權限：repo 的 `.claude/settings.local.json`（不進版控）只允許 `py -I tools/game_mcp.py`；會寫入存檔的步驟仍先問 PO。

## 下一步

1. ✅ PO 決定：C＋城市認養，引擎留在 Lua（ADR 0007）。
2. 依決定把 `adapters/inzoi.lua` 的 `TODO(Pn)` 換成實測過的呼叫，並設計 UI bridge（`mod/ui/bridge.js` 的遊戲內傳輸）。
3. 尚未測：P9（互動選單入口）、P10（狗）、Lua 存檔鉤子在**正式安裝**（非 ModKit 預覽）時會不會觸發。
