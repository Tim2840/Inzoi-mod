# Installs the Paw Home UE4SS mod into inZOI:
#   ue4ss\Mods\PawHome\Scripts\main.lua      (from mod\ue4ss\PawHome)
#   ue4ss\Mods\PawHome\Scripts\pawhome\...   (the engine, from mod\lua\pawhome)
# Requires UE4SS to be installed already (dwmapi.dll + ue4ss\ in Binaries\Win64).
# Save files (pawhome_*.sav) in the mod folder are left untouched.
param(
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\inZOI',
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (Get-Process -Name 'inZOI-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'inZOI is running; close the game first.'
}
$mods = Join-Path $GameDir 'BlueClient\Binaries\Win64\ue4ss\Mods'
if (-not (Test-Path $mods)) { throw "UE4SS not found at $mods; install UE4SS first." }
$target = Join-Path $mods 'PawHome'
$scripts = Join-Path $target 'Scripts'

if ($Uninstall) {
    if (Test-Path $scripts) { Remove-Item $scripts -Recurse -Force }
    Remove-Item (Join-Path $target 'enabled.txt') -ErrorAction SilentlyContinue
    Write-Host "Removed PawHome scripts from $target (save files kept)."
    return
}

if (Test-Path $scripts) { Remove-Item $scripts -Recurse -Force }
New-Item -ItemType Directory -Force $scripts | Out-Null
Copy-Item (Join-Path $repo 'mod\ue4ss\PawHome\Scripts\main.lua') $scripts
Copy-Item (Join-Path $repo 'mod\lua\pawhome') (Join-Path $scripts 'pawhome') -Recurse
Copy-Item (Join-Path $repo 'mod\ue4ss\PawHome\enabled.txt') $target -Force
Write-Host "PawHome installed -> $target"
