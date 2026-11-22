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

1. Copy the `stable` folder to `Beyond-All-Reason\data\AI\Skirmish\Anarva\stable\`.
   It must contain `SkirmishAI.dll`. If you got this without the DLL, copy it from
   `data\engine\<newest recoil>\AI\Skirmish\BARb\stable\SkirmishAI.dll`.
2. The BAR lobby only lists its built-in AIs by default. To show Anarvā:
   - create an empty file `Beyond-All-Reason\data\devmode.txt`
   - restart the lobby
   - open **Settings → Developer** and untick the **simple AI list** option.

   Anarvā then appears as **"Anarva stable"** in the Add AI list.
3. When the game engine updates, copy the new `SkirmishAI.dll` from the BARb folder again. The
   `tools\install.ps1` script does both steps for you.

## Playing online with friends

- Only the player who **adds** the Anarvā bot needs it installed. The AI runs on that player's PC, and
  its orders go to everyone else like normal player commands.
- That player must be **playing, not spectating**, and must stay in the game, or the AI stops.
- Keep exactly one version folder (`stable`). The lobby sends only the AI's name, not its version.
- Server rules (the autohost refusing unknown AI names, or the game being unranked) haven't been
  tested yet. Try a private custom battle first.
