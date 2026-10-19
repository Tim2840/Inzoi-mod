# 交接（2026-10-20）：官方 ModKit 路線開工

給在 `C:\Dev\Inzoi-mod` 開的新 session。決定紀錄：ADR 0005（改走 ModKit）、ADR 0006（規格、規則、MCP）。

## 目前狀態
- 分支：`chore/modkit-kickoff`（本交接所在，疊在 `docs/modkit-route` 上，**都還沒合併**進預設分支，合併要問 PO）。
- ModKit：PO 正在從 Epic 安裝。
- MCP：repo 的 `.mcp.json` 已登記 `inzoi-game`（:11212）、`inzoi-modkit`（:11213）；第一次執行 `claude` 時 PO 要按信任。
- 遊戲資料夾：**UE4SS 已停用**（`Win64\dwmapi.dll` 改名為 `dwmapi.dll.off`，改回即恢復）；`ue4ss\Mods\PawHome\pawhome_disabled.txt` 存在；ZoiPets 的 `enabled.txt` 改名為 `enabled.txt.off`。紀錄：`C:\Dev\backups\2026-10-20-pre-M1-3b\isolation-state.txt`。
- 存檔備份（已驗證）：`C:\Dev\backups\2026-10-20-pre-T2`、`-pre-M1-3b`、`-pre-isolation`、`-pre-isolation-2`。
- 測試：135/135（Lua 5.4）。

## 下一步
1. ModKit 裝好後：PO 開遊戲（進存檔）與 ModKit，`claude mcp list` 確認兩個伺服器 Connected。
2. 照 `docs/phase0-probe.md` 做 P1 → P7 → P8（底線：計時、存資料、UI 按鈕），再做 P2–P6、P9。進存檔前先備份。
3. 結果寫 `docs/phase0-results.md`，決定方案 A／B／C。

## 尚未處理
- `docs/engineering-workflow.md` 內文仍是雲端時期的版本；以 ADR 0006 與 `CLAUDE.md` 為準，之後再改寫。
