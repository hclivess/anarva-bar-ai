# Anarvā — a Skirmish AI for Beyond All Reason

Anarvā runs on its own build of BARb's C++ core (CircuitAI plus a patch that lets the scripts see the
battlefield) with its own AngelScript brain on top. Every decision is computed from the live game: no
dice, no fixed timers, no hand-picked thresholds. What it does: [FEATURES.md](../FEATURES.md). Where it
stands: [main README](../README.md#status-2026-11-25). It doesn't beat BARb hard yet; the rework is in
progress.

## Install

1. Download `anarva-<version>-windows-x64.zip` or `anarva-<version>-linux-x64.tar.gz` from the
   [latest release](https://github.com/hclivess/anarva-bar-ai/releases/latest) and extract it.
2. Run the installer: double-click `install.cmd` on Windows, or run `./install.sh` on Linux. It finds your
   BAR data folder (or asks for it) and copies `Anarva/stable` to `data/AI/Skirmish/Anarva/stable/`,
   including Anarvā's own core library (`SkirmishAI.dll` / `libSkirmishAI.so`). The scripts need that core,
   so BARb's stock library won't run them.
3. The BAR lobby only lists its built-in AIs by default. To show Anarvā:
   - Create an empty file `devmode.txt` in the BAR data folder (the installer offers to do this).
   - Restart the lobby.
   - Open **Settings → Developer** and untick the **simple AI list** option.

   Anarvā then appears as **"Anarva stable"** in the Add AI list.
4. `install.cmd -Uninstall` / `./install.sh --uninstall` removes Anarvā.

The core is built for the engine version it was released against. After a BAR engine update, install the
matching Anarvā release. Developers working from a checkout use `tools/install.ps1 -Dll <built core>`.
Windows "not safe" warnings and the missing macOS build are explained in the
[main README](../README.md#windows-says-the-script-is-not-safe).

## Playing online with friends

- Only the player who **adds** the Anarvā bot needs it installed. The AI runs on that player's PC, and its
  orders go to everyone else like normal player commands.
- That player must be **playing, not spectating**, and must stay in the game, or the AI stops.
- Keep exactly one version folder (`stable`). The lobby sends only the AI's name, not its version.
- Server rules (the autohost refusing unknown AI names, or the game being unranked) haven't been tested
  yet. Try a private custom battle first.

## Player names

BAR gives every AI a random name (the game's synced `ai_namer` gadget), and an AI can't change it. The installers add a
small interface widget, **Anarva player names** (`LuaUI/Widgets/anarva_names.lua`). It shows Anarvā's own names
for Anarvā-controlled teams on your screen: Vritrasura, biong, fethar, PanHrnecPapinak, Liduric (in team order).
It only changes what your screen shows, so it can't desync a game, and other players see BAR's names. If it doesn't
appear, allow custom widgets in BAR's settings and enable it in the widget list (F11).
