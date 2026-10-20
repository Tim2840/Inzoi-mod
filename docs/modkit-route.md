# 官方 ModKit 路線：官方文件讀到的事實與第 0 階段準備

> 決定：ADR 0005（2026-10-20，PO）。本文件只記錄**從官方文件實際讀到的**內容（2026-10-20 讀取），
> 以及它們對應到 `docs/phase0-probe.md` 的哪一題。文件只列名稱和一行描述，**沒有函式簽章**，
> 所以下面每一項都只代表「有這個型別」，不代表「我們能用它做到某件事」——那要靠第 0 階段在遊戲裡測。

## 1. 安裝

- 來源：Epic Games Store，**免費**。加入資料庫後在 Epic Games Launcher 安裝、啟動。
  （[Install](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/how-to/getting-started/01install)）
- 文件**沒有寫**磁碟空間、記憶體、顯示卡、作業系統需求，也沒寫需要哪個 inZOI 版本。
- 需要 PO 登入 Epic 帳號（agent 不能代為輸入帳密）。

## 2. MCP 伺服器（Claude Code 直接連遊戲與 ModKit）

官方首頁（[mod-docs.playinzoi.com](https://mod-docs.playinzoi.com/)）：

| 伺服器 | 位址 | 用途 | 前提 |
|---|---|---|---|
| `inzoi-game` | `http://localhost:11212/mcp` | 讀取並控制執行中的遊戲 | 遊戲要開著 |
| `inzoi-modkit` | `http://localhost:11213/mcp` | 建立與編輯模組專案 | ModKit 編輯器要開著；工具列有一鍵註冊 13 個助手的 MCP 按鈕 |

- 11212 被占用時：從 Steam 啟動參數加 `-climcpport=<port>`。

## 3. Lua API（[總覽](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/)）

- 型別分三個環境：**B2（模擬）804**、B1（呈現：UI、特效、鏡頭）5,642、Common/Engine 73，共 6,519。
- **B2 是主要的模組介面，Lua 模組跑在 B2 執行緒上。**
- 模式是**覆寫**：
  - 動作有時機鉤子（`OnPlay` / `OnFinish` / `OnPaused` / `OnCanceled` / `OnTick`），例如 `FB2Action_Eat.Override_OnPlay`。
  - 規則腳本的 `Condition__` / `Execute__` 靜態函式可用 `Override_` 改寫。
- B2 分類：Systems/Managers 66、Components 65、Actions 149、Scripts 81、Structs 351、Classes 3、Enums 89。

### 和寵物相關、值得在第 0 階段查的型別（名稱與一行描述，**都未實測**）

| 對應題目 | 型別 | 官方描述 |
|---|---|---|
| P4 生成 | `FB2SpawnerManager` | 管理角色／物件生成 |
| P4 生成 | `FB2PopulationSystem` | 人群生成與維持 |
| P2 找實體 | `FB2EntityManager` | 實體（角色／物件）池 |
| P4 生成 | `FB2Script_Spawner` | Spawner 領域的規則腳本（可覆寫） |
| P7 時間 | `FB2TimeManager`、`FB2TimeTaskManager`、`FB2Script_Time` | 遊戲內時間、排程時間任務 |
| 領養入口 | `FB2AdoptionManager` | 管理領養流程（**沒說領養什麼**） |
| 行為 | `FB2AutonomyComponent`、`FB2InstinctComponent`、`FB2Script_Behavior` | 自主行為、本能 |
| 動物？ | `FB2HowlingComponent`、`FB2Script_Howling` | 描述提到吠叫；**未確認和動物有關** |
| P6 互動 | `FB2InteractionComponent`、`FB2Script_Interaction`、`FB2Action_PlayAnim`、`FB2Action_PlayVATAnim` | 互動佇列；播放動畫；播放頂點動畫貼圖 |
| 需求 | `FB2StatComponent`（需求／能力）、`FB2EmotionComponent`、`FB2BuffComponent` | |
| 金錢、家戶 | `FB2CurrencyComponent`、`FB2Script_Currency`、`FB2HouseholdManager` | |
| 通知 | `FB2Action_PopupMessage`、`FB2Script_UITimeAlert`、`FB2Script_SpeechBubble` | |
| 移動 | `FB2EntityMoveComponent`、`FB2CharacterMovementComponent`、`FB2Action_WalkTo*`、`FB2Action_TeleportTo` | |

**沒有找到的：**149 個動作裡沒有任何動物、寵物、餵食動物、撫摸、領養寵物的動作；唯一明確的生成動作是
`FB2Action_SpawnVehicle*`。81 個規則腳本裡也沒有以動物或寵物命名的。

## 4. CLI 指令目錄（[CLI](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/cli/)）

- 頁面列出 **407 個指令、約 70 個類別**（例如 `household_biz` 38、`appearance` 31、`building` 27、`object` 1、`zoi` 2、`zoi_group` 9、`household` 6、`currency` 3）。
- **沒有** animal、pet、cat 或 spawn 類別。
- 頁面**沒有定義「Public／非 Public」**。`docs/research-report.md` 寫的「318 個、115 個 Public」來自搜尋摘要，和官方頁面目前的數字對不上，**以實測為準**。

## 5. ModKit 文件裡有的模組類型（[目錄](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/)）

- 角色、建造物件、音效、**互動**（[互動物件規格](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/project/build/02-interaction)、DataAsset、資料編輯器）、**UI 模組**（Overlay UI、[腳本](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/project/uimod/04-scripting)）。
- 發佈：[本機匯出](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/export/local)、[CurseForge](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/export/curseforge)；錯誤碼：[Mod Error Codes](https://mod-docs.playinzoi.com/docs/modkit-docs/faq/mod-errors)。
- 目錄裡**沒有專門的「Lua 腳本模組」教學頁**，Lua 模組怎麼建立要靠 `inzoi-modkit` MCP 或 ModKit 本身確認（P7）。

## 6. UE4SS 時期留下、對官方路線仍有用的線索

（v0.11.0、2026-10-20，透過 UE4SS 觀察，詳見 `docs/t2-m1-3a-results` 分支的結果檔）

- 城市裡有兩種貓：`BP_Void_Cat_C`（`B1GameObject`，靜態網格＋烘焙貼圖動畫，有互動元件）、`Void_Cat1_C`（Character，掛著空的標準 AIController：沒有行為樹、黑板、感知；觀察 60 秒完全沒動）。
- `B1` 開頭是**呈現層**。貓真正的行為若存在，比較可能在 **B2 模擬層**——正是官方 Lua 的所在。（推論，未驗證）
- `BP_Void_Cat_C` 用烘焙貼圖動畫，而 B2 有 `FB2Action_PlayVATAnim`：動物的動作也許由模擬層用這個動作驅動。（推論，未驗證）

## 7. 第 0 階段的順序（建議）

1. **不需安裝**：繼續讀 B2 的 Systems／Components 單頁（`FB2SpawnerManager`、`FB2AdoptionManager`、`FB2HowlingComponent` 等）看有沒有函式說明。
2. PO 從 Epic 安裝 ModKit（大小待查）。
3. 用 `/mcp` 連上 `inzoi-game`、`inzoi-modkit`，照 `docs/phase0-probe.md` 做 P1 → P7 → P8（先確認做得到的底線：計時、存資料、UI 按鈕），再做 P2–P6、P9（真寵物的可能性）。
4. 結果寫 `docs/phase0-results.md`，決定方案 A／B／C。

## 8. 單頁細節（第 0 階段第 1 步，持續補充）

### `FB2SpawnerManager`（[頁面](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/systems/fb2spawnermanager)，2026-10-20 讀取）

- 載入方式：`require('Systems.B2SpawnerManager')`；繼承 `FB2ManagerBase`。
- 屬性：`CharacterSpawnerGroups`、`GatherableObjectSpawnedTime`、`OldSpawnerMap`、`SpawnersByType`。
- 17 個函式，**會生成東西的只有** `SpawnGatherableObject`、`SpawnGatherableObjectByTerritoryId`（採集物）與 `SpawnCalendarEventObject`（行事曆活動物件）。
  角色只有讀取用的 `GetCharacterSpawnerGroup`，**沒有生成角色的函式**；頁面**沒有提到動物**。
- 10 個覆寫鉤子（例如 `Override_SpawnGatherableObject`、`Override_OnDayChanged`、`Override_RegisterSpawner`）。
- 結論：這個管理器**不是**「生成一隻貓」的現成入口；P4 仍要在遊戲裡查其他路徑（`FB2EntityManager`、`FB2PopulationSystem`、互動物件、資料模組）。

### ModKit 需求（Epic 商店頁，經搜尋摘要轉述，**未直接讀取**）

- 最低：RAM 12 GB、儲存空間 40 GB、RTX 2060 / RX 5600 XT（6 GB VRAM）；建議：RAM 16 GB、60 GB、RTX 3070 / RX 6800 XT。
- [Epic 商店頁](https://store.epicgames.com/en-US/p/inzoi-modkit)
- **實際安裝（2026-10-20，讀 Epic 安裝紀錄）**：版本 `20261011.16078.W.MODKIT.EGS`，位置 `C:\Games\inZOIModKit`，大小 **93.4 GB**（遠大於上面轉述的 40–60 GB，以實際為準）。

### 第 1 步追加（2026-10-20 讀取）

| 型別 | 讀到的重點 | 對寵物的意義 |
|---|---|---|
| [`FB2AdoptionManager`](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/systems/fb2adoptionmanager) | 「管理領養流程」；屬性與函式全是角色型別（`FB1CharacterAttribute`、`FB2CharacterGenerateParam`、`EB1GrowthStep`），分 `RequestAdoption_Medical` / `RequestAdoption_Physical` | 看起來是**領養小孩**，不是寵物（依型別名稱推論，頁面沒明講） |
| [`FB2HowlingComponent`](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/components/fb2howlingcomponent) | 「管理嚎叫（吠叫等）」；`OnReceiveHowling(HowlingId, SenderId)`、失敗冷卻 | 可能和動物聲音有關，物種不明 |
| [`FB2EntityManager`](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/systems/fb2entitymanager) | 75 個函式：`GetAllEntities(EB2EntityType)`、`FindCharacter`、`FindGameObject`、`Register`、`Unregister`、`DestroyObject`、`RequestCharacterStateChange`… | 可以找、列舉、註冊、移除實體；**沒提到動物** |
| [`FB2TimeTaskManager`](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/systems/fb2timetaskmanager) | 只有查詢、移除、清空排程任務；**沒有建立任務的函式** | P7「每小時跑一次」要另找方法（例如覆寫既有的每日／每時規則） |
| [`EB2EntityType`](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/enums/eb2entitytype) | `City`、`Site`、`Character`、`GameObject`、`HowlingEmitter`、`Household`、`HouseholdBiz`、`Career`、`Vehicle`、`CoopScheduler`、`Spawner`、`Inventory` | **沒有「動物」實體類型** |

**推論（未驗證）**：UE4SS 觀察到城市貓 `BP_Void_Cat_C` 的繼承鏈是 `BP_AnimalObjectTemplate → B1GameObject`，
而模擬層沒有動物實體類型，所以遊戲裡的貓很可能是**會動的「遊戲物件」（GameObject）**。若成立，官方路線的寵物
可以考慮做成 **ModKit 互動物件**（互動物件規格＋DataAsset）：照顧動作是物件的互動，效果用 Lua 覆寫接到引擎。
第 0 階段要確認：P2 時用 `FB2EntityManager:GetAllEntities(GameObject)` 找城市貓、看牠的元件與互動；
P9 時看能不能以 `BP_AnimalObjectTemplate` 這類範本做新的物件。
