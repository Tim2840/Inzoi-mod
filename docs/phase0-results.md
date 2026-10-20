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
| P6 觸發互動或動作 | 部分 | 部分：`interaction.list_available target=89129` 回傳 `Object_Void_Cat_Tickle`（遊ぶ）、`Object_Void_Cat_Dev`（おやつをあげる）；共 7 個貓互動 | `interaction.list_available`、`interaction.search`（Public） | 觸發要用 `interaction.execute`（UserCheat），未測 |
| P7 計時器和存資料 | 計時 ✅；存資料不明 | 計時 ✅：B1 `on_tick` 心跳＋`environment.get_time` 看到 11→12 點；B2 `on_tick` 也跑。存資料 ✅（UI）：`wf.state` 存檔→回主選單→讀檔後取回 `{"pet_name":"咪咪","counter":2}`。❌（Lua）：`on_savegame`／`on_loadgame` 在 Main、Time 管理器、貓綁定都沒觸發（2 次存檔、3 次載入） | `wf.state`、`on_tick`、`inzoi.event.on` | `time.hour_changed` 有訂閱成功，但紀錄被其他事件擠掉，**未確認** |
| P8 UI 呼叫指令 | ✅ 文件完整 | ✅ overlay 視窗顯示在遊戲內；按鈕 → `toast.show` 跳出通知（PO 目視＋`ui.find` 讀到） | `toast.show` | 預設字型**不支援 emoji**（🐱 顯示成方框） |
| P9 加入互動選單 | 部分 | 未測 | `interaction_menu` | |
| P10 狗 | 有範本 | 未測 | | |

## 遊戲內學到的架構限制（影響設計）

1. **B1／B2 嚴格分執行緒**：B2 Lua 呼叫 B1 指令回「is B1-only… Cannot call from sim thread Lua」；B1 Lua 呼叫 B2 指令回「is B2-only… Cannot call from game thread Lua」。
   唯一例外：B2 的 `on_end`（模擬拆除時）呼叫 B1 指令成功過。
2. **B2→B1 訊息**：`inzoi.message.send_to_client` 第一個參數必須是實體 ID；呼叫不報錯，但 B1 的 Main 收不到（`on_lua_message` 沒觸發）。
   送到綁定在該實體上的 B1 腳本會不會收到：**下一輪測**（已寫好 B1 Zoi 綁定）。
3. **B1 不能訂閱 B2 事件**：B1 的 `inzoi.event.on("time.hour_changed")` 回 nil、之後也沒收到。
4. **Lua 環境**：B1、B2 都是 Lua 5.4，**沒有 json**；`io` 不存在、`os` 成員被擋；`require` 只能載入白名單模組（BlueLuaKit 規則 `require-not-allowed`）。
5. **Shipping 版不寫遊戲 log**，Lua 的 `print` 看不到。探勘改用 `uimod.cfg_save`（B1）寫檔。
6. **UserCheat 指令在主選單無效**（「CheatManager not available」）；遊戲內未測。

## 初步判斷（不是結論）

- **方案 C（虛擬寵物）的底線都成立了**：計時（B1／B2 `on_tick`）、每個存檔各自的資料（UI `wf.state`）、UI 按鈕＋Public 指令。
  缺的是「資料放 UI、邏輯放 Lua」時兩邊怎麼溝通（U7），或乾脆把引擎搬到 UI 的 JS。
- **方案 A 比預期接近**：能穩定辨識並追蹤每一隻城市貓（實體 ID 跨載入不變），能列出牠的原版互動。
  還沒解的是「帶回家」（P3）與「把某隻貓標記成我們的」——後者可以在 UI 的 `wf.state` 記實體 ID。
- **方案 B** 仍然看不到路。

## 下一步

1. 第四輪（腳本已寫好、已掛上預覽）：確認 `time.hour_changed`、B2→B1 Zoi 綁定的訊息、UserCheat 在遊戲內能不能用（`environment.time_skip`、`interaction.execute`）。
2. 自動化：遊戲 MCP 有 `game.load`／`game.goto_lobby`，可以不用 PO 手動點；目前被 Claude Code 自動模式的安全分類器擋下，需要 PO 開權限。
3. 依 U7 結果決定引擎放 Lua 還是 UI，寫 ADR。
