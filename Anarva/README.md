# Anarvā — a Skirmish AI for Beyond All Reason

Anarvā is built on BARb's C++ core (CircuitAI). It reuses BARb's own `SkirmishAI.dll` and adds its own
AngelScript brain and configs on top.

## What it does differently from BARb

- **Massed attacks instead of trickling.** It sizes attack and raid gathering from its real army size,
  and recalls squads that have lost most of their strength. The survivors regroup and come back as part
  of a full wave, instead of walking into the enemy one at a time.
- **Recycles obsolete economy.** Once fusion-tier power carries the base, it reclaims solars, winds,
  tidals and advanced solars. Once 2+ advanced fusions carry the grid, it reclaims plain fusions, and it
  drops T1 metal makers after T2 makers arrive. It also stops the core from rebuilding any of them.
  If energy ever collapses, cheap energy is allowed again.
- **Salvages obsolete T1 units.** Late in the game (with an advanced factory and good income), cheap T1
  units idling at base are reclaimed for metal.
- **Hunts jammers.**
  - Seen enemy jammers are treated as a hidden army, so weak squads avoid them and strong ones go in.
  - A loss heatmap marks places where we keep dying unseen; it builds Dragon's Eye cameras there.
  - On jammer alert it gathers heavier, raises the scout quota, recruits air scouts and builds a Juno.
- **Strategic structures BARb never builds:**
  - an anti-nuke the moment an enemy silo is seen (or proactively when rich)
  - a Juno, as described above
  - an EMP or tactical missile launcher placed forward of the base
  - a late nuke, only once it has its own anti-nuke cover
  - shields placed over the most valuable uncovered infrastructure

## Install

1. Download `anarva-<version>-windows-x64.zip` or `anarva-<version>-linux-x64.tar.gz` from the
   [latest release](https://github.com/hclivess/anarva-bar-ai/releases/latest) and extract it.
2. Run the installer: double-click `install.cmd` on Windows, or run `./install.sh` on Linux. It finds
   your BAR data folder (or asks for it) and copies `Anarva/stable` to
   `data/AI/Skirmish/Anarva/stable/`. It also adds BARb's `SkirmishAI.dll` / `libSkirmishAI.so` from
   your newest engine (`data/engine/<newest recoil>/AI/Skirmish/BARb/stable/`).
3. The BAR lobby only lists its built-in AIs by default. To show Anarvā:
   - create an empty file `devmode.txt` in the BAR data folder (the installer offers to do this)
   - restart the lobby
   - open **Settings → Developer** and untick the **simple AI list** option.

   Anarvā then appears as **"Anarva stable"** in the Add AI list.
4. When the game engine updates, run the installer again to pick up the new library.
   `install.cmd -Uninstall` / `./install.sh --uninstall` removes Anarvā.

No installer? Copy the `stable` folder to `data/AI/Skirmish/Anarva/stable/` yourself and put the
library from the BARb folder above next to `AIInfo.lua`. Developers working from a checkout use
`tools/install.ps1`. Windows "not safe" warnings and the missing macOS build are explained in the
[main README](../README.md#windows-says-the-script-is-not-safe).

## Playing online with friends

- Only the player who **adds** the Anarvā bot needs it installed. The AI runs on that player's PC, and
  its orders go to everyone else like normal player commands.
- That player must be **playing, not spectating**, and must stay in the game, or the AI stops.
- Keep exactly one version folder (`stable`). The lobby sends only the AI's name, not its version.
- Server rules (the autohost refusing unknown AI names, or the game being unranked) haven't been
  tested yet. Try a private custom battle first.
