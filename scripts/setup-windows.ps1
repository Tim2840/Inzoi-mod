#Requires -Version 5.1
<#
  inZOI 寵物模組 — Windows 開發環境一鍵安裝

  用法（以「一般使用者」身分開 PowerShell 執行即可，winget 需要時會自己跳出系統管理員確認）：
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1

  參數：
    -SkipOptional   不安裝選用工具（Blender、Python 與桌面預覽用的 lupa）
    -SkipClone      不 clone 專案 repo（已經在 repo 裡執行時會自動略過）
    -RepoDir <路徑>  repo 要 clone 到哪裡（預設：文件\Inzoi-mod）

  這支腳本會：
    1. 用 winget 安裝 Git、VS Code、Steam、Epic Games Launcher、（選用）Blender、Python
    2. 安裝 Claude Code（官方安裝程式）
    3. clone 這個 repo 並切到開發分支
    4. 把 inZOI 的兩個 MCP 伺服器註冊到 Claude Code
    5. 開啟 Steam 的 inZOI 頁面和 Epic 的 ModKit 頁面（這兩個要登入帳號，只能你手動按安裝）
  重複執行也沒關係，已經裝好的東西會自動略過。
#>
param(
    [switch]$SkipOptional,
    [switch]$SkipClone,
    [string]$RepoDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Inzoi-mod')
)

# 原生指令（git/winget/claude）一律看 $LASTEXITCODE；PowerShell 5.1 在 'Stop' 模式下
# 重導向原生指令的 stderr 會直接拋例外，所以這裡用 'Continue'
$ErrorActionPreference = 'Continue'
$RepoUrl    = 'https://github.com/Tim2840/Inzoi-mod.git'
$RepoBranch = 'ccr-d0885a2d-yzygl2'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WingetPackage($id, $name) {
    winget list --id $id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$name 已經安裝"
        return
    }
    Write-Host "    安裝 $name ..."
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$name 安裝失敗（winget 回傳 $LASTEXITCODE），請之後手動安裝"
    } else {
        Write-Ok "$name 安裝完成"
    }
}

# ---------------------------------------------------------------- 0. 前置檢查
Write-Step '檢查 winget'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn '找不到 winget。請到 Microsoft Store 安裝或更新「應用程式安裝程式（App Installer）」後重新執行。'
    exit 1
}
Write-Ok 'winget 可以使用'

# ---------------------------------------------------------------- 1. 基本工具
Write-Step '安裝基本工具'
$packages = @(
    @{ Id = 'Git.Git';                     Name = 'Git' },
    @{ Id = 'Microsoft.VisualStudioCode';  Name = 'VS Code' },
    @{ Id = 'Valve.Steam';                 Name = 'Steam' },
    @{ Id = 'EpicGames.EpicGamesLauncher'; Name = 'Epic Games Launcher' }
)
if (-not $SkipOptional) {
    # 之後做寵物用品（床、玩具）的 3D 模型會用到
    $packages += @{ Id = 'BlenderFoundation.Blender'; Name = 'Blender（選用）' }
    # 桌面預覽和單元測試要用（pip install lupa）
    $packages += @{ Id = 'Python.Python.3.12'; Name = 'Python 3.12（選用）' }
}
foreach ($p in $packages) { Install-WingetPackage $p.Id $p.Name }
Update-SessionPath

# ---------------------------------------------------------------- 2. Claude Code
Write-Step '安裝 Claude Code'
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Ok 'Claude Code 已經安裝'
} else {
    Write-Host '    執行官方安裝程式 https://claude.ai/install.ps1 ...'
    try {
        Invoke-RestMethod https://claude.ai/install.ps1 -ErrorAction Stop | Invoke-Expression
    } catch {
        Write-Warn "下載 Claude Code 安裝程式失敗：$($_.Exception.Message)"
    }
    Update-SessionPath
    $localBin = Join-Path $HOME '.local\bin'
    if ((Test-Path $localBin) -and ($env:Path -notlike "*$localBin*")) { $env:Path += ";$localBin" }
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Ok 'Claude Code 安裝完成（第一次執行 claude 時需要登入）'
    } else {
        Write-Warn '安裝後還找不到 claude 指令，請重開 PowerShell 再執行一次這支腳本'
    }
}

# ---------------------------------------------------------------- 2b. 桌面預覽用的 lupa
if (-not $SkipOptional) {
    Write-Step '安裝 lupa（讓你不開遊戲也能預覽和跑測試）'
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -m pip install --quiet --upgrade lupa
        if ($LASTEXITCODE -eq 0) { Write-Ok 'lupa 安裝完成' } else { Write-Warn 'lupa 安裝失敗（不影響遊戲內開發，之後再手動 py -m pip install lupa）' }
    } else {
        Write-Warn '找不到 py 指令，Python 可能剛裝好。重開 PowerShell 後再執行一次這支腳本就會補上'
    }
}

# ---------------------------------------------------------------- 3. 專案 repo
Write-Step '準備專案 repo'
$inRepo = $false
if (Get-Command git -ErrorAction SilentlyContinue) {
    git -C $PSScriptRoot rev-parse --is-inside-work-tree *> $null
    $inRepo = ($LASTEXITCODE -eq 0)
}
if ($inRepo) {
    Write-Ok "已經在 repo 裡執行：$(Split-Path $PSScriptRoot -Parent)"
} elseif ($SkipClone) {
    Write-Warn '已略過 clone（-SkipClone）'
} elseif (Test-Path (Join-Path $RepoDir '.git')) {
    Write-Ok "repo 已經存在：$RepoDir"
} elseif (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn '找不到 git，請重開 PowerShell 後再執行一次'
} else {
    Write-Host "    clone 到 $RepoDir（私人 repo 會跳出 GitHub 登入視窗）"
    git clone --branch $RepoBranch $RepoUrl $RepoDir
    if ($LASTEXITCODE -eq 0) { Write-Ok 'clone 完成' } else { Write-Warn 'clone 失敗，請確認 GitHub 帳號有這個 repo 的權限' }
}

# ---------------------------------------------------------------- 4. MCP 伺服器
Write-Step '把 inZOI MCP 伺服器註冊到 Claude Code'
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $servers = @(
        @{ Name = 'inzoi-game';   Url = 'http://localhost:11212/mcp' },  # 遊戲開著時才連得到
        @{ Name = 'inzoi-modkit'; Url = 'http://localhost:11213/mcp' }   # ModKit 編輯器開著時才連得到
    )
    foreach ($s in $servers) {
        claude mcp get $s.Name *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$($s.Name) 已經註冊"
        } else {
            claude mcp add --transport http --scope user $s.Name $s.Url
            if ($LASTEXITCODE -eq 0) { Write-Ok "$($s.Name) -> $($s.Url)" } else { Write-Warn "$($s.Name) 註冊失敗" }
        }
    }
} else {
    Write-Warn '還沒有 claude 指令，先略過；裝好之後重新執行這支腳本就會補上'
}

# ---------------------------------------------------------------- 5. 需要登入帳號的部分
Write-Step '開啟遊戲和 ModKit 的安裝頁面（需要你手動登入並按安裝）'
Start-Process 'steam://install/2456740'                       # inZOI（Steam App ID 2456740）
Start-Process 'https://store.epicgames.com/p/inzoi-modkit'    # inZOI ModKit（免費）
Write-Ok '已開啟 Steam 和 Epic 商店頁面'

Write-Host @"

==================== 剩下要手動完成的步驟 ====================
 [ ] Steam：登入後安裝 inZOI（約 40-60 GB）
 [ ] Epic：登入後把「inZOI ModKit」加入收藏庫，再從 Epic Games Launcher 安裝
 [ ] 開一個新的 PowerShell，執行 claude 並登入
 [ ] （選用）py tools\preview_server.py 開桌面預覽
 [ ] 照 docs\setup-windows.md 的「驗證」一節確認 MCP 連得上
 [ ] 接著做 docs\phase0-probe.md 的可行性探勘
==============================================================
"@ -ForegroundColor White
