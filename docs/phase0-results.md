# 第 0 階段結果（官方 ModKit 路線）

> 題目見 `docs/phase0-probe.md`。分兩欄記：**桌面**＝只靠 ModKit MCP 與 ModKit 附帶文件得知（不碰遊戲）；
> **遊戲內**＝在執行中的遊戲實測。判斷方案只看「遊戲內」欄。
> 細節：`docs/probe/commands.md`（P1 指令表）、`docs/probe/lua-api.md`（P7／P8／P9 與未知清單 U1–U9）。

環境：ModKit `20261011.16078`；遊戲版本：（遊戲內實測時填）。

| 題目 | 桌面（2026-10-20） | 遊戲內 | 關鍵指令或 API | 備註 |
|---|---|---|---|---|
| P1 指令清單 | ✅ 406 個指令，`access`：Public 146／UserCheat 149／ScriptCheat 111；沒有 pet／animal／cat 類別 | 未測 | `cli_catalog.json` | 目錄有 `access` 欄，「Public」不用再猜 |
| P2 找到流浪貓 | 部分：有動物物件範本 `DEV_AnimalObjectVoidCatTemplate`；動物是 VAT 物件 | 未測 | `entity.scan_objects`、`entity.get_object_info`（Public） | U1 |
| P3 移動或跟隨 | 未知：`movement.summon`／`teleport_to` 是 Public，但說明只講角色 | 未測 | `movement.summon` | U4 |
| P4 生成貓 | ❌ 文件層面沒找到生成物件的 Public 指令（`building.place_object` 是 ScriptCheat、只在建造模式） | 未測 | — | 貓範本在 `Object`／`ObjectTemplate` 表（base、`E01`）都查不到，看起來不能當家具放（其他 DLC 未查） |
| P5 存檔後還在 | — | 未測 | | |
| P6 觸發互動或動作 | 部分：`interaction.list_available`（Public）可列；`interaction.execute` 是 UserCheat | 未測 | 互動 ID 線索 `Object_Void_Cat_Dev` | U3、U9 |
| P7 計時器和存資料 | 計時 ✅（`time.hour_changed` 事件、`on_tick`）；存資料：Lua 有 `on_savegame`／`on_loadgame` 但沒寫存哪裡 | 未測 | `inzoi.event.on` | U5、U6 |
| P8 UI 呼叫指令 | ✅ 文件完整：overlay app＋`inzoi.cli.execute('toast.show', …)`；`wf.state` 存進存檔 | 未測 | `toast.show`、`wf.state` | U7 |
| P9 加入互動選單 | 部分：UI 有 `interaction_menu` 觸發，文件只示範 `target: "character"` | 未測 | `interaction_menu` | U8 |
| P10 狗 | 有 `DEV_AnimalObjectVoidLabradorTemplate` 範本 | 未測 | | |

## 桌面研究的初步判斷（不是結論）

- **方案 C（虛擬寵物）的三個底線在文件上都有入口**：計時（`time.hour_changed`）、存資料（UI 的 `wf.state` 寫進存檔）、
  UI 按鈕＋Public 指令（`toast.show`）。要遊戲內確認 P7、P8。
- **方案 A 多了一條線索**：`ObjectTemplate` 綁定可以掛在貓範本上，讓 Lua 在每隻城市貓身上執行（U1、U2）。
  但要「把貓帶回家」還需要 P3（移動）或 P5（跨地塊、存檔保持），文件層面看不到。
- **方案 B（在家生成）文件層面看不到路**：貓範本在資料表查不到（base、`E01`），也沒有生成動物的 Public 指令。

## 下一步（需要 PO）

1. 在 ModKit 建一個探勘用模組專案（名稱待 PO 決定），放最小的 Lua（U2、U5、U6、U7）與 UI（P8）。只寫在 ModKit 的 Mods 資料夾，**不 commit 進 repo**（規則 11）。
2. PO 開遊戲 → 主選單時先跑不需要存檔的指令；進存檔前**備份兩個存檔資料夾**。
3. 依 U1 → U9 實測，填「遊戲內」欄。
