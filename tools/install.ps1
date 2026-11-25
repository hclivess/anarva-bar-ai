# Installs Anarva into the BAR data dir, using the SkirmishAI.dll from the newest engine's BARb.
#   -Name AnarvaDev   installs a side-by-side copy under another shortName (for testing / A-B vs Anarva)
param(
    [string]$BarData = "C:\Hry\Beyond-All-Reason\data",
    [string]$Name = "Anarva",
    [string]$Flags = "",  # e.g. "F_PROD=false,F_SCALE=false" for A/B variants
    [string]$Dll = ""     # custom-built SkirmishAI.dll (ref/build); default: the engine's BARb DLL
)
$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "..\Anarva\stable"
$dst = Join-Path $BarData "AI\Skirmish\$Name\stable"

$engine = Get-ChildItem (Join-Path $BarData "engine") -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "AI\Skirmish\BARb\stable\SkirmishAI.dll") } |
    Sort-Object Name | Select-Object -Last 1
if (-not $engine) { throw "No engine with BARb found under $BarData\engine" }

# A running game (or the lobby) holds the installed library open: removing the folder then deletes everything except
# the locked DLL and leaves a broken install (2026-11-25). Check the lock first and change nothing if it is held.
$oldDll = Join-Path $dst "SkirmishAI.dll"
if (Test-Path $oldDll) {
    try { $fs = [IO.File]::Open($oldDll, 'Open', 'ReadWrite', 'None'); $fs.Close() }
    catch { throw "$oldDll is in use (close Beyond All Reason, lobby included, and run again): nothing was changed" }
}
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Recurse -Force (Join-Path $src "*") $dst
if ($Dll) { Copy-Item -Force $Dll (Join-Path $dst "SkirmishAI.dll") }
else { Copy-Item -Force (Join-Path $engine.FullName "AI\Skirmish\BARb\stable\SkirmishAI.dll") $dst }
if ($Name -ne "Anarva") {
    $info = Join-Path $dst "AIInfo.lua"
    $text = [IO.File]::ReadAllText($info).Replace("value  = 'Anarva', -- AI name", "value  = '$Name', -- AI name") -replace "value  = 'Anarv[^']*',\r?\n(\s*desc   = 'human readable name)", "value  = '$Name',`n`$1"
    [IO.File]::WriteAllText($info, $text, (New-Object Text.UTF8Encoding($false)))
}
if ($Flags) {
    $brain = Join-Path $dst "script\anarva\misc\brain.as"
    $text = [IO.File]::ReadAllText($brain)
    foreach ($kv in $Flags.Split(",")) {
        $k, $v = $kv.Split("=")
        $new = [regex]::Replace($text, "const bool $k = (true|false);", "const bool $k = $v;")
        if ($new -eq $text) { throw "unknown flag $k" }
        $text = $new
    }
    [IO.File]::WriteAllText($brain, $text, (New-Object Text.UTF8Encoding($false)))
}
Write-Host "Installed $Name -> $dst (dll from $($engine.Name))"
