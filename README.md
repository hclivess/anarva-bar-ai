# Anarvā — a smarter Skirmish AI for Beyond All Reason

## What "Anarvā" means

*Anarvā* comes from the Sanskrit *anarvan*: unrestrained, boundless, irresistible. In the Bhāgavata
Purāṇa (6.10), Anarvā is one of the generals who served under Vṛtrāsura, among the asura commanders
(with Namuci, Śambara, Puloma and others) who led his armies against Indra's devas. The name is the
design. BARb plays by arbitrary constraints: hand-tuned cutoffs, fixed timers, gathering thresholds it
can never reach, a factory mix that ignores what it sees. Anarvā removes them. Nothing it does is
"because the number says so". Every choice is argued from the situation in front of it.

## How it works

Anarvā runs on BARb's C++ core (CircuitAI) and adds its own AngelScript brain and configs. Its rule is
**no static thresholds**: every choice compares the live marginal value of the alternatives, worked out
from game facts (unit costs, upkeep, converter rates) and live measurements (force ratio, trade
efficiency, front movement, income growth, overflow).

Every module sits behind a feature flag (`F_*` in `script/anarva/misc/brain.as`). A module ships **on**
only after it has won head-to-head A/B tests, every map from both sides, against the best-measured
build. Status as of this commit:

| Module | Default | Evidence |
|---|---|---|
| Recycling obsolete eco (solar/wind → fusion → advanced fusion, T1 makers) and salvage of idle T1 units | **on** | part of the first build (7–3 vs BARb-hard) |
| Jammer intel: phantom threat on seen jammers, loss heatmap → Dragon's Eyes, Juno on jammer alert | **on** | first build |
| Strategic: anti-nuke when an enemy silo appears; EMP/tactical launcher, nuke under anti-nuke cover and shields, only while our army covers what we need | **on** | first build; luxury spending is now gated on the force ratio |
| Broken-squad recall (first-gen rule) | **on** | first build |
| Constructor-rich opener (constructors alternate with raider escorts) | **on** | **13–2–1 vs the previous build** (round 8) |
| Production chooser: units scored from live abilities (Lanchester damage × health, reach, sight gap, screening, travel time vs horizon); rez bots from the wreck pool; constructors left to the core's mix | testing, leading | 3–0 vs base in the first games of round 7 |
| Director-sized waves and quotas (army needed to win = enemy + jammer guess ÷ trade efficiency) | off | net negative so far: holds units back, costs map control |
| Director scale knob (constructors vs army from surplus/deficit) | off | untested on its own since the starvation fixes |
| Payback-based tech gate, moho energy gate, overflow handling (nanos, converters), assist redirect, fortify (turrets + teeth) | off | untested individually yet |
| Forced continuous scouting, static AA counter, need-based recall, fusion recycling | off | measured harmful as always-on behaviour (round 3 → 4) |

The reasoning behind each module is in [STRATEGY.md](STRATEGY.md) (economy, tech, intel; sources Sun Tzu,
Clausewitz, Napoleon and top-player replays) and [TACTICS.md](TACTICS.md) (composition, engagement,
micro limits). Every experiment and its result is logged in [PROGRESS.md](PROGRESS.md) and
[progress.json](progress.json).

**Goal:** one Anarvā beats six BARb (hard) opponents on every map type.

**Honest status:** the first build beat BARb-hard 7–3 in 1v1, mostly on points. Bundling many new
modules at once regressed it (3–8), mainly through economic starvation. That's why every module is now
proven one at a time. The 1v6 goal hasn't been attempted yet: the 1v1 build has to be clearly stronger
first.
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
