# Windows 安裝教學（保姆級）

> 全程約 **1–2 小時**，其中大部分是在等 Steam 和 Epic 下載。你只需要照著點、照著貼。
> 文字裡的 `這種格式` 就是要**整行複製貼上**到 PowerShell 的指令。
> 我沒辦法在你的電腦上操作，所以 Steam／Epic／Claude 的畫面文字可能和我寫的略有不同，意思一樣就好。

## 全部步驟一覽

| # | 做什麼 | 要自己點嗎 | 時間 |
|---|---|---|---|
| 0 | 檢查電腦和帳號 | 要 | 5 分鐘 |
| 1 | 打開 PowerShell | 要 | 1 分鐘 |
| 2 | 貼兩行指令，**自動安裝大部分工具** | 貼上就好 | 10–20 分鐘 |
| 3 | Steam 安裝 inZOI | 要 | 等下載 |
| 4 | Epic 安裝 inZOI ModKit | 要 | 等下載 |
| 5 | 登入 Claude Code | 要 | 3 分鐘 |
| 6 | 驗證全部都裝好了 | 要 | 5 分鐘 |
| 7 | （選用）桌面預覽 | 貼上就好 | 3 分鐘 |

---

## 步驟 0：先確認這幾件事

**電腦**（ModKit 最低需求，Epic 商店頁面）

- Windows 10 或 11
- 記憶體 **12 GB** 以上
- 顯示卡 RTX 2060 / RX 5600 XT（6 GB 顯存）以上
- **硬碟剩餘 120 GB 以上**（遊戲 + ModKit + 工具）

查硬碟空間：打開「檔案總管」→ 左邊點「本機」→ 看 C: 槽剩下多少。

**帳號**（沒有的先去註冊，都免費）

| 帳號 | 用在哪 |
|---|---|
| Steam | 下載 inZOI 遊戲（你應該已經買了遊戲） |
| Epic Games | 免費領取 inZOI ModKit |
| Claude | 登入 Claude Code，讓它直接連進遊戲幫你寫和測模組（需要有 Claude Code 使用權限的方案） |

---

## 步驟 1：打開 PowerShell

1. 在畫面左下角的 **開始鈕**（Windows 圖示）上按**滑鼠右鍵**。
2. 選「**終端機**」（Windows 11）或「**Windows PowerShell**」（Windows 10）。
   - ⚠️ **不要選「系統管理員」那一個**。一般的就好，需要權限時它會自己跳出確認視窗。
3. 會跳出一個黑色（或藍色）的視窗，裡面有一行文字結尾是 `>`，這就是 PowerShell。

先測試 winget（Windows 內建的安裝工具）能不能用，貼上這行再按 Enter：

```powershell
winget --version
```

- ✅ 看到 `v1.x.x` 這樣的版本號 → 繼續。
- ❌ 說「找不到 winget」→ 打開 **Microsoft Store**，搜尋「**應用程式安裝程式**」（App Installer），按「更新」，更新完**重開 PowerShell** 再試一次。

> 💡 怎麼貼上：在 PowerShell 視窗裡**按滑鼠右鍵**就是貼上（不用 Ctrl+V）。貼完按 **Enter** 執行。

---

## 步驟 2：貼兩行指令，自動安裝

### 2-1 下載安裝腳本

貼上下面這**一整行**，按 Enter：

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tim2840/Inzoi-mod/ccr-d0885a2d-yzygl2/scripts/setup-windows.ps1" -OutFile "$env:TEMP\setup-pawhome.ps1"
```

沒有任何紅字、直接回到 `>` 就是成功。

### 2-2 執行安裝腳本

貼上這一整行，按 Enter：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:TEMP\setup-pawhome.ps1" -RepoDir "C:\Dev\Inzoi-mod"
```

接下來會發生什麼事：

1. 畫面會依序出現青色的 `==>` 標題，例如「安裝基本工具」。
2. 安裝 Git、VS Code、Steam、Epic Games Launcher 等的時候，**螢幕可能會閃一下並跳出「是否允許此應用程式變更您的裝置？」**，請按「**是**」。
3. 每個東西裝好會出現綠色的 `[OK]`。已經裝過的會顯示「已經安裝」並自動跳過，不用擔心。
4. 它會把專案下載到 `C:\Dev\Inzoi-mod`（**這就是你之後的工作資料夾**）。
5. 最後它會**自動打開 Steam 和 Epic 的網頁**，並印出一份「剩下要手動完成的步驟」清單。

整個過程約 10–20 分鐘，請耐心等它跑完（回到 `>` 並出現那份清單才算結束）。

看到**黃色的 `[!]`** 不用慌，那是警告，不一定是失敗：

| 黃字訊息 | 怎麼辦 |
|---|---|
| `找不到 claude 指令` / `找不到 git` | 新裝的程式要重開視窗才找得到。**關掉 PowerShell、重開一個**，再貼一次 2-2 那行（會自動跳過裝好的，只補缺的） |
| `某某 安裝失敗（winget 回傳 …）` | 再貼一次 2-2 的指令重試；還是失敗就把那行文字複製給我 |
| `lupa 安裝失敗` | 只影響桌面預覽，先跳過，之後做步驟 7 時再處理 |

---

## 步驟 3：Steam 安裝 inZOI

1. 腳本跑完時，**Steam 應該已經跳出一個安裝 inZOI 的視窗**。如果有 → 登入 Steam，按「**安裝**」。
2. 如果沒有跳出來：打開 **Steam** → 登入 → 左上「**庫存**」→ 找到 **inZOI** → 按「**安裝**」。
3. 選好安裝位置（空間夠的磁碟）→ 下載。**約 40–60 GB**，網路慢的話可以去吃飯。
4. 下載完成後按一次「**開始遊戲**」，確認能進到主畫面，然後先關掉。

---

## 步驟 4：Epic 安裝 inZOI ModKit

ModKit 是官方的模組編輯器，**免費**，是用 Epic 發的。

1. 腳本應該已經用瀏覽器打開了 **inZOI ModKit 的 Epic 商店頁面**。如果沒有，自己開：
   https://store.epicgames.com/p/inzoi-modkit
2. 登入你的 Epic 帳號 → 按「**取得**」（Get）→ 照畫面完成「訂單」（價格是 $0，不會扣錢）。
3. 打開 **Epic Games Launcher**（開始選單搜尋 `Epic Games Launcher`）→ 登入。
4. 左邊點「**庫**」（Library）→ 找到 **inZOI ModKit** → 按「**安裝**」→ 等下載。
5. 如果庫裡沒看到：確認右上角登入的是**剛才領取的那個帳號**，再按重新整理或重開 Launcher。

---

## 步驟 5：登入 Claude Code

1. **關掉所有 PowerShell，重新開一個**（一般的，不是系統管理員）。
2. 貼上並按 Enter：
   ```powershell
   cd C:\Dev\Inzoi-mod
   claude
   ```
3. 第一次執行會要求選擇外觀、並**跳出瀏覽器請你登入 Claude 帳號** → 登入並按允許。
4. 回到 PowerShell，看到可以輸入文字的對話框就代表成功了。先輸入 `/exit` 按 Enter 離開。

---

## 步驟 6：驗證（重要）

### 6-1 確認 inZOI 的兩條「連線」都註冊好了

在 PowerShell 貼上：

```powershell
claude mcp list
```

應該會看到兩行：

```
inzoi-game: http://localhost:11212/mcp ...
inzoi-modkit: http://localhost:11213/mcp ...
```

這時它們很可能顯示「**Failed to connect**」或打叉，**這是正常的**，因為遊戲和 ModKit 都還沒開。

### 6-2 開遊戲，再檢查一次

1. 從 Steam 啟動 **inZOI**，進入任意一個存檔，**停在遊戲畫面上不要關**。
2. 回到 PowerShell 再貼一次 `claude mcp list`。
   - ✅ `inzoi-game` 變成 **Connected**（綠勾）→ 成功！
   - ❌ 還是連不上 → 看下面的「常見問題」。

### 6-3 開 ModKit，再檢查一次

1. 從 **Epic Games Launcher** 啟動 **inZOI ModKit**（第一次開會很久，是 Unreal 在編譯，正常）。
2. 再貼一次 `claude mcp list` → `inzoi-modkit` 也變成 **Connected**。

> 兩個都綠勾，就代表 Claude 已經能「看見」你的遊戲和編輯器了。

---

## 步驟 7：（選用）不開遊戲，先玩玩看寵物

這一步用**電腦上的 Python** 跑我寫的寵物引擎，不需要開遊戲。

```powershell
cd C:\Dev\Inzoi-mod
py -I tests\run.py
```

看到 **`62 passed, 0 failed`** 就代表引擎在你的電腦上也運作正常。接著：

```powershell
py tools\preview_server.py
```

- 它會印出一行網址 `http://127.0.0.1:8765/?preview=1`，**用瀏覽器打開**。
- 試試看：「領養寵物」→ 領養一隻 → 點「餵食」「玩耍」→ 最下面的「預覽工具」按 `+1d` 快轉一天，看貓的狀態變化。
- 要關掉：回到 PowerShell 按 **Ctrl + C**。

---

## 常見問題

| 狀況 | 原因與解法 |
|---|---|
| 貼上後出現紅字「無法載入檔案…因為這個系統上已停用指令碼執行」 | 你少打了 `-ExecutionPolicy Bypass`。請**整行**複製 2-2 的指令，不要只複製一部分 |
| 步驟 2-1 紅字「無法連線到遠端伺服器」 | 網路問題或公司／學校網路擋住 GitHub。換手機熱點試試 |
| 「`claude` 不是可辨識的 Cmdlet」 | 新裝的程式要**重開 PowerShell** 才找得到。還是不行就貼 `$env:Path += ";$HOME\.local\bin"` 再試 |
| 「`git` 不是可辨識的…」 | 同上，重開 PowerShell。再不行就重貼 2-2 |
| 「`py` 不是可辨識的…」 | Python 剛裝好，重開 PowerShell；再不行重貼 2-2 |
| `claude mcp list` 的 `inzoi-game` 一直連不上，遊戲明明開著 | ① 確認**已經進到存檔裡**，不是停在主選單 ② 11212 埠可能被別的程式占用：到 Steam → inZOI → **右鍵 → 內容 → 啟動選項**，貼上 `-climcpport=11300`，重開遊戲，然後在 PowerShell 貼 `claude mcp remove inzoi-game` 再貼 `claude mcp add --transport http --scope user inzoi-game http://localhost:11300/mcp` ③ 還是不行，把 `claude mcp list` 的整段輸出貼給我 |
| Epic 庫裡找不到 ModKit | 確認登入的是領取它的那個 Epic 帳號；到商店頁面看是不是顯示「已在庫中」 |
| ModKit 第一次開啟卡在某個百分比很久 | 正常，第一次要編譯著色器，可能要 10–30 分鐘，不要強制關閉 |
| 想從頭重來 | 直接重貼 2-2，腳本重複執行很安全，已經裝好的會自動跳過 |

---

## 完成檢查表

- [ ] `winget --version` 看得到版本號
- [ ] 腳本跑完，出現「剩下要手動完成的步驟」清單
- [ ] `C:\Dev\Inzoi-mod` 資料夾存在，裡面有 `README.md`
- [ ] inZOI 能從 Steam 開起來
- [ ] ModKit 能從 Epic Games Launcher 開起來
- [ ] `claude` 能開啟並已登入
- [ ] 遊戲開著時，`claude mcp list` 的 `inzoi-game` 是 Connected
- [ ] ModKit 開著時，`inzoi-modkit` 是 Connected
- [ ] （選用）`py -I tests\run.py` 顯示 `62 passed, 0 failed`

## 下一步

全部打勾後，進入 [`phase0-probe.md`](phase0-probe.md)：**一邊開著遊戲和 ModKit，在 `C:\Dev\Inzoi-mod` 裡輸入 `claude`**，然後把裡面每題的「給 Claude Code 的指令」貼給它，做完把結果表貼給我。

**卡住的時候**請把這三樣貼給我：① 你在哪一步 ② 畫面上的完整文字（紅字或黃字複製下來）③ 步驟 6 的 `claude mcp list` 輸出。
