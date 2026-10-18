# Windows 開發環境安裝

> 我（Claude）在雲端容器裡沒辦法碰到你的電腦，所以把所有能自動化的步驟都寫成一支腳本 `scripts/setup-windows.ps1`。只有**需要登入帳號**的兩件事（Steam 安裝 inZOI、Epic 領取 ModKit）一定要你自己按。

## 需要準備的東西

| 項目 | 用途 | 安裝方式 |
|---|---|---|
| inZOI（Steam） | 遊戲本體，測試模組用 | 腳本會開啟安裝頁面，你登入後按安裝 |
| inZOI ModKit（Epic，免費） | 官方模組編輯器（UE5），用來寫 Lua、打包、上傳 CurseForge | 腳本會開啟商店頁面，你領取後在 Epic Launcher 安裝 |
| Epic Games Launcher | 安裝 ModKit 用 | ✅ 腳本自動安裝 |
| Git | 版本控制、同步這個 repo | ✅ 腳本自動安裝 |
| VS Code | 編輯 Lua、HTML、JSON | ✅ 腳本自動安裝 |
| Claude Code | 透過 MCP 連進遊戲和 ModKit，讓我直接幫你寫和測試 | ✅ 腳本自動安裝（官方安裝程式） |
| Blender（選用） | 之後做寵物用品（貓床、玩具）的 3D 模型 | ✅ 腳本自動安裝（加 `-SkipOptional` 可以略過） |

**硬體需求（ModKit，Epic 商店頁面）**：Windows 10/11、i5-10400 或 Ryzen 5 3600、**12 GB RAM**、RTX 2060 或 RX 5600 XT（6 GB VRAM）、DirectX 12。硬碟空間：ModKit 40–60 GB，加上遊戲本體，**建議預留 120 GB 以上**。

## 步驟

### 1. 取得腳本

方法 A（推薦）：先裝 Git 再 clone。在 PowerShell 輸入：

```powershell
winget install --id Git.Git -e
# 重開 PowerShell
git clone --branch ccr-d0885a2d-yzygl2 https://github.com/Tim2840/Inzoi-mod.git "$HOME\Documents\Inzoi-mod"
cd "$HOME\Documents\Inzoi-mod"
```

方法 B：在 GitHub 網頁切到 `ccr-d0885a2d-yzygl2` 分支，按 **Code → Download ZIP**，解壓縮後在那個資料夾開 PowerShell。

### 2. 執行安裝腳本

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

- 用一般 PowerShell 執行就可以，winget 需要權限時會自己跳出 UAC 視窗。
- 如果出現「找不到 claude」之類的警告，**重開 PowerShell 再執行一次**就好（新裝的程式要重開視窗才會進 PATH）。腳本重複執行很安全。

### 3. 手動完成（腳本最後也會列出來）

1. **Steam**：登入後安裝 inZOI。
2. **Epic**：在已經打開的商店頁面按「取得」，接著到 Epic Games Launcher 的「收藏庫」安裝 **inZOI ModKit**。
3. 開新的 PowerShell，輸入 `claude` 並登入你的 Claude 帳號。

### 4. 驗證

1. 啟動 inZOI，進入任意存檔。
2. 在 repo 資料夾開 PowerShell，執行 `claude mcp list`，應該會看到：
   - `inzoi-game: http://localhost:11212/mcp ✓ Connected`
   - `inzoi-modkit` 要等 ModKit 編輯器打開才會顯示 Connected
3. 如果 11212 埠被占用：在 Steam 的 inZOI → 內容 → 啟動選項加上 `-climcpport=11300`，然後執行：
   ```powershell
   claude mcp remove inzoi-game
   claude mcp add --transport http --scope user inzoi-game http://localhost:11300/mcp
   ```

全部連上之後，就可以進行 [`phase0-probe.md`](phase0-probe.md) 的可行性探勘。
