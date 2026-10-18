# CLAUDE.md — 毛孩之家 Paw Home（inZOI 寵物模組）

給在這個 repo 工作的 Claude Code。先讀這份，再讀 `docs/pet-mod-plan.md` 與 `docs/phase0-probe.md`。使用者說繁體中文，回覆請用繁體中文；程式碼、註解、commit 訊息用英文。

## 專案是什麼

inZOI 目前沒有寵物系統。本模組用官方 ModKit 的 **Lua 腳本模組** 加 **HTML/JS Overlay UI**，照 The Sims 4《貓狗成群》的玩法補上養貓：領養、需求、個性、成長老死、親密度、訓練、疏於照顧被動保員帶走。第一版只做貓。語系：繁體中文、English。

## 現況（務必看清楚哪些做了、哪些沒做）

| 部分 | 狀態 |
|---|---|
| 寵物引擎 `mod/lua/pawhome/`（需求、個性、心情、老化、親密度、訓練、照顧、忽略離家、領養、存檔） | ✅ 完成，67 項測試全過，**只在模擬環境驗證過** |
| 介面 `mod/ui/`（繁中／英文） | ✅ 完成，只在桌面預覽驗證過 |
| `mod/lua/pawhome/adapters/inzoi.lua`（連到真遊戲） | ❌ **全是 `error("TODO(Pn)")` 待填空** |
| UI 在遊戲內與 Lua 溝通的傳輸層 `mod/ui/bridge.js` | ❌ 遊戲內分支還會丟錯（待 P8） |
| 遊戲內實測 | ❌ **一次都沒有做過** |

## 平行專案：ZoiPets（UE4SS 路線）

使用者另有一個本機專案 `C:\Users\user\Desktop\inzoi-pet-mod`（ZoiPets），走 **UE4SS Lua ＋ pak 替換**，已在 inZOI v0.10.0 驗證 UE4SS 可注入、可讀寫檔、找到主選單的貓 actor `BP_Pet_Customize_01_C`。以上是從該 session 的紀錄讀到的，**本 repo 的 session 沒有親自驗證**。兩個專案的關係、差異與建議的處理順序見 [`docs/handoff-ue4ss-session.md`](docs/handoff-ue4ss-session.md)。

- 本 repo 的程式（官方 ModKit 路線）**仍然沒有在遊戲內跑過**。
- 官方 ModKit 路線做不到真正的動物 AI；UE4SS 路線可能做得到，但**尚未驗證**。
- 兩邊如何合併由使用者決定，不要自行刪除或覆寫另一邊。
- **已定案（使用者，2026-10-18）**：疏於照顧**不做離家出走**，改成「軟性懲罰 → 動保員警告 → 帶回收容所 → 可付費贖回（有等待時間、親密度打折）」，與 ZoiPets 一致。其餘規格（老死、每戶隻數、只走 UE4SS 或雙 adapter）**尚未決定**。

## 第一優先：第 0 階段探勘

照 `docs/phase0-probe.md` 在真的遊戲上做，把結果填到 `docs/phase0-results.md`。這份探勘決定走方案 A（真領養）、B（在家生成）、C（虛擬寵物）。

## 規矩

1. **絕對不要捏造探勘結果。** 指令名稱、Lua API、參數、行為，都要是從真的遊戲或 `mod-docs.playinzoi.com` 實際看到的。不確定就寫「未驗證」。
2. **只有 `core/api.lua` 和 `adapters/*` 可以碰遊戲**，其他模組只能呼叫 `Api.*`。遊戲更新時應該只需要改 adapter。
3. **只用 Public 指令**（CLI 目錄 318 個指令只有 115 個是 Public；UserCheat／ScriptCheat 在玩家端是 no-op）。
4. **不要覆寫 Zoi 的個性、自主行為、情緒、動畫**，官方明說不開放給模組。只做宏觀層面（領養、需求、照顧）。
5. `adapters/inzoi.lua` 的 `caps`（`spawn`、`moveStray`、`buffs`、`animate`）**只有在實測過之後才能設為 true**。
6. 新增或修改邏輯時，在 `tests/` 補測試（用 `adapters/mock.lua`），並維持全綠：
   - Windows：`py -I tests\run.py`
   - macOS／Linux：`python3 -I tests/run.py`（需要 `pip install lupa`）
7. 字串一律放 `mod/lua/pawhome/localization/`，**en 與 zh_TW 的鍵與 `{佔位符}` 必須一致**（測試會檢查）。UI 不放任何寫死的文字。
8. 平衡數值放 `mod/lua/pawhome/data/`，不要寫死在程式裡。
9. 存檔格式有版本號：改 `state` 結構要加 `core/storage.lua` 的 migration，不能讓舊存檔壞掉。
10. 資料表用 Lua table，**不用 JSON**（遊戲的 Lua 環境不一定有 JSON 解析器）。
11. 不要把 ModKit 的 Unreal 專案或大型二進位檔直接 commit；先討論要用 `.gitignore` 還是 Git LFS。
12. 桌面預覽：`py tools\preview_server.py` → `http://127.0.0.1:8765/?preview=1`。改 Lua 之後要重啟它。

## 已知未知（探勘要回答）

- Lua 有沒有計時器／遊戲事件？能不能存資料（P7）？
- 能不能找到、移動、生成貓，存檔讀檔後還在嗎（P2–P5）？
- 能不能觸發貓的互動或動畫（P6）？能不能在原版貓互動選單加選項（P9）？
- UI 怎麼呼叫 Lua（P8）？
- 一個遊戲日等於現實多久？（用來重新校準 `neglect.lua` 的「約 2–3 天被動保員帶走」是否太嚴）

## 分工與開新 session 的規則（使用者已同意，2026-10-18）

- **本機 session（ZoiPets，跑在使用者電腦）** 負責開發與一切需要遊戲、UE4SS、使用者電腦的工作；**雲端 session** 負責檢查（code review、跑測試、對照本檔規則）與不需要遊戲的工作。雲端 session 看不到遊戲內的結果，不能代替實測。
- 雲端 session **可以自行決定另開 session**，但只限：獨立、範圍清楚、**不需要遊戲或使用者電腦**的雲端工作（例如補測試、寫文件、調整介面）。
  - 開了就**立刻告訴使用者**開了什麼、為什麼。
  - 在**自己的分支**工作，不碰預設分支，不改別人正在改的檔案。
  - **數量從嚴**：一次只開需要的，每個 session 只做一件小事（每個 session 都會消耗使用者的額度）。
- 以下情況**一律先問使用者**，不可自行開 session 去做：需要遊戲／UE4SS／使用者電腦的事、會改規格或玩法或兩個專案合併方式的事、會動到別人正在改的檔案。
- 同時有多個 session 改程式時，各用各的分支，合併前先讓使用者知道。

## 開發流程摘要（完整版：`docs/engineering-workflow.md` v1.0；決定紀錄：`docs/adr/0003`）

- **角色**：PO＝使用者；Dev＝本機 session（碰遊戲／UE4SS／安裝腳本）；Review/QA/Release＝雲端 session（引擎、CI、文件、ADR）。
- **四眼原則**：合併進預設分支前必須有**非作者**審查通過；不直接 push 預設分支。目前未啟用 PR／Issue（需 PO 同意），審查流程＝推分支＋`send_message` 通知＋審查結果寫 `docs/reviews/`。
- **分支與提交**：`feat/`、`fix/`、`docs/`、`chore/` 短命分支，squash merge，Conventional Commits（本 repo 用英文）。
- **擁有權**：`pets/`、`data/`、`localization/`、`mod/ui/`、`tools/` → 雲端；`adapters/ue4ss.lua`、`mod/ue4ss/`、`scripts/`、`docs/qa/` → 本機。`core/api.lua`：新增「選用」函式＝adapter 方作者＋通知；改必要函式或既有語意＝雙方 review。
- **完成標準**：CI 綠、有測試、en／zh-TW 一致、存檔結構變更有 migration、遊戲介接函式標明「已驗證（build 號＋日期＋依據）／未驗證」、文件與 CHANGELOG 更新。**沒有遊戲內證據就不是「已驗證」，`caps` 不得設 true。**
- **遊戲操作同意層級**：T0 讀檔／離線測試／改程式（不需同意）；T1 安裝自己的 `ue4ss\Mods\PawHome`＋啟動遊戲停在主選單做注入與讀寫檔驗證（PO 一次性同意，不點「繼續」；**載入存檔時絕不強殺**）；T2 進存檔、生成／操作貓（PO 在場或明確同意、先備份、不在連線遊玩時）；T3 安裝／移除 UE4SS 本體或動 Mods 以外（PO 明確同意）。
- **一律問 PO**：玩法與規格、啟動遊戲（依上述層級）、發佈到外部平台、改寫歷史／刪分支／改預設分支名／開啟 branch protection、一次開多個 session、合併兩個專案的最終方案。永遠不取得 AES 金鑰、不散佈 KRAFTON 資源。
- **目前里程碑**：M1「畫面上出現一隻貓，並知道牠能不能自己動」（`docs/engineering-workflow.md` §14）。原「第 0 階段探勘」改以 M1 為準，`docs/phase0-probe.md` 保留作官方 ModKit 路線的參考。

## Session 之間的通知約定（使用者要求，2026-10-18）

- 本機 session 在以下情況要用 `send_message` 對雲端 session（`session_011JM8yBsFxnGHQKyQyyQsV5`）傳 3 行以內的短訊息，**不必等整件事做完**：①完成交付物（commit、推送、測試結果）②**卡在等使用者同意或在電腦前**，並寫明他要做什麼 ③發現需要使用者決定的事。格式：狀態（完成／卡住／需決定）→ 重點 → 下一步。
- 雲端 session 在等本機 session 的期間，要**自己排定時檢查**（`send_later`），只在狀態有變化時才用 `PushNotification` 通知使用者；沒變化就靜默重排，並有次數上限，不可一直重複。收到回報後不可取消檢查，除非確定已無後續。

## Git

- 開發分支：`ccr-d0885a2d-yzygl2`（也是 repo 預設分支）。若有人同時在雲端 session 改程式，建議本機另開分支再合併，避免衝突。
- commit 訊息用英文、說明為什麼。未經使用者要求不要開 PR。
