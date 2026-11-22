# Installs Anarva into the BAR data dir, using the SkirmishAI.dll from the newest engine's BARb.
#   -Name AnarvaDev   installs a side-by-side copy under another shortName (for testing / A-B vs Anarva)
param(
    [string]$BarData = "C:\Hry\Beyond-All-Reason\data",
    [string]$Name = "Anarva",
    [string]$Flags = ""   # e.g. "F_PROD=false,F_SCALE=false" for A/B variants
)
$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "..\Anarva\stable"
$dst = Join-Path $BarData "AI\Skirmish\$Name\stable"

$engine = Get-ChildItem (Join-Path $BarData "engine") -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "AI\Skirmish\BARb\stable\SkirmishAI.dll") } |
    Sort-Object Name | Select-Object -Last 1
if (-not $engine) { throw "No engine with BARb found under $BarData\engine" }

if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Recurse -Force (Join-Path $src "*") $dst
Copy-Item -Force (Join-Path $engine.FullName "AI\Skirmish\BARb\stable\SkirmishAI.dll") $dst
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
