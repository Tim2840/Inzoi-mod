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
| P3 移動或跟隨 | 未知 | 未測 | B2 有 `FB2Actor:SetLocationOnlySimul`（只動模擬層，不通知 B1） | 貓在模擬層 3 分鐘內座標完全不動 |
| P4 生成貓 | ❌ 文件層面沒路 | 未測 | — | |
| P5 存檔後還在 | — | 部分：城市貓的實體 ID 跨載入穩定（不是我們生成的貓） | | |
| P6 觸發互動或動作 | 部分 | ✅ `interaction.execute interaction_bag_id=Object_Void_Cat_Dev target_entity_id=89129`：Zoi 走到那隻橘貓旁播放餵零食（截圖確認）。`list_available` 回傳 `Object_Void_Cat_Tickle`（遊ぶ）、`Object_Void_Cat_Dev`（おやつをあげる）；共 7 個貓互動 | `interaction.execute`（UserCheat，遊戲內可用）、`interaction.list_available`（Public） | B2 的 `interaction.started/finished` 事件帶 Zoi ID、互動 ID、貓的實體 ID；NPC 對貓的互動也收得到 |
| P7 計時器和存資料 | 計時 ✅；存資料不明 | 計時 ✅：B1 `on_tick` 心跳＋`environment.get_time` 看到 11→12 點；B2 `on_tick` 也跑。存資料 ✅（UI）：`wf.state` 存檔→回主選單→讀檔後取回 `{"pet_name":"咪咪","counter":2}`。❌（Lua）：`on_savegame`／`on_loadgame` 在 Main、Time 管理器、貓綁定都沒觸發（2 次存檔、3 次載入） | `wf.state`、`on_tick`、`inzoi.event.on` | B2 `time.hour_changed` ✅（`{hour=13}`；`time_skip` 跳 2 小時只觸發一次） |
| P8 UI 呼叫指令 | ✅ 文件完整 | ✅ overlay 視窗顯示在遊戲內；按鈕 → `toast.show` 跳出通知（PO 目視＋`ui.find` 讀到） | `toast.show` | 預設字型**不支援 emoji**（🐱 顯示成方框） |
| P9 加入互動選單 | 部分 | 未測 | `interaction_menu` | |
| P10 狗 | 有範本 | 未測 | | |

## 遊戲內學到的架構限制（影響設計）

1. **B1／B2 嚴格分執行緒**：B2 Lua 呼叫 B1 指令回「is B1-only… Cannot call from sim thread Lua」；B1 Lua 呼叫 B2 指令回「is B2-only… Cannot call from game thread Lua」。
   唯一例外：B2 的 `on_end`（模擬拆除時）呼叫 B1 指令成功過。
2. **B2→B1 訊息**：`inzoi.message.send_to_client` 第一個參數必須是實體 ID；呼叫不報錯，但 B1 的 Main 收不到（`on_lua_message` 沒觸發）。
   B1 的 Zoi 綁定（`*`）也沒收到（第四輪，送給被操控的 Zoi 16597）。**目前沒有找到 B2→B1 的可用通道。**
3. **B1 不能訂閱 B2 事件**：B1 的 `inzoi.event.on("time.hour_changed")` 回 nil、之後也沒收到。
4. **Lua 環境**：B1、B2 都是 Lua 5.4，**沒有 json**；`io` 不存在、`os` 成員被擋；`require` 只能載入白名單模組（BlueLuaKit 規則 `require-not-allowed`）。
5. **Shipping 版不寫遊戲 log**，Lua 的 `print` 看不到。探勘改用 `uimod.cfg_save`（B1）寫檔。
6. **UserCheat 指令在主選單無效**（「CheatManager not available」），**在遊戲內可用**（`environment.time_skip`、`environment.time_speed`、`interaction.execute`、`game.load`、`game.goto_lobby`）。

## 初步判斷（不是結論）

- **方案 C（虛擬寵物）的底線都成立了**：計時（B1／B2 `on_tick`）、每個存檔各自的資料（UI `wf.state`）、UI 按鈕＋Public 指令。
  缺的是「資料放 UI、邏輯放 Lua」時兩邊怎麼溝通（U7），或乾脆把引擎搬到 UI 的 JS。
- **方案 A 比預期接近**：能穩定辨識並追蹤每一隻城市貓（實體 ID 跨載入不變），能列出牠的原版互動。
  還沒解的是「帶回家」（P3）與「把某隻貓標記成我們的」——後者可以在 UI 的 `wf.state` 記實體 ID。
- **方案 B** 仍然看不到路。

## 自動化

遊戲內測試可以不需要 PO 點擊：`tools/game_mcp.py` 直接呼叫遊戲 MCP（`game.load` → `environment.time_skip` →
`interaction.execute` → `game.goto_lobby save=false`），日誌從 `ModKitPreview/PawHome_Probe_DBA66034/probe/*.cfg` 讀。
權限：repo 的 `.claude/settings.local.json`（不進版控）只允許 `py -I tools/game_mcp.py`；會寫入存檔的步驟仍先問 PO。

## 下一步

1. U7：再找 B2→B1／Lua→UI 的通道（`inzoi.data` 的 domain、`ui_event`、B1 綁定在貓物件上）。找不到的話，引擎就放在 UI 的 JS，
   Lua 只做 B2 掛鉤（讀貓、讀事件）——但 B2 的結果要怎麼交給 UI 仍是同一個問題。
2. P3：在測試存檔裡試 `SetLocationOnlySimul` 移動一隻貓（不存檔），看 B1 畫面跟不跟。
3. 依結果決定方案與引擎位置，寫 ADR。
