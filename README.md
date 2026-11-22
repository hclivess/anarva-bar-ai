# Anarvā — a smarter Skirmish AI for Beyond All Reason

Anarvā runs on BARb's C++ core (CircuitAI) and adds its own AngelScript brain and tuned configs:

- massed attack waves with a posture-driven Director (boom, hold, balanced, pressure, all-in)
- broken-squad recall, so armies don't trickle in one by one
- eco recycling: solars and winds → fusions → advanced fusions, plus T1 makers and obsolete T1 units
- jammer hunting: phantom threat on seen jammers, Dragon's Eyes where we die unseen, Junos
- strategic buildings BARb never makes: anti-nuke, tactical/EMP launchers, nukes, shields over key
  infrastructure, and anti-air placed when air is scouted

**Goal:** one Anarvā beats six BARb (hard) opponents on every map type. Status is in
[PROGRESS.md](PROGRESS.md) and [progress.json](progress.json).

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
