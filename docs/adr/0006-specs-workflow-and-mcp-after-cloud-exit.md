# 0006 規格定案、雲端退出後的開發規則、MCP 設定方式

- 日期：2026-10-20　狀態：**採用**　決定者：**PO（使用者）**，在本機 session 逐題決定　取代：ADR 0003 的角色與審查部分
- **背景**：PO 改走官方 ModKit（ADR 0005），雲端 session 於同日退出，只剩 PO＋一個本機 session。原規則中的「雲端審查、四眼原則、通知雲端 session」不再適用；幾項規格也一直未決。

## 決定

### 規格
1. **專案統一用 Paw Home**（`Tim2840/Inzoi-mod`）。ZoiPets（`Desktop\inzoi-pet-mod`）封存為參考，不再開發。
2. **每戶寵物數**：預設 **1 隻**，設定頁最多可開到 **4 隻**（`data/settings.lua` 預設 1，`app.lua` 範圍 1–4，設定頁新增滑桿）。
3. **老死**：維持現狀——預設會長大、變老、**老死**；設定頁可關閉老化。
4. **需求**：維持 **4 個**（飢餓、精力、玩樂、貓砂）；精力靠睡眠自動回復。

### 開發規則
5. 角色：**PO**＝使用者（規格、對外與不可逆的決定）；**Dev**＝本機 session（開發，並自我審查）。
   - 四眼原則改為：合併進預設分支前，**測試全綠＋CI 綠＋Dev 對照完成標準自我審查＋PO 說「可以合併」**。
   - **功能分支 Dev 可以直接推送**，不必每次詢問；**預設分支（`ccr-d0885a2d-yzygl2`）絕不直接推送**，合併每次都問 PO。
   - 遊戲操作：啟動到主選單＝每個工作階段問 PO 一次；進存檔、透過 MCP 操作存檔＝PO 在電腦前同意＋先備份存檔（`Documents\inZOI\SaveGames` 與 `%LOCALAPPDATA%\BlueClient\Saved\SaveGames`）。
   - 不再有 session 間的 `send_message` 通知；有需要 PO 的事直接在對話裡問。
6. **MCP**：`inzoi-game`（`localhost:11212`）與 `inzoi-modkit`（`localhost:11213`）登記在 repo 的 **`.mcp.json`**（專案設定），不寫入使用者的全域設定。第一次在 repo 資料夾執行 `claude` 時由 PO 確認信任。`scripts/setup-windows.ps1` 不再做全域註冊。

## 後果
- 引擎測試的輔助函式把上限設為 4（比較多隻貓的測試需要），出貨預設值 1 由獨立測試檢查。
- `CLAUDE.md` 與 `docs/engineering-workflow.md` 中雲端相關的段落以本 ADR 為準。
- 仍未決：無（本次之前的未決規格都已定案）。下一個決定點是第 0 階段的結果（方案 A／B／C）。
