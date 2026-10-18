# 審查：`feat/ue4ss-adapter`（M1-1／M1-2）

- 審查者：雲端 session　作者：本機 session　日期：2026-10-19（使用者當地日期）
- 範圍：`origin/ccr-d0885a2d-yzygl2..origin/feat/ue4ss-adapter`，9 個 commit，HEAD `3f312ed`，12 個檔案、+1274／-1 行
- 依據：`docs/engineering-workflow.md` §5–§6、`CLAUDE.md` 規則
- 方式：拉分支到獨立 worktree；逐檔閱讀；`python -I tests/run.py`；對照規則與證據

## 結論：**有條件通過**（0 blocker、3 major、5 nit）
3 項 major 處理完（或寫明理由）後可合併。T1 結果本身是強證據，adapter 的設計與誠實標示都很好。

## 通過的部分（審查確認過）
| 項目 | 結果 |
|---|---|
| 基底 | 就是預設分支最新（`ba0f3fb`），不需要處理衝突 |
| 引擎目錄 | **完全沒動** `pets/`、`data/`、`localization/`、`core/`、`mod/ui/`；只動 `tests/run.lua`（加 suite 清單） |
| 只透過 adapter 碰遊戲 | ✅（`adapters/ue4ss.lua` 與 UE4SS 進入點） |
| caps | 全 false；安全模式下即使請求也強制關閉；`REQUESTED_CAPS = {}` ✅ |
| 驗證標示 | 每個函式標「VERIFIED／UNVERIFIED」並寫明依據與 build（見 M2 的例外） |
| 測試 | 102/102（含 22 個新測試）；用**真檔案**、真實的 `.bak` 輪替、stub 版 `LoopAsync`／`RegisterKeyBind`；stub 檔頭註明「只模擬 v0.10.0 的呼叫形狀，不代表 v0.11.0」 |
| 無禁止內容 | 沒有 AES 金鑰、沒有 KRAFTON 資源；結果檔把 `%USERPROFILE%` 遮蔽 ✅ |
| 腳本安全 | 遊戲在跑就拒絕；找不到 UE4SS 就停（不會偷裝 UE4SS＝T3）；安裝只動自己的 `ue4ss\Mods\PawHome\Scripts` |
| T1 證據 | 結果檔與 `docs/compatibility.md` 一致；偵測到 UE 5.6、橫幅顯示 SAFE MODE、存檔寫出、沒有錯誤行 |

## Major（必須處理）
**M1 `smoke-t1.ps1` 預設會強殺遊戲，沒有確認「沒有載入存檔」**
`CloseMainWindow` 30 秒沒關掉就 `Stop-Process -Force`，而腳本無法知道使用者是否在這 4 分鐘內按了「繼續」。這違反 §7／§9 的規則「有載入存檔時絕不強殺」；腳本只在註解提醒「可能載入存檔時請加 `-NoForceClose`」，預設卻是強殺。
**修法（擇一）**：①預設不強殺，改成 `-ForceClose` 才強殺（失敗就寫「仍在執行，請手動關閉」）；②讓 mod 在 log 寫出目前的世界名稱（你的探索看到大廳是 `/Game/Map/LobbyLevel2`），腳本**只在世界是 Lobby 時**才強殺，讀不到世界名稱就不強殺。①最簡單，②可以做成之後的強化。

**M2 驗證表對存檔函式的「已驗證」說過頭**
`saveGet`／`saveSet` 標「Verified on v0.10.0」，依據是 ZoiPets 用 `io.open` **寫出**檔案。但現在的程式碼還包含：讀回既有檔案、`.bak1` 後備讀取、以及用 `os.rename`／`os.remove` 做的多代輪替——這些在遊戲內**從未執行過**。v0.11.0 的 T1 是第一次寫出（log 是 `started (new)`，沒有既有檔案），輪替路徑沒被走到。
**修法**：①把表拆成「`io.open` 寫出：已驗證（v0.10.0、v0.11.0 T1）」與「讀回既有檔案、`.bak` 輪替：**未驗證**」；②**再跑第二次 T1**（同一個 build，已涵蓋在使用者對 v0.11.0 的 T1 同意內），預期 log 出現 `started (loaded)` 且 `.bak1` 存在，把這兩項寫進結果檔的檢查表；③Windows 的 `os.rename` 不能覆蓋既有檔，Linux 會——所以 CI 只跑 Linux 測不到這個差異。**雲端這邊我會把 CI 加上 `windows-latest`**（見下方跟進）。

**M3 `DEBUG = true` 寫死在 `main.lua`**
用安裝腳本裝出來的 mod 一律是除錯流程：假時鐘（現實 1 分鐘＝遊戲 1 小時）、記憶體裡的 1000 元錢包、四個 Shift 熱鍵。現在只有 PO 在用、caps 全關，所以不是 blocker；但 T2 會在真實存檔裡跑，而且之後任何打包都會帶著它。
**修法**：預設 `false`，只有 mod 資料夾存在 `pawhome_debug.txt` 才開啟（與 kill switch 同一種機制）。`DEBUG=false` 時沒有時鐘，引擎閒置，是安全的預設。

## Nit
1. **fixture 沒有標註觀測 build**：`test_ue4ss.lua` 的探索測試用的物件名稱來自 v0.10.0（build 20260915.15331）主選單掃描，請在 fixture 旁註明（§7 規定）。
2. **主檔損毀（不是不見）時沒有後備**：`saveGet` 只在主檔**不存在**時才讀 `.bak1`。若主檔存在但壞掉，引擎判定 `corrupt` 重新開始，下一次存檔會把壞檔輪替成 `.bak1`，三次存檔後好的世代就被擠掉。這個缺口主要在引擎（我的）——見跟進 F3。
3. **安裝腳本沒有記錄安裝清單**：§9 的 T1 寫「記錄安裝清單」。目前版面固定、`-Uninstall` 恰好移除同一批路徑，實質滿足；請在腳本註解寫明「uninstall 移除的就是 install 加入的」，或我把規則改成這句（我傾向改規則）。
4. **除錯時鐘每次啟動從 0 開始**（`started = os.time()`）：重啟後時間倒退，已存的寵物時間戳會錯亂。只影響除錯流程，但請在文件的「已知限制」寫明（引擎端的處理見 F1）。
5. `sanitize()` 會讓不同 slot 碰撞（`a/b` 與 `a_b` 變成同一個檔名）。遊戲的真實 slot id 很可能不含這些字元，不急；找到真實 id（V3）時一併確認。

## 雲端這邊的跟進（我的領域）
| # | 工作 | 原因 |
|---|---|---|
| F1 | 引擎處理「時鐘倒退」：重載舊存檔或重啟時，`now < lastTick` 就把所有絕對時間戳（冷卻、`impoundedAt`、`notified`、`lastMisbehavior`、`adoptedAt`、`diedAt`）整體平移，並補測試 | **跨專案的設計風險**：mod 資料在遊戲存檔之外，玩家讀取較舊的遊戲存檔時，遊戲時間會比 mod 記錄的 `lastTick` 早；目前引擎會讓冷卻、收容所等待與「10 天後被領養」錯亂 |
| F2 | CI 加 `windows-latest` | M2③ |
| F3 | 評估選用函式 `saveGetBackup(key, n)`：引擎在 `corrupt` 時往較舊的世代讀 | nit 2；新增選用函式＝作者＋通知 |

## 下一步
- 作者處理 M1–M3（nit 自行裁量），在 `feat/ue4ss-adapter` 追加 commit；我只審差異。
- 合併後（squash）更新 `docs/compatibility.md`；`pawhome_verified_builds.txt` **仍不可加入 v0.11.0**，因為 caps 還沒有證據（M1-3b）。
- T2（M1-3a）需要使用者另外同意，且先照 `docs/qa/smoke-checklist.md` 備份存檔。


---

## 複審（`c3373b4`，只審差異）— **通過，已 squash 合併**

| 項目 | 結果 | 依據 |
|---|---|---|
| M1 預設強殺 | ✅ 已解決 | 預設不強殺：`CloseMainWindow` → 對所有可見視窗送 `WM_CLOSE`（等同點 X）→ 仍在跑就報告 `STILL RUNNING`；只有 `-ForceClose` 才 `Stop-Process`。PowerShell 語法檢查通過；視窗關閉的行為**在遊戲內未驗證**（本審查只能驗語法） |
| M2 驗證表過度宣稱 | ✅ 已解決 | 表拆成「首次寫出：已驗證（v0.10.0、v0.11.0）」「讀回既有存檔、`.bak` 輪替：**未驗證**」；`buildFingerprint`／安全模式因橫幅實際出現而改標「已驗證（v0.11.0）」，有依據；smoke 腳本新增「讀回」與「`.bak1` 雜湊＝上次存檔」兩項檢查，重跑會寫 `-runN` 結果檔 |
| M3 DEBUG 寫死 | ✅ 已解決 | 預設關閉，須有 `pawhome_debug.txt`；有測試證明「沒有旗標＝沒按鍵、沒時鐘、沒存檔」；smoke 腳本自己建立／移除旗標 |
| nit 1、3、4、5 | ✅ | fixture 註明觀測 build；install 註解寫明 uninstall 移除範圍；除錯時鐘改固定紀元並有「重啟後不倒退」的鑑別測試；sanitize 碰撞寫入已知限制 |
| 測試 | ✅ 104/104（Linux，CI 綠）；與我的 83 合併後 **109/109** | 測試包裝在失敗時也會還原被替換的全域函式（原本失敗會吃掉總結）——好的修正 |

**複審新增的 nit（不擋合併）**：①`WM_CLOSE` 等同使用者點 X，若有人在 T1 期間載入存檔，遊戲會依自己的方式處理關閉（可能問是否離開、或不儲存）。T1 期間**任何人都不應操作遊戲**，請寫進 `docs/qa/smoke-checklist.md` ②「`.bak1` 雜湊＝上次存檔」的檢查假設**一次執行只存檔一次**。除錯時鐘每 60 實際秒才換一個遊戲小時，腳本載入後約 25 秒就關閉，所以目前成立；若日後縮短間隔或拉長視窗，這個檢查會誤報失敗，請在腳本註解寫明。

**合併方式**：squash，衝突只在 `tests/run.lua`（兩邊各新增 suite），兩邊保留。CI 之後會第一次在 Windows 上跑它的 rotation 測試，若失敗再處理。

**仍有效的結論**：`pawhome_verified_builds.txt` **不可加入 v0.11.0**（caps 沒有證據）。下一個需要 PO 的事是**第二次 T1**（驗證讀回與輪替）與 **T2**。
