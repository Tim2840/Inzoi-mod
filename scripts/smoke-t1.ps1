# T1 smoke test (docs/engineering-workflow.md §7, §9): install the PawHome UE4SS mod,
# start inZOI, stay on the MAIN MENU, collect log evidence and write a result file:
#   docs/qa/results/<date>-<FileVersion>[-runN].md
#
# Checks: V1 (UE4SS injected + PawHome loaded), V6 (save file written after start) and,
# when a PawHome save already existed before the run, read-back ("started (loaded)")
# and backup rotation (the previous save survives, byte for byte, as one of .bak1-.bak3).
# Why not just .bak1, and why the check runs early: the mod saves more than once per run
# (on start, again on the first loop tick a second later, and on every game-hour change
# = every 60 real seconds with the debug clock). Each save rotates once, so the previous
# save moves down one generation per save and falls out after 3. The script therefore
# looks for it as soon as the first new save appears (at most a few seconds in, i.e. 2-3
# saves), not at the end of the run.
#
# Consent: T1 needs the PO's one-time consent for this game build. The script never
# clicks "Continue" or loads a save, but it cannot prove nobody else did, so it never
# kills the game by default: it asks every game window to close (like clicking X) and,
# if the game is still running after the grace period, reports it. Pass -ForceClose
# only when you are sure the game is on the main menu.
#
# Debug mode: the mod only has a clock (and therefore saves) in debug mode, so the
# script creates <Mod>\pawhome_debug.txt for the run and removes it again if it was
# not there before.
param(
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\inZOI',
    [int]$TimeoutSec = 240,
    [int]$GraceSec = 45,
    [switch]$SkipInstall,
    [switch]$ForceClose
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$win64 = Join-Path $GameDir 'BlueClient\Binaries\Win64'
$exe = Join-Path $win64 'inZOI-Win64-Shipping.exe'
$ue4ssDir = Join-Path $win64 'ue4ss'
$modDir = Join-Path $ue4ssDir 'Mods\PawHome'
$logPath = Join-Path $ue4ssDir 'UE4SS.log'
$savePath = Join-Path $modDir 'pawhome_debug.pawhome.save.sav'
$debugFlag = Join-Path $modDir 'pawhome_debug.txt'
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

$createdDebugFlag = $false
if (-not (Test-Path $debugFlag)) { New-Item -ItemType File $debugFlag | Out-Null; $createdDebugFlag = $true }

# ---------------------------------------------------------------- run
$hadSave = Test-Path $savePath
$hashBefore = if ($hadSave) { (Get-FileHash $savePath).Hash } else { $null }
$saveBefore = if ($hadSave) { (Get-Item $savePath).LastWriteTime } else { $null }
$started = Get-Date
Start-Process 'steam://rungameid/2456740'

function Find-PreviousGeneration {
    # which .bakN (1-3) holds the save that existed before the run, or $null
    foreach ($n in 1..3) {
        $bak = "$savePath.bak$n"
        if ((Test-Path $bak) -and ((Get-FileHash $bak).Hash -eq $hashBefore)) { return $n }
    }
    return $null
}

$deadline = $started.AddSeconds($TimeoutSec)
$sawProcess = $false; $loaded = $false; $saved = $false; $crashed = $false
$rotatedGen = $null; $rotationChecked = $false
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
    if ($saved -and $hadSave -and -not $rotationChecked) {
        $rotatedGen = Find-PreviousGeneration
        $rotationChecked = $true
    }
    if ($loaded -and $saved) { break }
    Start-Sleep -Seconds 2
}
# let it idle a little so late errors reach the log
if ($loaded -and $saved -and -not $crashed) { Start-Sleep -Seconds 20 }
$aliveAtEnd = [bool](Get-Process -Name $processName -ErrorAction SilentlyContinue)

# ---------------------------------------------------------------- close
Add-Type -Namespace PawHome -Name Win -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr hWnd, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr w, System.IntPtr l);
'@ -ErrorAction SilentlyContinue

function Close-AllWindows([int]$procId) {
    # WM_CLOSE to every visible top-level window of the process (game window and the
    # UE4SS console): the same request as clicking each window's X button.
    $sent = [System.Collections.Generic.List[IntPtr]]::new()
    $cb = [PawHome.Win+EnumProc]({
        param($h, $l)
        $wpid = [uint32]0
        [void][PawHome.Win]::GetWindowThreadProcessId($h, [ref]$wpid)
        if ($wpid -eq $procId -and [PawHome.Win]::IsWindowVisible($h)) {
            [void][PawHome.Win]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            $sent.Add($h)
        }
        return $true
    }.GetNewClosure())
    [void][PawHome.Win]::EnumWindows($cb, [IntPtr]::Zero)
    return $sent.Count
}

$closeHow = 'not running'
$p = Get-Process -Name $processName -ErrorAction SilentlyContinue
if ($p) {
    $null = $p.CloseMainWindow()
    if ($p.WaitForExit(15000)) {
        $closeHow = 'closed normally (main window)'
    } else {
        $null = Close-AllWindows $p.Id
        if ($p.WaitForExit($GraceSec * 1000)) {
            $closeHow = 'closed normally (WM_CLOSE to all windows)'
        } elseif ($ForceClose) {
            Stop-Process -Id $p.Id -Force
            $closeHow = 'force-closed (-ForceClose given; operator confirmed main menu)'
        } else {
            $closeHow = 'STILL RUNNING - did not close on request; not killed (no -ForceClose). Close it by hand.'
        }
    }
}
if ($createdDebugFlag -and -not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    Remove-Item $debugFlag -ErrorAction SilentlyContinue
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
# read-back and rotation can only be checked when a save existed before the run
$readBack = $null; $rotated = $null
if ($hadSave) {
    $readBack = [bool]($pawLines | Where-Object { $_ -match 'started \(loaded\)' })
    # checked as soon as the first new save appeared (see the header)
    $rotated = $null -ne $rotatedGen
}
$pass = $v1 -and $v6 -and $aliveAtEnd -and -not $errLines -and ($readBack -ne $false) -and ($rotated -ne $false)
function Mark($ok) { if ($null -eq $ok) { 'n/a (no save before this run)' } elseif ($ok) { 'PASS' } else { 'FAIL' } }
function Redact($s) { $s -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%' }

$resultsDir = Join-Path $repo 'docs\qa\results'
New-Item -ItemType Directory -Force $resultsDir | Out-Null
$base = "{0}-{1}" -f $started.ToString('yyyy-MM-dd'), $build
$result = Join-Path $resultsDir "$base.md"
$n = 2
while (Test-Path $result) { $result = Join-Path $resultsDir "$base-run$n.md"; $n++ }
$md = @"
# T1 smoke – $build – $($started.ToString('yyyy-MM-dd HH:mm'))

| Check | Result |
|---|---|
| Overall | **$(Mark $pass)** |
| V1 UE4SS injected and PawHome loaded | $(Mark $v1) |
| V6 save file written after start | $(Mark $v6) |
| Read back an existing save (``started (loaded)``) | $(Mark $readBack) |
| Backup rotation (previous save kept as ``.bak1``–``.bak3``, same hash) | $(Mark $rotated) |
| Game still running at the end of the window (no crash) | $(Mark $aliveAtEnd) |
| No ``[PawHome]`` error lines | $(Mark (-not $errLines)) |

- Build: ``$build``, fingerprint ``$fingerprint``
- Save before the run: $(if ($hadSave) { 'yes' } else { 'no' })$(if ($rotatedGen) { " (found as .bak$rotatedGen right after the first new save)" })
- Close: $closeHow
- Script: ``scripts/smoke-t1.ps1`` (timeout ${TimeoutSec}s, main menu only, no save loaded by the script)

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
Write-Host "Close: $closeHow"
if (-not $pass) { exit 1 }
