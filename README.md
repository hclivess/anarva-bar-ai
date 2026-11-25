# Anarvā — a Skirmish AI for Beyond All Reason

## What "Anarvā" means

*Anarvā* comes from the Sanskrit *anarvan*: unrestrained, boundless, irresistible. In the Bhāgavata
Purāṇa (6.10), Anarvā is one of the generals who served under Vṛtrāsura, among the asura commanders
(with Namuci, Śambara, Puloma and others) who led his armies against Indra's devas. The name is the
design. BARb plays by arbitrary constraints: hand-tuned cutoffs, fixed timers, dice rolls, a build order
from a table. Anarvā removes them. Every choice is argued from the situation in front of it.

## Status (2026-11-25)

**Anarvā does not beat BARb yet.** It is being rebuilt from BARb's logic into its own decisions, and
since that rework it has not won a full-length 1v1 against BARb hard. Earlier results ("9–4 vs BARb
hard") came from a build that still ran BARb's logic underneath. They are history, not the current
state.

**What changed in the rework:**
- Every random number and hand-picked constant in the scripts, configs and the C++ core became a computed
  decision ([AUDIT.md](AUDIT.md) lists each one and what replaced it).
- The feature flags were folded into the code.
- The first games after the rework exposed a series of economy and strength-estimation bugs, which have
  been fixed (issues #81–#88).

**Where it stands against top players.** The yardstick is the best players' replays, not BARb. These
are the average winners of 61 top-player 1v1 games in the replay database, against Anarvā in its latest
1v1 tests against BARb hard:

| Minute | Extractors | Constructors | Factories | Army (metal) | Anarvā (latest tests) |
|---|---|---|---|---|---|
| 2 | 3.4 | 3.7 | 1.0 | 102 | 2–3 extractors, 1 constructor |
| 4 | 9.0 | 7.3 | 1.0 | 593 | 3–4 extractors |
| 6 | 14.1 | 12.7 | 1.4 | 1185 | 4–9 extractors |
| 8 | 20.1 | 20.2 | 2.0 | 2756 | 5–12 extractors, 1 factory, army 1300–2900 |
| 10 | 23.6 | 29.4 | 2.7 | 4460 | |

The gap is expansion and production capacity: winners keep about one constructor per extractor and add a
second factory by minutes 6–8. This is the current work.

**Goal:** first 100% of 1v1 games against BARb hard, then one Anarvā against six BARbs on every map type.

## How it decides

Anarvā runs on its own build of BARb's C++ core (CircuitAI plus [`core/circuitai.patch`](core/circuitai.patch))
with its own AngelScript brain (`Anarva/stable/script/anarva/misc/brain.as`). The rules (from
[CLAUDE.md](CLAUDE.md)):

- **No random numbers, no hand-picked constants.** A decision is a live comparison of value
  (metal-equivalent over the planning horizon, minus risk), from measured game state and unit facts. The
  only numbers allowed are game facts (frame rate, a unit's cost, range, speed), unit conversions and
  guards against division by zero.
- **Copy the reasoning behind what top players do, never their numbers.** Every strategic claim cites the
  replays it rests on.

Examples of what that means in practice:

| Decision | How it is computed |
|---|---|
| Planning horizon | how long what we own keeps paying before the enemy can take it: the time they need to build a force worth all we own, plus the time to cross the map |
| Which job a constructor takes | seconds until the job pays back at *shadow prices*: metal is worth nothing while it overflows, energy is priced at our own spending ratio while it is the bottleneck, and a job without a yield (lab, turret) is paid from stock and then income |
| How much energy | the energy needed to spend the metal we earn, at the energy/metal ratio of what our factories build. Converters' draw counts as surplus, not need |
| How many constructors | enough to claim the unclaimed extractor spots within the horizon (walk + build per spot), and only while we are not weaker than the enemy army we know of |
| Strength | each known enemy unit counted once, on the same Lanchester measure as ours: sqrt(dps × health). The commander's D-gun is excluded, since it fires only on order |
| When to tech | the T2 upgrade's payback must beat both the horizon and the next T1 extractor, unless the lab's cost is already banked |
| Reclaiming our own plants | only when a plant we can build now (not vent-bound) makes more energy per metal, and energy stays in surplus without it |
| Faction | from the commander that actually spawned: a random side resolves only then |

Every builder choice is logged with its alternatives (`[ANV-PICK]` lines: the job taken and the best job
of each other type, in seconds), so each economic decision can be read from the log.

## Replay study

500 games of leaderboard players (1v1 to 8v8, FFA) are downloaded to `ref/lib/` (see
[REPLAYS.md](REPLAYS.md)). `tools/replay_db.py run` plays each one back once, headless, with the analyzer widget, and stores
everything in SQLite (`runs/replays.db`), so no replay is ever played twice:

- per minute and player: metal and energy income, banked and storage, spending, army, defence and economy
  value, constructors, build power, extractors and their income, factories
- every unit built, with time, place and kind
- the damage and kill matrix by attacker unit and victim unit (for studying fights; the AI never reads it as a table)
- the commander's track, what it built and where it died

1v1 is parsed first. Progress: `python tools/replay_db.py status`.

## The C++ core

The scripts see the battlefield through a bridge the patch adds:

| Script API | What it gives |
|---|---|
| `AiGetEnemies(...)` | every known enemy: position, velocity, type, metal cost, flags, health, build progress |
| `AiGetEnemyGroups(...)` | the core's clusters of enemy units: centre, metal, threat |
| `AiGetTeamUnits()`, `AiGetMetalSpots(...)`, `AiGetWrecks(...)` | our units, extractor spots, wrecks |
| `AiGetElevation(x, z)` and terrain queries | height, line of sight |
| `aiThreat.GetThreatAt(unit or def, pos)` | enemy fire a unit would take at a spot |
| `def.GetRangeAt(heightDiff)`, `def.CanBuild(def)`, `def.GetRadius()` | reach from a height, build options, footprint |

Unit facts the bridge can't see (build options, stockpile times, extraction, upkeep, geothermal vents,
commander metal make) are generated from the game's unit files by `tools/gen_facts.py` into `misc/facts.as`.

## Install

You need Beyond All Reason installed and started at least once (so it has downloaded an engine).

### From a release

1. Download the archive for your OS from the [latest release](https://github.com/hclivess/anarva-bar-ai/releases/latest):
   - Windows: `anarva-<version>-windows-x64.zip`
   - Linux: `anarva-<version>-linux-x64.tar.gz`
2. Extract it. Don't run the installer from inside the zip.
3. Run the installer: double-click `install.cmd` on Windows, or run `./install.sh` on Linux.

   It finds your BAR data folder. If it finds several or none, it asks you, and you can also pass the
   path as an argument. It copies `Anarva/stable` there together with Anarvā's own core library
   (`SkirmishAI.dll` / `libSkirmishAI.so`). The scripts need that core's bridge, so BARb's stock library
   won't run them.
4. The lobby lists only its built-in AIs by default. To show Anarvā:
   - Create an empty `devmode.txt` in the data folder (the installer offers to do it).
   - Restart the lobby.
   - Open **Settings → Developer** and untick **simple AI list**.

   Anarvā appears as **"Anarva stable"**.

Remove it with `install.cmd -Uninstall` / `./install.sh --uninstall`; `-DryRun` / `--dry-run` shows what
would happen without changing anything.

The last release (v0.1.0) predates the rework. A new release follows once Anarvā wins its 1v1s.

### From source (developers)

- Build the core under MSYS2 MinGW64 (`tools/build_dll.sh`, or `ninja -C ref/build BARb`).
- Deploy with `tools/install.ps1 -Name AnarvaDev -Dll <built SkirmishAI.dll>`, which makes a side-by-side
  test copy.
- `python build.py` self-tests the configs and writes the release archives to `dist/`.

### Windows says the script is not safe

The installer is a plain, unsigned script, so Windows may warn about it.

- **SmartScreen "Windows protected your PC"**: click **More info → Run anyway**.
- **Downloaded-file block**: unblock the zip before extracting (Properties → **Unblock**, or
  `Unblock-File .\anarva-<version>-windows-x64.zip`).
- **Check the download is ours**: compare `Get-FileHash .\anarva-<version>-windows-x64.zip -Algorithm SHA256`
  with the `.sha256` file on the release page. On Linux, run `sha256sum -c anarva-<version>-linux-x64.tar.gz.sha256`.
- If Defender flags it, report the false positive at <https://www.microsoft.com/wdsi/filesubmission>.

### Why there is no macOS build

Beyond All Reason ships only for Windows and Linux, and BARb's native library exists only as
`SkirmishAI.dll` and `libSkirmishAI.so`.

## Questions and answers

**Can one player really beat six BARbs?**
Yes. Public replays show humans alone beating 3–14 hard BARbs, and BAR's own scenarios pit one player
against up to seven ([STRATEGY.md](STRATEGY.md) §22).

**Why not copy a pro's build order?**
Balance changes and every game differs. Anarvā takes the *reason* a strong player does something (what
it buys, what it costs, in which situation) and computes the decision from the live game. Their numbers
are only the yardstick that Anarvā's results are compared against.

**How does it know what each unit is good against?**
From each unit's facts (range, speed, weapons, targets, health, cost), set against the enemy units it
actually sees in this game by the square law. There is no counter table: not BARb's, and not one built from
replays. A table is a frozen rule, and the right answer depends on the enemy actually in this game.

**Does it use transports, nukes, cloak, cameras?**

- **Anti-nuke:** built when an enemy *could* have a missile by the time ours would be ready.
- **Nukes, tactical launchers and shields:** built when their value beats their cost.
- **Cameras:** placed where the loss heatmap shows unseen losses.
- **Not yet:** transports and cloaked infiltration (issues #28, #75).

**Does it work online?**
Yes. Only the player hosting the AI needs it installed (see [Anarva/README.md](Anarva/README.md)).

## More

- [FEATURES.md](FEATURES.md): what the AI does now, by module.
- [STRATEGY.md](STRATEGY.md) and [TACTICS.md](TACTICS.md): the reasoning (Sun Tzu, Clausewitz, Lanchester,
  replays).
- [AUDIT.md](AUDIT.md): every removed random number and constant, and what replaced it.
- [PROGRESS.md](PROGRESS.md): test log.
- [GitHub issues](https://github.com/hclivess/anarva-bar-ai/issues): open work. Every remark from the owner's
  games becomes an issue.
- Developer tools in `tools/`:
  - `batch.py` and `run_match.py`: headless matches, including 1vN.
  - `replay_db.py`: the replay database.
  - `gen_facts.py`: unit facts.
  - `analyze_maps.py`: map analysis.

License: GPL-2.0, the same as CircuitAI and Beyond All Reason, which this is derived from.
