# PO 同意紀錄（遊戲操作與推送）

記錄使用者（PO）對遊戲操作層級（見 `docs/engineering-workflow.md` §9）與關鍵動作的同意。**只有 PO 本人的明確同意才可記錄**；同意範圍以下表為準，超出範圍必須重新取得。

| 日期（UTC） | 層級／動作 | 範圍 | 原文 | 取得方式 | 備註 |
|---|---|---|---|---|---|
| 2026-10-18 | 推送分支 | 本機 session 推 `feat/ue4ss-adapter` 到 `Tim2840/Inzoi-mod`（只新增分支） | 「可以推送，同意啟動遊戲驗證」 | PO 在雲端 session 親自回覆，由雲端 session 轉達本機 session；本機 session 可要求 PO 另行確認 | 不動預設分支 |
| 2026-10-18 | **T1**（一次性） | inZOI **v0.11.0**（exe 20261013.16166）：安裝／更新自己的 `ue4ss\Mods\PawHome`；啟動遊戲停在主選單、只做注入與讀寫檔驗證；不點「繼續」、不讀檔；只在主選單時關閉 | 同上 | 同上 | 啟動前確認遊戲行程未在執行；**不含 T2／T3**；遊戲 build 改變後需重新同意 |

## 尚未取得的同意
- **T2**（進存檔、生成／操作貓）：每次需 PO 在場或明確同意，並先備份存檔（`docs/qa/smoke-checklist.md`）。
- **T3**（安裝／移除／更新 UE4SS 本體）。
- 開 PR／Issue、刪除審查用遠端分支 `docs/claude-md-workflow`、啟用 branch protection、發佈到 CurseForge／Nexus。
