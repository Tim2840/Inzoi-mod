# 交接：把開發交給本機 Claude Code session

## 為什麼要交給本機 session

雲端 session 碰不到你的 Windows，所以做不了第 0 階段探勘、接遊戲和遊戲內實測。這三件事只有跑在你電腦上、又能連到 `inzoi-game` / `inzoi-modkit` 兩個 MCP 的 session 才做得到。

## 開始前（約 5 分鐘）

- [ ] 照 [`setup-windows.md`](setup-windows.md) 裝好環境，步驟 6 的驗證都是綠的（遊戲開著 → `inzoi-game` Connected；ModKit 開著 → `inzoi-modkit` Connected）
- [ ] `C:\Dev\Inzoi-mod` 在 `ccr-d0885a2d-yzygl2` 分支，並且是最新：
  ```powershell
  cd C:\Dev\Inzoi-mod
  git pull origin ccr-d0885a2d-yzygl2
  ```
- [ ] **先開 inZOI 進存檔，再開 ModKit**，兩個都保持開著

## 啟動本機 session

```powershell
cd C:\Dev\Inzoi-mod
claude
```

想在 Claude Code app／手機上看同一個本機 session，改用：

```powershell
claude remote-control
```

啟動時它會自動讀 `CLAUDE.md`，裡面有專案現況、規矩和已知未知，所以你**不用重新解釋專案**。

## 第一則訊息（整段複製貼上）

```
請接手這個專案的開發。先讀 CLAUDE.md、docs/pet-mod-plan.md、docs/phase0-probe.md。

目前遊戲和 ModKit 都開著，inzoi-game 與 inzoi-modkit 兩個 MCP 應該已連線。

第一個任務：做 docs/phase0-probe.md 的第 0 階段探勘（P1 到 P10），把真實結果填進 docs/phase0-results.md。
- 每一題都要附上你實際執行的指令與遊戲回傳的內容，不要猜、不要捏造；做不到就寫「未驗證／做不到」與原因。
- 也請在 ModKit 的 Lua 編輯器跑 mod/lua/pawhome/adapters/inzoi.lua 裡的 Adapter.discover()，把輸出存成 docs/probe/discover.txt。
- 全部做完後，依 phase0-probe.md 最後的判斷規則，告訴我該走方案 A、B 或 C，以及理由。

做完探勘先停下來給我看結果，我確認方案之後，你再開始填 adapters/inzoi.lua 並在遊戲裡實測。
```

## 之後的工作順序（本機 session 負責）

1. **探勘** → `docs/phase0-results.md`，決定方案 A/B/C（**需要你確認**）
2. **填 `adapters/inzoi.lua`**，只把實測過的 `caps` 設為 true
3. **接 UI 傳輸層**（`mod/ui/bridge.js` 的遊戲內分支，P8）
4. **在 ModKit 建專案並打包**，載入遊戲做冒煙測試：領養 → 照顧 → 存檔讀檔 → 快轉
5. **用真實的遊戲日長度重新校準平衡**（`mod/lua/pawhome/data/`、`pets/neglect.lua`）
6. **上傳 CurseForge**（需要你的帳號，由你操作）

## 分工與避免衝突

| 誰 | 做什麼 |
|---|---|
| **本機 session** | 上面所有需要遊戲的工作，**之後程式碼以它為主** |
| **雲端 session（我）** | 不碰遊戲的部分：文件、模組頁面文案、新增玩法邏輯與測試（只在你要求時） |

雲端和本機如果**同時**改程式，請其中一邊用別的分支（例如本機用 `local-dev`），再合併，不然 push 會衝突。最簡單的做法：**交接之後，雲端 session 不再改程式碼，除非你明確叫我做**。

## 本機 session 做完後，請它回報

- 探勘結果表與最後選的方案
- 哪些 `caps` 實測可用
- 遊戲內冒煙測試的結果（含失敗的）
- 一個遊戲日等於現實幾分鐘
- 還沒解決的問題
