# Anarva installer for Windows.
#
# Copies Anarva\stable from this folder into <BAR data>\AI\Skirmish\Anarva\stable\ and adds the
# SkirmishAI.dll from the newest installed engine's BARb (Anarva runs on BARb's C++ core and does not
# ship its own copy, so the DLL always matches the engine your game uses).
#
#   install.cmd                                   find the BAR data folder and install
#   install.cmd "D:\Games\Beyond-All-Reason\data" install into that data folder
#   install.cmd -Uninstall                        remove Anarva again
#   install.cmd -DryRun                           print what would be done, change nothing
#
# Run it again after BAR updates its engine, to pick up the new SkirmishAI.dll.
param(
    [Parameter(Position = 0)]
    [string]$BarData = "",
    [switch]$Uninstall,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$AiName = "Anarva"
$LibName = "SkirmishAI.dll"

function Write-Step([string]$text) {
    if ($DryRun) { Write-Host "[dry run] would $text" } else { Write-Host $text }
}

function Get-NaturalKey([string]$name) {
    # recoil_2026.9.3 sorts after recoil_2026.10.1 as plain text; pad every number so it does not
    [regex]::Replace($name, '\d+', { param($m) $m.Value.PadLeft(12, '0') })
}

function Test-BarData([string]$dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath (Join-Path $dir "engine") -PathType Container)) { return $false }
    $engines = @(Get-ChildItem -LiteralPath (Join-Path $dir "engine") -Directory -Filter "recoil_*" -ErrorAction SilentlyContinue)
    return $engines.Count -gt 0
}

function Find-BarData {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason\data")) }
    if ($env:USERPROFILE) { $candidates.Add((Join-Path $env:USERPROFILE "Documents\My Games\Beyond All Reason")) }
    $candidates.Add("C:\Program Files\Beyond-All-Reason\data")
    # Cheap scan of fixed drives: X:\Beyond-All-Reason\data and X:\<one folder>\Beyond-All-Reason\data
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) { continue }
        $root = $drive.RootDirectory.FullName
        $candidates.Add((Join-Path $root "Beyond-All-Reason\data"))
        foreach ($sub in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $candidates.Add((Join-Path $sub.FullName "Beyond-All-Reason\data"))
        }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($c in $candidates) {
        if (-not (Test-BarData $c)) { continue }
        $full = (Resolve-Path -LiteralPath $c).ProviderPath.TrimEnd('\')
        if (-not ($found | Where-Object { $_ -ieq $full })) { $found.Add($full) }
    }
    return ,$found
}

function Read-BarDataPath([string]$reason) {
    Write-Host $reason
    Write-Host "The BAR data folder is the one that contains the 'engine', 'maps' and 'games' folders,"
    Write-Host "for example C:\Users\<you>\AppData\Local\Programs\Beyond-All-Reason\data"
    while ($true) {
        $answer = (Read-Host "Path to the BAR data folder (empty to cancel)").Trim().Trim('"')
        if (-not $answer) { throw "Cancelled: no BAR data folder given." }
        if (Test-BarData $answer) { return (Resolve-Path -LiteralPath $answer).ProviderPath.TrimEnd('\') }
        Write-Host "'$answer' has no engine\recoil_* folder, so it is not a BAR data folder. Try again."
    }
}

function Select-BarData {
    if ($BarData) {
        if (-not (Test-BarData $BarData)) {
            throw "'$BarData' is not a BAR data folder: it has no engine\recoil_* folder."
        }
        return (Resolve-Path -LiteralPath $BarData).ProviderPath.TrimEnd('\')
    }
    $found = Find-BarData
    if ($found.Count -eq 1) {
        Write-Host "Found the BAR data folder: $($found[0])"
        return $found[0]
    }
    if ($found.Count -eq 0) {
        return Read-BarDataPath "Could not find the Beyond All Reason data folder in the usual places."
    }
    Write-Host "Found several BAR data folders:"
    for ($i = 0; $i -lt $found.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $found[$i]) }
    while ($true) {
        $answer = (Read-Host "Number of the one to use, or a full path").Trim().Trim('"')
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $found.Count) { return $found[$n - 1] }
        if ($answer -and (Test-BarData $answer)) { return (Resolve-Path -LiteralPath $answer).ProviderPath.TrimEnd('\') }
        Write-Host "Not a number from the list or a BAR data folder: '$answer'"
    }
}

function Find-Engine([string]$data) {
    $engines = Get-ChildItem -LiteralPath (Join-Path $data "engine") -Directory -Filter "recoil_*" |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "AI\Skirmish\BARb\stable\$LibName") -PathType Leaf } |
        Sort-Object { Get-NaturalKey $_.Name }
    $newest = @($engines) | Select-Object -Last 1
    if (-not $newest) {
        throw "No engine under $data\engine has AI\Skirmish\BARb\stable\$LibName. Start BAR once so it downloads an engine, then run this again."
    }
    return $newest
}

function Show-LobbyHelp([string]$data) {
    $devmode = Join-Path $data "devmode.txt"
    Write-Host ""
    Write-Host "To see Anarva in the lobby (it lists only its built-in AIs by default):"
    Write-Host "  1. create an empty file $devmode"
    Write-Host "  2. restart the BAR lobby"
    Write-Host "  3. Settings > Developer > untick 'simple AI list'"
    Write-Host "Anarva then appears as 'Anarva stable' in the Add AI list."
    Write-Host ""
    if (Test-Path -LiteralPath $devmode) {
        Write-Host "devmode.txt already exists, so step 1 is done."
        return
    }
    if ($DryRun) {
        Write-Host "[dry run] would offer to create $devmode (y/n)"
        return
    }
    $answer = (Read-Host "Create devmode.txt now? (y/n)").Trim().ToLowerInvariant()
    if ($answer -eq "y" -or $answer -eq "yes") {
        New-Item -ItemType File -Path $devmode | Out-Null
        Write-Host "Created $devmode"
    } else {
        Write-Host "devmode.txt not created. Do step 1 yourself if Anarva does not show up."
    }
}

function Install-Anarva([string]$data) {
    $src = Join-Path $PSScriptRoot "$AiName\stable"
    if (-not (Test-Path -LiteralPath (Join-Path $src "AIInfo.lua") -PathType Leaf)) {
        throw "This installer must sit next to the '$AiName' folder from the release archive (missing $src\AIInfo.lua). Extract the whole archive first."
    }
    $engine = Find-Engine $data
    $lib = Join-Path $engine.FullName "AI\Skirmish\BARb\stable\$LibName"
    $aiRoot = Join-Path $data "AI\Skirmish\$AiName"
    $dst = Join-Path $aiRoot "stable"
    $tmp = Join-Path $aiRoot "stable.installing"
    $files = @(Get-ChildItem -LiteralPath $src -Recurse -File)

    Write-Host "BAR data folder: $data"
    Write-Host "Newest engine with BARb: $($engine.Name)"
    if (Test-Path -LiteralPath $tmp) { Write-Step "remove leftover $tmp"; if (-not $DryRun) { Remove-Item -LiteralPath $tmp -Recurse -Force } }
    Write-Step "copy $($files.Count) files from $src to $tmp"
    Write-Step "copy $lib to $tmp\$LibName"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        Copy-Item -Path (Join-Path $src "*") -Destination $tmp -Recurse -Force
        Copy-Item -LiteralPath $lib -Destination (Join-Path $tmp $LibName) -Force
        $copied = @(Get-ChildItem -LiteralPath $tmp -Recurse -File).Count
        if ($copied -ne $files.Count + 1) { throw "Copy incomplete: expected $($files.Count + 1) files in $tmp, found $copied." }
    }
    if (Test-Path -LiteralPath $dst) {
        Write-Step "remove the previous install $dst"
        if (-not $DryRun) { Remove-Item -LiteralPath $dst -Recurse -Force }
    }
    Write-Step "rename $tmp to $dst"
    if (-not $DryRun) { Rename-Item -LiteralPath $tmp -NewName "stable" }
    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run finished: nothing was changed."
    } else {
        Write-Host "Installed $AiName into $dst ($($files.Count) files + $LibName from $($engine.Name))."
        Write-Host "Run this installer again after BAR updates its engine."
    }
    Show-LobbyHelp $data
}

function Uninstall-Anarva([string]$data) {
    $aiRoot = Join-Path $data "AI\Skirmish\$AiName"
    if (-not (Test-Path -LiteralPath $aiRoot)) {
        Write-Host "$AiName is not installed in $data (no $aiRoot). Nothing to do."
        return
    }
    Write-Step "remove $aiRoot"
    if (-not $DryRun) {
        Remove-Item -LiteralPath $aiRoot -Recurse -Force
        Write-Host "Uninstalled $AiName."
    }
    $devmode = Join-Path $data "devmode.txt"
    if (Test-Path -LiteralPath $devmode) {
        Write-Host "$devmode was left in place; delete it yourself if no other AI or tool needs developer mode."
    }
}

try {
    if ($DryRun) { Write-Host "Dry run: nothing will be changed." }
    $data = Select-BarData
    if ($Uninstall) { Uninstall-Anarva $data } else { Install-Anarva $data }
    exit 0
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
