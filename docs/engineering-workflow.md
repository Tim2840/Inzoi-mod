# 開發分工與規則（v1.0）

> 狀態：**v1.0 採用**（雲端與本機 session 經 2 輪討論達成共識，見 ADR 0003）。精簡版放在 `CLAUDE.md`（`CLAUDE.md` 屬雙簽檔案，已走審查）。
> **尚待 PO（使用者）回覆**：①是否允許開 PR／Issue（回覆前沿用「推分支＋訊息＋`docs/reviews/`」）②T1 一次性同意 ③同意推送 `feat/ue4ss-adapter`。
> 授權：使用者（Tim）2026-10-18 授權兩個 session「自己訂開發分工與規則，高自主開發」。

## 1. 角色（誰負責什麼）

| 角色 | 由誰擔任 | 負責 | 不能做 |
|---|---|---|---|
| **產品負責人（PO）** | 使用者 Tim | 範圍、玩法規格、優先順序、**一切對外與不可逆的決定** | — |
| **開發者（Dev）** | 本機 session（跑在使用者電腦） | 所有碰遊戲／UE4SS／使用者電腦的工作；adapter、遊戲內實測、安裝腳本；寫程式＋測試、開 PR | 自己核准自己的 PR；未經 PO 同意啟動遊戲；改引擎規則而不經 owner review |
| **審查與品質（Review/QA/Release）** | 雲端 session | code review、跑 CI、對照規則；維護 CI、文件、ADR、CHANGELOG；引擎（`pets/`、`data/`、`localization/`）的程式 | 代替遊戲內實測；核准自己寫的 PR |
| **臨時 worker** | 雲端 session 另開的小 session | 獨立、不需遊戲的小任務（見 `CLAUDE.md` 規則） | 碰遊戲、改規格 |

**四眼原則**：任何合併進預設分支的變更，必須由**不是作者的那一方**審查通過。

## 2. 程式碼擁有權（改動別人的目錄要經 owner review）

| 路徑 | Owner |
|---|---|
| `mod/lua/pawhome/pets/`、`data/`、`localization/`、`core/`（api 契約除外）、`mod/ui/`、`tests/test_pets.lua`、`tests/test_core.lua`、`tools/` | 雲端 |
| `mod/lua/pawhome/adapters/ue4ss.lua`、`mod/ue4ss/`、`scripts/`、`tests/test_ue4ss.lua`、`docs/qa/` | 本機 |
| `core/api.lua`（adapter 契約）、`CLAUDE.md`、`docs/adr/` | **分兩級**：①新增「選用」函式＝adapter 方（本機）作者＋**通知**對方即可；②改「必要」函式或既有語意＝**雙方 review** |
| `docs/` 其他 | 共用，誰改誰是作者、另一方審查 |

## 3. 分支與合併（trunk-based、短命分支）

- 預設分支永遠可用（測試全綠）。**不直接 push 預設分支**，一律走分支 → 審查 → 合併。（目前 GitHub 不能強制，靠約定；之後建議使用者開啟 branch protection。）
- 分支命名：`feat/<主題>`、`fix/<主題>`、`docs/<主題>`、`chore/<主題>`（例：`feat/ue4ss-adapter`）；一個分支只做一件事，存活不超過數天。
- 合併方式：**squash merge**，一個 PR 一個 commit，訊息用 Conventional Commits（**Paw Home repo 用英文**；ZoiPets 專案維持中文）：`feat(adapter): ...`、`fix(pets): ...`、`docs: ...`、`test: ...`、`chore(ci): ...`。
- **誰合併**：審查方核准且 CI 綠 → **作者合併**（高自主）；合併後通知 PO。涉及「§8 要問 PO」的事，核准不等於同意，仍需 PO。
- 不改寫別人分支的歷史；衝突時用 merge，不 rebase 別人的分支。

## 4. 變更單位：Issue → PR

- 工作用 **GitHub Issue** 記錄（標題＝使用者價值或技術目標，內含完成條件）。小事可以直接開 PR。
- PR 使用 `.github/pull_request_template.md`，必填：做了什麼／為什麼、測試證據、**遊戲內驗證狀態**（已驗證＋遊戲 build 號／未驗證）、風險、是否動到契約。
- ⚠ **PR 與 Issue 要由 PO 同意才開**（預設規則：未經使用者要求不開 PR）。PO 同意前，沿用現在的方式：**推分支＋用 `send_message` 通知對方審查**，審查結果寫在對話與 `docs/reviews/` 裡。

## 5. Definition of Done（合併前必須全部成立）

1. CI（`.github/workflows/test.yml`）綠；本機也能跑 `py -I tests\run.py`。
2. 新增邏輯有測試（用 `adapters/mock.lua` 或 fake UE4SS）。
3. en／zh-TW 字串齊全、佔位符一致（測試會擋）。
4. 動到存檔結構 → 有 migration ＋測試。
5. 動到遊戲介接 → 每個函式在 `docs/ue4ss-adapter.md` 標明「已驗證（遊戲 build 號、日期、依據）／未驗證」；`caps` 只有實測後才可為 true。
6. 文件同步（README／docs／CHANGELOG 的 `Unreleased`）。
7. 非作者審查通過；所有 blocker 已處理。

## 6. 審查規則

- 嚴重度：**blocker**（錯誤、違反規則、會弄壞存檔）／**major**（設計缺陷、缺測試）／**nit**（風格）。blocker 與 major 必須處理，nit 作者自行裁量。
- 審查看：①對照 `CLAUDE.md` 規則 ②驗證狀態有沒有依據 ③測試是否真的測到行為（不只是通過）④與其他路徑的相容性。
- 審查方**不得**在沒有證據下宣稱「遊戲內可行」；作者**不得**在沒實測下把 `caps` 設為 true。

## 7. 測試策略（金字塔）

| 層 | 內容 | 在哪跑 | 頻率 |
|---|---|---|---|
| 單元／行為 | 引擎（需求、個性、老化、收容所…）＋模擬 30 天 | CI（lupa）＋本機 | 每次 push |
| Adapter 契約 | 用 fake UE4SS API 驗證 adapter：真檔案存讀、`.bak` 復原、分區、進入點（整點才 tick、錯誤被吞、按鍵有註冊）。**fake 的資料必須來自真實 log／探索輸出，並在 fixture 標註「觀測自哪個遊戲 build」**，避免測寂寞 | CI＋本機 | 每次 push |
| 遊戲內冒煙（T1，**全自動**） | `steam://` 啟動 → 輪詢 `UE4SS.log` 出現 `[PawHome] loaded` ＋存檔寫出＋探索報告 → **只在主選單時**關閉（`CloseMainWindow` 失敗才用 `Stop-Process`，**有載入存檔時絕不強殺**）→ 自動寫結果檔 `docs/qa/results/<日期>-<exe FileVersion>.md`（附 log 摘錄） | 只有本機 | 每個遊戲 build、每個 release 前 |
| 遊戲內（T2，半自動） | 使用者進存檔（桌面操控授權必須本人按），mod 偵測進入世界就自動跑探索／生成／印數值，使用者只需「點繼續、等 2 分鐘、關遊戲」 | 只有本機＋使用者 | 里程碑驗收 |
| 回歸清單 | `docs/qa/smoke-checklist.md`，結果記在 `docs/qa/results/<日期>-<build>.md` | 本機 | 同上 |

## 8. 什麼事要問 PO（其餘兩個 session 自行決定）

- 玩法與規格（隻數、老死、數值、經濟、新功能）。
- **啟動遊戲**（見 §9 同意層級）。
- **發佈**到 CurseForge／Nexus／任何外部平台。
- 改寫 git 歷史、刪除分支或檔案、改預設分支名稱、開啟 branch protection。
- 花額度的大動作（一次開多個 session）。
- 取得或使用 AES 金鑰、散佈 KRAFTON 資源（**永遠不做**）。
- 兩個專案如何合併的最終方案。

## 9. 遊戲操作的同意層級

| 層級 | 內容 | 同意 |
|---|---|---|
| T0 | 讀檔、讀 log、跑離線測試、改程式 | 不需要 |
| T1 | 安裝／更新**我們自己的** `ue4ss\Mods\PawHome`（腳本可還原、**不碰遊戲檔**；**uninstall 移除的必須恰好就是 install 加入的**，存檔保留）；啟動遊戲**停在主選單**、只做注入與讀寫檔驗證、正常關閉。**不點「繼續」、不讀檔** | **PO 一次性書面同意**（可涵蓋「同一個遊戲 build」的 T1） |
| T2 | 進存檔、生成／操作貓、改動存檔內容。**不在連線遊玩時進行** | **PO 在場或明確同意**，並先備份存檔 |
| T3 | 安裝／移除／更新 **UE4SS 本體**，或動 `ue4ss\Mods` 以外的任何遊戲資料夾內容 | **PO 明確同意**，且用安裝腳本（可還原） |

## 10. 溝通協定

- **時間一律用台灣時間（UTC+8）**：對使用者的回覆、通知、文件、審查與結果紀錄都是。（只有 git、CI 與 log 的原始時間戳保持原樣；引用時請換算。）
- 會議式同步：用 `send_message`，格式「狀態（完成／卡住／需決定）→ 重點 → 下一步」，3 行內。
- 等待對方時，雲端用 `send_later` 定時檢查（只在狀態變化時通知 PO）。
- 每個重要決定寫成 **ADR**（`docs/adr/NNNN-標題.md`：背景、決定、後果、決定者與日期）。

## 11. 版本與發佈

- SemVer，`0.x` 期間不保證相容；`CHANGELOG.md` 採 Keep a Changelog。
- 相容性表：模組版本 ↔ inZOI build 號（在 `docs/compatibility.md`）。
- Release ＝ tag ＋打包檔 ＋ CHANGELOG ＋ 相容性表更新；**發佈由 PO 決定**。

## 12. 風險登錄（持續維護）

| 風險 | 緩解 |
|---|---|
| 遊戲更新弄壞 UE4SS 或類別名稱 | 每個新 build 先跑 T1 冒煙；adapter 集中、契約穩定 |
| 注入被反作弊／ToS 處理 | PO 知情；不連線遊玩時測試；保留 ModKit 路線（雙 adapter）作為後路 |
| 兩個 session 衝突 | 擁有權表、短命分支、一件事一分支 |
| 存檔損毀 | T2 前備份；存檔讀失敗＝視為沒有寵物，絕不讓遊戲崩潰 |

## 13. 工程要求（adapter 與 mod 必備）

1. **Kill switch**：設定 `enabled=false` 可完全停用 mod；`caps` 即 feature flag，預設全 false。
2. **啟動橫幅 log**：mod 版本＋遊戲 build（exe FileVersion）＋UE4SS 版本＋caps，方便回報問題。
3. **未知 build 自動降級為安全模式**（只做虛擬寵物，不碰任何遊戲物件），直到該 build 通過 T1 冒煙並登錄在 `docs/compatibility.md`。
4. **存檔多代備份輪替**（在 adapter 的檔案層實作，引擎不管）；讀失敗＝視為沒有寵物，絕不讓遊戲崩潰。
5. **UE4SS 版本與 SHA256 釘在文件**（`docs/ue4ss-adapter.md`），升級要走 T3。
6. **回復計畫**＝uninstall 腳本＋還原 `.bak`；每個 release 的說明都要寫怎麼完全移除。

## 14. 第一個里程碑 M1「畫面上出現一隻貓，並知道牠能不能自己動」

| # | 工作 | 負責 | 層級 | 完成條件（證據） |
|---|---|---|---|---|
| M1-1 | T1 冒煙自動化＋結果檔＋`docs/compatibility.md` | 本機 | T1 | 在 v0.11.0 產生第一份結果檔（可與 M1-2 並行） |
| M1-2 | adapter 強化：橫幅、安全模式、kill switch、存檔輪替、`main.lua` 進入點測試；**探索工具新增「dump 指定物件的屬性／函式」** | 本機 | T0 | CI 綠、DoD 全過 |
| M1-3a | 進世界自動探索：城市流浪貓的類別、遊戲時間、存檔 key | 本機＋PO | T2 | 探索報告＋log，**標註遊戲 build** |
| M1-3b | **生成實驗（關鍵）**：生成貓後是否會自己走動、有無 AI | 本機＋PO | T2（先備份存檔） | 下列五項證據全部齊備，結論寫成 ADR（方案 A／B／C） |
| M1-4 | 把寫死的家庭／Zoi ID、除錯錢包換成真的 | 本機 | T2 | 領養能真的扣錢；**若找不到金錢 API，允許「記錄為未找到、維持除錯錢包」** |
| M1-5 | CI、PR 範本、`docs/qa/smoke-checklist.md`、審查紀錄 | 雲端 | T0 | 每個分支（或 PR）都有審查記錄 |
| M1-6 | 引擎對「實體貓」的需求盤點與契約草案（**只依已知事實，其餘標未知**） | 雲端 | T0 | `docs/proposals/adapter-contract-physical-cat.md`，經本機審查 |

**M1-3b 的五項證據**：
1. 生成結果的 log（actor 全名）。
2. dump 該 actor 的 `Controller`／`AIControllerClass` 屬性值。
3. 每 5 秒記錄座標、連續 60 秒，**以位移判斷是否自己走動**。
4. 移除後遊戲穩定執行 5 分鐘（沒有崩潰）。
5. 存檔 → 讀檔後確認我們生成的 actor **沒有被寫進遊戲原生存檔**（T2 前先備份存檔）。
截圖為選配（桌面操控需要使用者在場按「允許」）。

## 15. 變更紀錄
- **v1.1（2026-10-19）**：T1 條件「記錄安裝清單」改為「uninstall 移除的恰好就是 install 加入的」（第一次審查 nit 3）；CI 加 `windows-latest`；引擎新增時鐘倒退處理（見 `docs/reviews/2026-10-19-ue4ss-adapter.md` 的 F1）。
- **v0.2（2026-10-18）**：整合本機 session 第 1 輪意見——契約變更分兩級（§2）、T1 全自動冒煙與「有存檔不強殺」（§7）、T1 納入安裝自己的 mod 與「不點繼續」、T2 補「不在連線遊玩」、T3 縮為 UE4SS 本體與 mod 以外（§9）、分支改名 `feat/ue4ss-adapter` 與 commit 語言（§3）、fixture 必須標註觀測 build（§7）、新增 §13 工程要求與 §14 里程碑 M1。
- **v1.0（2026-10-18）**：整合第 2 輪——M1-3 拆成 3a／3b 並訂出五項證據、M1-2 加入「dump 物件」工具、M1-4 允許「記錄為未找到」、M1-6 只依已知事實（見 `docs/ue4ss-adapter.md`）；升為 v1.0。
