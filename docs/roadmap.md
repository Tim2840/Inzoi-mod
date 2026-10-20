# 路線圖與分工（2026-10-21 起）

PO 的目標（2026-10-21）：接近 The Sims 4《貓狗成群》家貓的程度，以做得到的為主。三個主要目標：

1. **會走動的貓**，動畫流暢、不可破圖。
2. **花色固定的貓**。
3. **寵物店介面整合進遊戲的手機與電腦**，可愛、獨特，圖示自己畫（不用 emoji 或公版圖示）。

日期是預定完成日，研究結果可能改變後面的排程；改了就更新這份文件。

## 工作線

| 代號 | 內容 | 負責 | 分支 | 預定 |
|---|---|---|---|---|
| M1 | 經 adapter 送走貓；餵食／逗貓計入引擎需求與親密度；城市貓選單加「領養」 | 主 session | `feat/modkit-care` | 10-24 |
| M2 | 專用測試存檔（不再動 PO 的存檔）、遊戲內自動測試腳本 | 主 session | 同上 | 10-24 |
| W1 | 會走的貓：研究可行性（結論＋證據） | 走路 session | `feat/walking-cat` | 研究 10-24 |
| W2 | 會走的貓：原型與流暢度驗證（研究結論可行才做） | 同上 | 同上 | 10-31 |
| C1 | 固定花色：找出隨機來源，研究能否固定，並決定可選幾種花色 | 花色 session | `feat/fixed-coat` | 研究 10-23 |
| C2 | 固定花色實作＋存進寵物資料（領養時選花色） | 同上 | 同上 | 10-27 |
| U1 | 手機／電腦入口研究、可愛版面設計、自製 SVG 圖示組 | 介面 session | `feat/phone-pc-ui` | 設計 10-25 |
| U2 | 遊戲內入口實作與驗證（手機、電腦都能打開寵物店） | 同上 | 同上 | 10-29 |
| S1 | 原版貓用品（`CatToy01`、`CatPuree01`、`CatSandSpray01` 等）：店裡買、對應需求（玩樂、飢餓、貓砂） | 主 session | 另開 | 11-05 |
| S2 | 幼貓長大：外觀尺寸隨年齡變化（要先證實物件能縮放） | 走路 session 的研究順帶 | — | 11-07 |
| S3 | 生病與獸醫（需求長期過低→生病→付費看診） | 主 session | 另開 | 11-12 |
| S4 | 個性對行為與互動的影響、訓練 | 主 session | 另開 | 11-14 |
| P1 | 打包（ModKit 專案）、安裝說明、雙語說明頁 | 主 session | 另開 | 11-15 |
| P2 | 發佈到 CurseForge | 主 session | — | **需 PO 同意** |

《貓狗成群》有、而我們**不做**或**延後**的：狗、創造寵物（自訂毛色編輯器）、寵物服裝、寵物與 Zoi 的社交互動動畫——取決於 W1／C1 的研究結果，屆時再評估。

## 協作規矩（給每個 session）

- **遊戲只有一個。** 會改變遊戲狀態的操作（讀檔、離開存檔、掛載模組、寫開發版模組資料夾、`data.patch`、作弊、生成物件）都要先拿遊戲鎖：
  `py -I tools/game_lock.py acquire <你的名字> 45 <做什麼>`；結束前回到主選單、卸載自己掛的模組，再 `release`。
  拿不到鎖就先做不需要遊戲的工作，稍後再試。只讀查詢（`data.table_get`、`cli_help`、`game.get_state`、掃描）不用鎖。
- 拿鎖之後、操作之前，先看 `game.get_state`：如果狀態不是上一個持鎖者留下的樣子（例如 PO 正在玩），立刻停手並回報。
- **不要存 PO 的存檔。** 需要存檔的測試用專用測試存檔（名稱見 M2，完成前一律不存檔離開）。
- 開發版模組資料夾 `Documents\inZOI\Mods\InGame\PawHomeDev_A5BI7C` 是共用的：只在持鎖時用 `py -I tools/build_modkit.py` 重建，釋放鎖前不需要還原。
- ModKit 的官方文件在 `C:\Games\inZOIModKit\inZOIModKit\Data\Tools\mcp\modkit\`（`workspace_docs/`、`data_asset_schemas/`、`datatable_docs/`、`cli_catalog.json`）；Lua 定義檔在遊戲目錄 `BlueClient/Content/Data/Lua/luals-defs/`。
- 研究結論寫進 `docs/research/<主題>.md`：每一條都標「已驗證（遊戲版本、日期、依據）」或「未驗證」，不捏造。
- 只改自己工作線的檔案；共用檔案（`mod/ui/bridge.js` 的 `GAME_DATA`、`mod/lua/pawhome/adapters/inzoi*.lua`）的修改要小而集中，方便合併。
- 不下載、不安裝任何東西，不發佈到外部；需要的話回報給主 session。
- 完成時：測試全綠、推送自己的分支，回報結果與分支名稱；合併由主 session 處理。
