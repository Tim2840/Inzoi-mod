# CLAUDE.md — 毛孩之家 Paw Home（inZOI 寵物模組）

給在這個 repo 工作的 Claude Code。**新 session 先讀 [`docs/handoff-2026-10-20-modkit.md`](docs/handoff-2026-10-20-modkit.md)**（目前狀態與下一步），再讀 [`docs/modkit-route.md`](docs/modkit-route.md) 與 [`docs/phase0-probe.md`](docs/phase0-probe.md)。使用者說繁體中文，回覆請用繁體中文；程式碼、註解、commit 訊息用英文。

## 專案是什麼

inZOI 目前沒有寵物系統。本模組照 The Sims 4《貓狗成群》的玩法補上養貓：領養、需求、個性、成長老死、親密度、訓練、疏於照顧被動保員帶走（可付費贖回）。第一版只做貓。語系：繁體中文、English。

**路線（ADR 0005，PO 2026-10-20）：官方 ModKit** —— Lua 腳本模組（遊戲模擬層 B2）＋ HTML/JS Overlay UI。UE4SS 路線**暫停**（程式留在 repo，不再開發）。

## 已定案的規格（ADR 0002、0006）

- 每戶預設 **1 隻**，設定頁最多 **4 隻**。
- 會長大、變老、**老死**（設定頁可關閉老化）。
- **4 個需求**：飢餓、精力（睡覺自動回復）、玩樂、貓砂。心情由需求推算；親密度每個 Zoi 對每隻寵物各一個。
- 疏於照顧：軟性懲罰 → 動保員警告 → 帶回收容所 → 可付費贖回；沒人贖回會被領養走。**沒有離家出走。**

## 現況

| 部分 | 狀態 |
|---|---|
| 寵物引擎 `mod/lua/pawhome/` | ✅ 完成，145 項離線測試全過，**只在模擬環境驗證過** |
| 介面 `mod/ui/`（繁中／英文） | ✅ 完成，只在桌面預覽驗證過 |
| `adapters/inzoi.lua`（官方 ModKit，連到真遊戲） | ❌ **全是 `error("TODO(Pn)")` 待填空**——第 0 階段的產出 |
| `mod/ui/bridge.js` 的遊戲內傳輸 | ❌ 待 P8 |
| 官方路線遊戲內實測 | ❌ **還沒做過** |
| UE4SS 路線（`adapters/ue4ss.lua`、`mod/ue4ss/`、`scripts/*ue4ss*`、`scripts/smoke-t1.ps1`） | ⏸ 暫停。有遊戲內證據（v0.11.0），但裝著 UE4SS 時「存檔後離開」會崩潰（ADR 0005） |

## 第一優先：第 0 階段（官方 ModKit）

照 `docs/phase0-probe.md`（P1–P10）透過 MCP 在真遊戲上做，結果寫 `docs/phase0-results.md`，決定方案 A（真領養）／B（在家生成）／C（虛擬寵物）。官方文件已讀到的事實與尚未證實的部分在 `docs/modkit-route.md`。**方案 C（虛擬寵物）是一定做得到的底線；「會自己走動的寵物」是未證實的目標。**

## 規矩

1. **絕對不要捏造探勘結果。** 指令名稱、Lua API、參數、行為，都要是從真的遊戲、MCP 或 `mod-docs.playinzoi.com` 實際看到的。不確定就寫「未驗證」。
2. **只有 `core/api.lua` 和 `adapters/*` 可以碰遊戲**，其他模組只能呼叫 `Api.*`。
3. **CLI 指令**：官方頁面（2026-10-20）列 407 個指令，頁面沒有定義 Public／非 Public；`docs/research-report.md` 的「318／115」是搜尋摘要，**以 P1 實測為準**。在弄清楚之前，不要依賴 UserCheat／ScriptCheat 類指令。
4. **不要覆寫 Zoi 的個性、自主行為、情緒、動畫**（二手轉述的官方說法：這些不開放給模組）。只做宏觀層面（領養、需求、照顧）。
5. adapter 的 `caps`（`spawn`、`moveStray`、`buffs`、`animate`）**只有在遊戲內實測過之後才能設為 true**。
6. 新增或修改邏輯時，在 `tests/` 補測試（用 `adapters/mock.lua`），並維持全綠：
   - Windows：`py -I tests\run.py`（需要 `pip install lupa`），或 `lua -e "package.path='mod/lua/?.lua;tests/?.lua;'..package.path" tests/run.lua`
   - 注意：直接用 `lua` 跑時程式結束碼一律是 0，**要看最後一行的 passed／failed**。
7. 字串一律放 `mod/lua/pawhome/localization/`，**en 與 zh_TW 的鍵與 `{佔位符}` 必須一致**（測試會檢查）。UI 不放任何寫死的文字。
8. 平衡數值放 `mod/lua/pawhome/data/`，不要寫死在程式裡。
9. 存檔格式有版本號：改 `state` 結構要加 `core/storage.lua` 的 migration，不能讓舊存檔壞掉。
10. 引擎與資料表用 Lua table，**不用 JSON**（官方 Lua 環境不一定有 JSON 解析器）。
11. 不要把 ModKit 的 Unreal 專案或大型二進位檔直接 commit；先和 PO 討論 `.gitignore` 或 Git LFS。
12. 桌面預覽：`py tools\preview_server.py` → `http://127.0.0.1:8765/?preview=1`。改 Lua 之後要重啟它。
13. 永遠不取得 AES 金鑰、不散佈 KRAFTON 的遊戲資源。

## 開發規則（ADR 0006，取代 ADR 0003 的審查與角色部分）

- **角色**：PO＝使用者；Dev＝本 session（開發＋自我審查）。沒有其他 session。
- **分支**：`feat/`、`fix/`、`docs/`、`chore/` 短命分支，squash merge，Conventional Commits（英文）。**功能分支可以直接推送；預設分支 `ccr-d0885a2d-yzygl2` 絕不直接推送。**
- **合併**：測試全綠＋CI 綠＋自我審查（對照下方完成標準）＋**PO 說「可以合併」**。每次都要問。
- **完成標準**：有測試、en／zh-TW 一致、存檔結構變更有 migration、遊戲介接函式標明「已驗證（遊戲版本＋日期＋依據）／未驗證」、文件與 CHANGELOG 更新。
- **遊戲操作**：啟動遊戲到主選單＝每個工作階段問 PO 一次；進存檔、透過 MCP 操作存檔＝PO 在電腦前同意＋**先備份兩個存檔資料夾**（`Documents\inZOI\SaveGames`、`%LOCALAPPDATA%\BlueClient\Saved\SaveGames`，做完核對檔案數與大小）。載入存檔時絕不強制結束遊戲。
- **一律先問 PO**：規格與玩法、下載或安裝任何東西（說明檔名、來源、大小）、發佈到外部平台、改寫 git 歷史、刪分支、改預設分支、修改使用者的全域設定。
- **MCP**：`inzoi-game`、`inzoi-modkit` 登記在 repo 的 `.mcp.json`；遊戲要開著、ModKit 要開著才連得到。

## Git

- 預設分支：`ccr-d0885a2d-yzygl2`。未經 PO 要求不要開 PR。
- 參考用、不再開發的 UE4SS 分支：`feat/observe-existing-cat`、`docs/t2-m1-3a-results`（未合併）。
