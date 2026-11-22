# Anarvā — a smarter Skirmish AI for Beyond All Reason

Anarvā runs on BARb's C++ core (CircuitAI) and adds its own AngelScript brain and configs. Its rule is
**no static thresholds**: every choice compares the live marginal value of the alternatives, worked out
from game facts (unit costs, upkeep, converter rates) and live measurements (force ratio, trade
efficiency, front movement, income growth, overflow).

What it does:

- **Director.** Works out the army power needed to win, from the scouted enemy army plus the army we
  guess is hidden under jammers, divided by how efficiently we're trading. It sizes attack waves to
  that, and splits production between constructors and army from the surplus or deficit. It only cuts
  the economy when pushed back at home.
- **Assessment.** Tracks whether we're pushing or being pushed back, how well we trade, and whether
  the economy is still growing.
- **Economist.** Prices energy in metal at the converter rate. Investments (T2, moho upgrades) are
  judged by payback time against a planning horizon set by how safe we are.
- **Production.** Picks each unit from its live abilities (damage against air, surface and
  underwater, health, range, speed, cost) against the scouted enemy mix, plus a screening value against
  heavy armies. It builds rez bots while the wreck pool from recent fights is worth more than the rez
  fleet.
- **Waves and recall.** Squads gather until they can win, then launch together. A squad that's no
  longer winning comes home to regroup instead of trickling in.
- **Economy:**
  - recycles obsolete eco: solars and winds, then fusions once advanced fusions carry the grid, T1
    makers, and idle T1 units late in the game
  - gates moho upgrades on energy headroom
  - spends overflowing metal through nanos and assists, and converts overflowing energy with makers
- **Intel:**
  - keeps real sight with continuous scouting, because radar dots carry no type
  - treats seen jammers as a hidden army
  - builds Dragon's Eyes where we die unseen, and a Juno against jammers
- **Strategic:**
  - anti-nuke when an enemy silo appears
  - a tactical or EMP launcher placed forward
  - a nuke once our anti-nuke covers us
  - shields over the most valuable infrastructure
  - anti-air scaled to the air we've seen
  - turrets and dragon's teeth at contested fronts when outgunned

**Goal:** one Anarvā beats six BARb (hard) opponents on every map type.

**Honest status:** the first build beat BARb-hard 7-3 in 1v1, mostly on points. The bundle of new
modules added since then lost 3-8, mainly because the economy starved. Every module now sits behind a
feature flag and is being A/B-tested head-to-head against the first build. A module ships only if it
measurably helps. Details are in [PROGRESS.md](PROGRESS.md), [progress.json](progress.json) and
[STRATEGY.md](STRATEGY.md), which maps every principle (Sun Tzu, Clausewitz, Napoleon, top-player
replay data) to the code that implements it.

## Install

You need Beyond All Reason installed and started at least once (so it has downloaded an engine).

### From a release (recommended)

1. Download the archive for your OS from the [latest release](https://github.com/hclivess/anarva-bar-ai/releases/latest):
   - Windows: `anarva-<version>-windows-x64.zip`
   - Linux: `anarva-<version>-linux-x64.tar.gz`
2. Extract it. Don't run the installer from inside the zip.
3. Run the installer:
   - Windows: double-click `install.cmd`.
   - Linux: run `./install.sh` in a terminal.

   It finds your BAR data folder. If it finds several, or none, it asks you for one, and you can also
   pass the path as an argument. It copies `Anarva/stable` there and adds BARb's `SkirmishAI.dll` /
   `libSkirmishAI.so` from your newest engine. Anarvā runs on that library and doesn't ship its own,
   so it always matches your game. Every step is printed.
4. The lobby lists only its built-in AIs by default. To show Anarvā, create an empty `devmode.txt` in
   the data folder (the installer offers to do it), restart the lobby, then open
   **Settings → Developer** and untick **simple AI list**. Anarvā appears as **"Anarva stable"**.

Run the installer again after BAR updates its engine. Remove the AI with `install.cmd -Uninstall` or
`./install.sh --uninstall`. Add `-DryRun` / `--dry-run` to see what it would do without changing
anything.

### From source (developers)

`tools/install.ps1 -BarData <data folder>` copies the working tree's `Anarva/stable` and the newest
engine's DLL. Use `-Name AnarvaDev` for a side-by-side test copy. To build the release archives
yourself, run `python build.py`. It self-tests the configs, `#include`s and profiles, then writes
`dist/` (`python build.py --selftest` runs only the checks).

### Windows says the script is not safe

The installer is a plain, unsigned script, so Windows may warn about it.

- **SmartScreen "Windows protected your PC"**: click **More info → Run anyway**.
- **Downloaded-file block**: the zip carries the mark of the web. Unblock it before extracting, either
  with Properties → **Unblock**, or in PowerShell:
  `Unblock-File .\anarva-<version>-windows-x64.zip`
- **Check the download is ours**: compare
  `Get-FileHash .\anarva-<version>-windows-x64.zip -Algorithm SHA256` with the `.sha256` file published
  next to it on the release page. On Linux, run `sha256sum -c anarva-<version>-linux-x64.tar.gz.sha256`.
- If Defender flags it, please report the false positive at
  <https://www.microsoft.com/wdsi/filesubmission>. `install.ps1` is plain text, so you can read what it does first.

### Why there is no macOS build

Beyond All Reason ships only for Windows and Linux, and BARb's native library exists only as
`SkirmishAI.dll` and `libSkirmishAI.so`. With no macOS game and no macOS library to copy, a macOS
archive would install nothing that runs.

## More

- Players: lobby and online notes are in [Anarva/README.md](Anarva/README.md).
- Developers: everything is in `tools/`.
  - `install.ps1` deploys the AI (use `-Name AnarvaDev` for a side-by-side test copy).
  - `run_match.py` and `batch.py` run headless AI-vs-AI matches, including 1vN, with a scoreboard by
    map type.
  - `fetch_replays.py`, `run_replay.py` and `analyze_replays.py` find, play back and analyze
    high-skill replays, producing per-format development curves.

License: GPL-2.0, the same as CircuitAI and Beyond All Reason, which this is derived from.
