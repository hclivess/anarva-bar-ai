# Anarvā — a Skirmish AI for Beyond All Reason

Anarvā is built on BARb's C++ core (CircuitAI). It ships its own build of that core (BARb's source plus a
small patch that lets the scripts see the battlefield and adds a few switchable behaviours) and adds its own
AngelScript brain and configs on top. Full feature list with measured results: [FEATURES.md](../FEATURES.md).

## What it does differently from BARb

On by default (proven in testing):

- **Recycles obsolete economy.** Once fusion-tier power carries the base, it reclaims solars, winds,
  tidals and advanced solars, drops T1 metal makers after T2 makers arrive, and stops the core from
  rebuilding them. If energy ever collapses, cheap energy is allowed again.
- **Salvages obsolete T1 units.** Late in the game (advanced factory, good income), cheap T1 units
  idling at base are reclaimed for metal.
- **Hunts jammers.** Seen enemy jammers are treated as a hidden army, so weak squads avoid them and
  strong ones go in. A loss heatmap marks where we keep dying unseen and gets Dragon's Eye cameras. On
  jammer alert it sends air scouts and builds a Juno.
- **Strategic structures BARb never builds.** An anti-nuke the moment an enemy silo is seen. An EMP or
  tactical launcher placed forward, a late nuke only under its own anti-nuke cover, and shields over
  the most valuable infrastructure, all three only while its army is strong enough to afford them.
- **Recalls broken squads** so survivors regroup instead of trickling into the enemy.

Being tested (off by default until they win head-to-head): capability-based production with rez bots,
Director-sized attack waves, the scouting-driven constructor-vs-army split, the payback-based tech
gate, the moho energy gate, overflow handling, assist redirect and front fortification. See the status
table in the [main README](../README.md).
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

## Player names

BAR gives every AI a random name (the game's synced `ai_namer` gadget); an AI can't change it. The installers add
a small interface widget, **Anarva player names** (`LuaUI/Widgets/anarva_names.lua`), that shows Anarva's own names
for Anarva-controlled teams on your screen: Vritrasura, biong, fethar, PanHrnecPapinak, Liduric (in team order).
It only changes what your screen shows, so it can't desync a game; other players see BAR's names. If it doesn't
appear, allow custom widgets in BAR's settings and enable it in the widget list (F11).
