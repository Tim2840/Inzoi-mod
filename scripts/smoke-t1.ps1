# T1 smoke test (docs/engineering-workflow.md §7, §9): install the PawHome UE4SS mod,
# start inZOI, stay on the MAIN MENU, collect log evidence for V1 (injection + mod
# load) and V6 (save file written), close the game, and write a result file:
#   docs/qa/results/<date>-<FileVersion>.md
#
# Consent: T1 needs the PO's one-time consent for this game build. The script never
# clicks "Continue" or loads a save. It force-closes only if the window does not close
# within the grace period; pass -NoForceClose if a person may have loaded a save.
param(
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\inZOI',
    [int]$TimeoutSec = 240,
    [int]$GraceSec = 30,
    [switch]$SkipInstall,
    [switch]$NoForceClose
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$win64 = Join-Path $GameDir 'BlueClient\Binaries\Win64'
$exe = Join-Path $win64 'inZOI-Win64-Shipping.exe'
$ue4ssDir = Join-Path $win64 'ue4ss'
$modDir = Join-Path $ue4ssDir 'Mods\PawHome'
$logPath = Join-Path $ue4ssDir 'UE4SS.log'
$savePath = Join-Path $modDir 'pawhome_debug.pawhome.save.sav'
$processName = 'inZOI-Win64-Shipping'

# ---------------------------------------------------------------- preconditions
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { throw 'inZOI is already running; close it first.' }
if (-not (Test-Path $exe)) { throw "inZOI not found: $exe" }
if (-not (Test-Path (Join-Path $win64 'dwmapi.dll')) -or -not (Test-Path (Join-Path $ue4ssDir 'UE4SS.dll'))) {
    throw 'UE4SS is not installed (installing it is T3 and needs explicit PO consent).'
}
if (Test-Path (Join-Path $modDir 'pawhome_disabled.txt')) { throw 'Kill switch pawhome_disabled.txt is present; remove it first.' }

$exeItem = Get-Item $exe
$build = $exeItem.VersionInfo.FileVersion
$fingerprint = "size:$($exeItem.Length)"
Write-Host "Build $build ($fingerprint)"

if (-not $SkipInstall) { & (Join-Path $PSScriptRoot 'install-ue4ss.ps1') -GameDir $GameDir }

# ---------------------------------------------------------------- run
$started = Get-Date
$saveBefore = if (Test-Path $savePath) { (Get-Item $savePath).LastWriteTime } else { $null }
Start-Process 'steam://rungameid/2456740'

$deadline = $started.AddSeconds($TimeoutSec)
$sawProcess = $false; $loaded = $false; $saved = $false; $crashed = $false
while ((Get-Date) -lt $deadline) {
    $running = [bool](Get-Process -Name $processName -ErrorAction SilentlyContinue)
    if ($running) { $sawProcess = $true } elseif ($sawProcess) { $crashed = $true; break }
    if ((Test-Path $logPath) -and (Get-Item $logPath).LastWriteTime -gt $started) {
        $loaded = [bool](Select-String -Path $logPath -SimpleMatch '[PawHome] loaded' -Quiet)
    }
    if (Test-Path $savePath) {
        $t = (Get-Item $savePath).LastWriteTime
        $saved = ($t -gt $started) -and ($null -eq $saveBefore -or $t -gt $saveBefore)
    }
    if ($loaded -and $saved) { break }
    Start-Sleep -Seconds 5
}
# let it idle a little so late errors reach the log
if ($loaded -and $saved -and -not $crashed) { Start-Sleep -Seconds 20 }
$aliveAtEnd = [bool](Get-Process -Name $processName -ErrorAction SilentlyContinue)

# ---------------------------------------------------------------- close
$closeHow = 'not running'
$p = Get-Process -Name $processName -ErrorAction SilentlyContinue
if ($p) {
    $null = $p.CloseMainWindow()
    if ($p.WaitForExit($GraceSec * 1000)) {
        $closeHow = 'closed normally'
    } elseif ($NoForceClose) {
        $closeHow = 'STILL RUNNING (force close disabled; close it by hand)'
    } else {
        Stop-Process -Id $p.Id -Force
        $closeHow = 'force-closed at the main menu (no save was loaded by this script)'
    }
}

# ---------------------------------------------------------------- evidence
$lines = @()
if (Test-Path $logPath) { $lines = Get-Content $logPath -Encoding utf8 }
$header = $lines | Select-String -Pattern 'UE4SS - v|EngineVersion' | Select-Object -First 3 | ForEach-Object Line
$pawLines = $lines | Select-String -SimpleMatch '[PawHome]' | Select-Object -First 40 | ForEach-Object Line
$errLines = $lines | Select-String -Pattern '\[PawHome\].*(error|failed)' | Select-Object -First 20 | ForEach-Object Line
$banner = $pawLines | Where-Object { $_ -match '\[PawHome\] v' } | Select-Object -First 1

$v1 = $loaded -and -not $crashed
$v6 = $saved
$pass = $v1 -and $v6 -and $aliveAtEnd -and -not $errLines
function Mark($ok) { if ($ok) { 'PASS' } else { 'FAIL' } }
function Redact($s) { $s -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%' }

$resultsDir = Join-Path $repo 'docs\qa\results'
New-Item -ItemType Directory -Force $resultsDir | Out-Null
$result = Join-Path $resultsDir ("{0}-{1}.md" -f $started.ToString('yyyy-MM-dd'), $build)
$md = @"
# T1 smoke – $build – $($started.ToString('yyyy-MM-dd HH:mm'))

| Check | Result |
|---|---|
| Overall | **$(Mark $pass)** |
| V1 UE4SS injected and PawHome loaded | $(Mark $v1) |
| V6 save file written after start | $(Mark $v6) |
| Game still running at the end of the window (no crash) | $(Mark $aliveAtEnd) |
| No ``[PawHome]`` error lines | $(Mark (-not $errLines)) |

- Build: ``$build``, fingerprint ``$fingerprint``
- Close: $closeHow
- Script: ``scripts/smoke-t1.ps1`` (timeout ${TimeoutSec}s, main menu only, no save loaded)

## UE4SS header
``````
$(($header | ForEach-Object { Redact $_ }) -join "`n")
``````

## PawHome log lines
``````
$(($pawLines | ForEach-Object { Redact $_ }) -join "`n")
``````

## Error lines
``````
$(if ($errLines) { ($errLines | ForEach-Object { Redact $_ }) -join "`n" } else { '(none)' })
``````

Banner: $(if ($banner) { '``' + (Redact $banner) + '``' } else { '(not found)' })
"@
[IO.File]::WriteAllText($result, $md, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Result: $(Mark $pass) -> $result"
if (-not $pass) { exit 1 }
