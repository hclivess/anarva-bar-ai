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
| Strategic: anti-nuke when an enemy silo appears; EMP/tactical launcher, nuke under anti-nuke cover and shields, only while our army covers what we need | **on** | first build; luxury spending is gated on the force ratio |
| Broken-squad recall (first-gen rule) | **on** | first build |
| Constructor-rich opener | **on** | **13–2–1 vs the previous build** |
| Director scale knob (constructors vs army from scouted surplus/deficit; the economy is cut only when pushed back at home) | **on** | **9–4–3 vs the previous build** |
| Commander safety (configs: hide earlier, at lower threat, wider danger radius) | **on** | **1.5 → 2.25 vs BARb-hard** |
| Terrain defence: turrets on the high ground over our choke, dragon's teeth across it (map analysis) | **on** | new; on because chokes and high ground decide 1vN, being measured |
| Boom on pressure, not presence (the human playbook vs several BARbs) | off | 0–6 in 1v2 so far |
| Defeat in detail (1vN: size waves against one opponent, not the sum) | off | 1–11 in 1v2 (the first 1v2 win) |
| Production chooser (Lanchester damage × health, reach, sight, screening, travel time; rez bots) | off | rejected 2–1–8 |
| Waves and quotas, overflow handling, tech gate, moho gate, assist redirect, scouting timer, static AA, fusion recycling | off | rejected or neutral in A/B |

The reasoning behind each module is in [STRATEGY.md](STRATEGY.md) (economy, tech, intel, terrain; sources
Sun Tzu, Clausewitz, Napoleon and replays of top players and of humans beating several BARbs) and
[TACTICS.md](TACTICS.md) (composition, engagement, transports, micro limits). Every experiment and its
result is logged in [PROGRESS.md](PROGRESS.md) and [progress.json](progress.json). Open work is tracked
in [GitHub issues](https://github.com/hclivess/anarva-bar-ai/issues).

**Goal:** one Anarvā beats six BARb opponents on every map type.

**Status:**

- 1v1: Anarvā beats BARb-hard **9–4 with 3 draws** (2.25), with at least 2:1 on every map type.
- 1v2: not there yet. **1 win in 12** (Throne). It out-earns each BARb about 1.3×. Humans who beat
  several BARbs out-earn each bot 2–3× (STRATEGY.md §22), and closing that economic gap is the current
  work.

## The C++ core

Anarvā used to run only as scripts on top of BARb's prebuilt DLL. The scripts could only see the totals the DLL
chose to share (income, overall enemy threat, enemy cost per role), never "this enemy is here". Anarvā now
builds its own DLL from BARb's CircuitAI source with a small patch (`core/circuitai.patch`, built by
`tools/build_dll.sh` under MSYS2 MinGW64), so the scripts can see what the core sees. Strategy stays in script;
the core only supplies facts and hands-free mechanics, so it rarely needs rebuilding.

| Script API | What it gives |
|---|---|
| `AiGetEnemies(pos, vel, def, cost, flags)` | every known enemy: position, velocity, type (null for radar blips), metal cost, LOS/radar/being-built/paralyzed flags |
| `AiGetEnemyGroups(pos, cost, threat)` | the core's clusters of enemy units: centre, metal, threat |
| `AiGetTeamUnits()` | all our units |
| `AiGetElevation(x, z)`, `AiMinElevation()`, `AiMaxElevation()` | terrain height |
| `aiThreat.GetThreatAt(unit or def, pos)` | how much enemy fire a unit (type) would take at a spot |
| `def.GetRangeAt(heightDiff)`, `def.IsBallistic()` | weapon reach from a given height, using the engine's own rule (cannons reach further downhill, lasers lose a little either way) |
| `aiMilitaryMgr.EnqueueDefendAt(pos, power)`, `AbortTask(task)` | a defend task anchored at any spot (an expansion, a ridge), held until the script releases it |

Core behaviour changed in the patch:
- **Artillery picks its firing spot by height.** For each enemy building it could shell, it searches the ground
  around the target for spots where the target is in range from that spot's height and the threat map shows no
  enemy fire, then goes to the one it reaches soonest. High ground widens the set of spots that qualify, so
  artillery climbs exactly when a hill gives it reach or safety, with no hill bonus to tune.

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
   pass the path as an argument. It copies `Anarva/stable` there, including Anarvā's own core library (`SkirmishAI.dll` /
   `libSkirmishAI.so`: BARb's CircuitAI plus the bridge the scripts need, built for engine 2026.09.03).
   Every step is printed.
4. The lobby lists only its built-in AIs by default. To show Anarvā, create an empty `devmode.txt` in
   the data folder (the installer offers to do it), restart the lobby, then open
   **Settings → Developer** and untick **simple AI list**. Anarvā appears as **"Anarva stable"**.

Remove the AI with `install.cmd -Uninstall` or
`./install.sh --uninstall`. Add `-DryRun` / `--dry-run` to see what it would do without changing
anything.

### From source (developers)

`tools/install.ps1 -BarData <data folder>` copies the working tree's `Anarva/stable`; add `-Dll <path>` for a core
built by `tools/build_dll.sh` or the `core.yml` workflow (the scripts need it). Use `-Name AnarvaDev` for a side-by-side test copy. To build the release archives
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

## Questions and answers

**Can one player really beat six BARbs?**
Yes. Public replays show humans alone beating 3–14 hard and hard-aggressive BARbs, and BAR's own
scenarios pit one player against up to seven. Those humans boom to 2–3× each bot's income, keep an army
of about half the bots' combined army, fight it at home, and add static defence once the economy can
afford it (STRATEGY.md §22).

**Did you study how the best players progress?**
Yes, in three sets, played back headless and measured every minute:

- top-rated 1v1 duels (48 player-games)
- top team games up to 4v4 (25 player-games)
- humans alone against several BARbs (6 games)

Each has an income, army, defence and eco curve, and the economy-vs-army ratio over time. 1v1, team
games and 8v8 are treated separately because they differ: team games boom harder and go T2 earlier.
The decision rules copy the *reasoning* behind these curves, not the numbers.

**What did we gain from the map analysis?**

- **Ready and used:** per start position, Anarvā knows its choke toward the enemy, the high ground
  overlooking it, and how much higher that ground is. Terrain defence (on) builds there.
- **Ready and used:** for every installed map, Anarvā knows the base-to-base path length versus the
  straight line, the narrowest corridor, extractors per side and water share. These drive travel time
  and constructor value.
- **Not yet proven:** no map-driven module has won an A/B test yet. The constructor share from free
  extractors was neutral, and the composition chooser that uses travel time was rejected. Terrain
  defence is the first map-driven module to ship on, and it's still being measured.

**Is it aware of high-ground advantages?**

- Ballistic weapons gain range firing downhill, elevation extends sight, and crests block fire from
  below.
- Anarvā's map analysis finds the highest ground over its choke, and terrain defence puts its turrets
  there.
- The core's unit behaviour doesn't seek high ground in open fights; that needs unit commands (see the
  next question).

**What happens when a map gets updated?**
Map facts are looked up by full name, then by the map's name without its version. A new version of a
known map uses the facts of the version that was analysed. A brand-new map has no facts until
`tools/analyze_maps.py` is re-run, and Anarvā falls back to the core's behaviour there.

**What is "Throne"?**
A map: Throne_V8, 12288×12288 with lots of water, used in BAR's "King of the Hill" scenario. Test
results name the map they were played on.

**Does it use transports?**
Not yet. Transports can carry every unit, including turrets, construction turrets and the commander,
which makes the commander far faster. Directing them needs unit commands the script layer doesn't have.
It's planned for the C++ build, with commander airlift first.

**Does it use tactical missiles, nukes, cloaking and cameras?**

- **Tactical missile launcher:** BARb lists it among its defences but limits it to one and rarely builds
  it. Anarvā builds it forward when its army covers what it needs.
- **Anti-nuke:** a launch from a silo we never saw lands in seconds, so reacting to a spotted silo is
  too late. Readiness takes minutes: build time at our build power plus 90 s to stockpile the first
  interceptor. So Anarvā builds the anti-nuke as soon as an enemy *could* have a missile by the time
  ours would be ready. That's estimated from the enemy's likely economy since T2, weighted by the base
  value a nuke would erase and compared with the anti-nuke's cost.
- **Nuke:** built under anti-nuke cover. Its timing still uses fixed rules, which is open debt.
- **Not yet:** cloaked infiltration (sniping the anti-nuke, then nuking) and hidden cameras. Both are
  tracked as issues and need unit commands.

**Why didn't it build converters?**
Because it still used BARb's fixed "energy income = 20–60× metal income" curve. Energy kept being built
by the clock, storage sat full, and the core builds converters only as a last resort, at most two at a
time. The replacement is in test, as profile `anarva_e` with flags `F_ENERGY` and `F_CONVERT`:

- **No curve.** A power plant is ordered only when energy would run out before a new plant could
  finish (net balance, demand trend, stock, build time). Above 75% storage, where the game's converters
  already run, none is ordered.
- **Converters.** Real surplus goes to converters, T1 or T2 by which repays faster, build time included.

**How many rez bots?**
As many as the wreck metal on the map repays. Everything that died, ours and theirs, leaves about 60%
of its metal as a wreck; far-off fights count half because the enemy can take those wrecks too. One
more bot is built while that pool exceeds the fleet's cost plus one bot. Every count follows the same
rule: size it to the scale it works on (STRATEGY.md §28).

**Why not just copy BARb's or a pro's numbers?**
Balance changes and every game is different. Anarvā compares the live value of each option
(cost, build time, upkeep, risk, space, time to finish) and has **no static thresholds**.

**Does it work online?**
Yes. Only the player hosting the AI needs it installed (see [Anarva/README.md](Anarva/README.md)).

**Which opponent matters?**
BARb (BARbarIAn), the strongest built-in AI. Everything is tested against it, at its hard and
hard-aggressive settings.

## More

- **What is in the AI right now:** [FEATURES.md](FEATURES.md), every feature with its default and measured result, plus the script API (generated by `tools/gen_features.py`).
- Ideas and planned work: [GitHub issues](../../issues). Collaborators: work on a branch and open a pull request; new behaviour goes behind a flag that is off by default until it is measured.
- Players: lobby and online notes are in [Anarva/README.md](Anarva/README.md).
- Developers: everything is in `tools/`.
  - `install.ps1` deploys the AI (use `-Name AnarvaDev` for a side-by-side test copy).
  - `run_match.py` and `batch.py` run headless AI-vs-AI matches, including 1vN, with a scoreboard by
    map type.
  - `fetch_replays.py`, `run_replay.py` and `analyze_replays.py` find, play back and analyze
    high-skill replays, producing per-format development curves.

License: GPL-2.0, the same as CircuitAI and Beyond All Reason, which this is derived from.
