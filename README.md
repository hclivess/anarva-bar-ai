# Anarvā — a new AI and a data lab for Beyond All Reason

Two things in one repository:

- **A new Skirmish AI.** It decides everything from the live game: values computed from unit facts and measured
  state, with no dice and no hand-picked constants. It runs on its own build of BARb's C++ core.
- **A BAR data lab.** Hundreds of top-player replays are played back headless and stored in one SQLite database:
  economy by minute, every unit built with time and place, kills by attacker and victim, commander tracks. The
  figures below come from it, and so does every claim the AI's decisions rest on (see [Replay study](#replay-study)).

## What "Anarvā" means

*Anarvā* comes from the Sanskrit *anarvan*: unrestrained, boundless, irresistible. In the Bhāgavata
Purāṇa (6.10), Anarvā is one of the generals who served under Vṛtrāsura, among the asura commanders
(with Namuci, Śambara, Puloma and others) who led his armies against Indra's devas. The name is the
design. BARb plays by arbitrary constraints: hand-tuned cutoffs, fixed timers, dice rolls, a build order
from a table. Anarvā removes them. Every choice is argued from the situation in front of it.

## Status (2026-11-26)

![What 1v1 winners have by each minute, and where Anarvā stands](docs/replay_research.gif)

*1v1 winners from top-player replays (blue: median, band: middle half) against one Anarvā game versus BARb hard
(orange). Regenerate with `python tools/viz_replays.py --game runs/<batch>/gNN`.*

**Anarvā does not beat BARb yet.** It has not won a full-length 1v1 against BARb hard since it was rebuilt from
BARb's logic into its own decisions. The closest round so far (round 32) went to the 20-minute limit in three of
four games and lost them on points.

**What the chart shows:** Anarvā keeps pace with the winners for the first seven minutes:
- extractors, energy and its first lab come on the winners' curve;
- it builds a second factory before they do.

Then BARb's raiders take its extractors and its army never grows past a fraction of theirs. Holding the map and
building production capacity, starting with the first construction turret that winners build at 4.7 minutes, is
the current work.

**Recent changes, most from watching games against BARb** (each is a computed decision, see below):
- **Energy before the lab:** the opener builds whichever of metal and energy limits the lab's production.
  It used to build three extractors and the lab before any energy.
- **Pricing:**
  - an extractor is worth what it extracts minus its upkeep;
  - energy is priced by what it lets us spend;
  - wind is valued as it blows, lulls included.
- **Commander:** it no longer chases raiders it can't catch, and its build time counts as a cost.
- **Builders:**
  - they finish their jobs;
  - they leave a job when energy runs short and switch to energy, boosting the factory included;
  - they reclaim what blocks their way.
- **Towers:**
  - they compete with other jobs on the loss they prevent;
  - a choke tower is built only where its fire covers the whole choke.
- **Rez bots** are built only for actual wrecks.
- **Fights:** taken on expected value: what the fight keeps against what it risks.
- **Engine and lobby:**
  - it reports ready at the start screen and says which team it is in chat;
  - two Anarvās in one game no longer crash.

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

**Milestones of the 1v1 winners** (107 winning players; when each first appears, and how many get there):

| Milestone | Games | Median | Middle half |
|---|---|---|---|
| First lab or plant | 103 | 1.1 min | 0.9–1.2 |
| First construction turret | 102 | 4.7 min | 3.7–5.7 |
| First T2 factory | 41 | 12.7 min | 9.7–16.0 |
| First T2 extractor | 34 | 14.9 min | 11.1–17.2 |
| First fusion | 24 | 16.6 min | 13.2–20.7 |
| First T3 gantry | 12 | 26.3 min | 24.3–30.8 |
| Juggernaut / Behemoth / Titan | 1 each | 41 / 46 / 33 min | |

**What winners build, minute by minute** (units built per game in each minute; the 24 most-built units):

![Unit time map of 1v1 winners](docs/units_timeline.png)

Wind is built hardest between minutes 6 and 9. The raiders arrive in the same window: Grunts (`corak`) at minutes
2–6, Incisors (`corgator`) at 8–10. Winners build about 17 construction turrets per game, most of them at minutes
8–10.

**Where they build** (Feast of Hades, 15 winning players, both start sides overlaid, growing minute by minute):

![Build heatmap on Feast of Hades](docs/heatmap_feast_of.gif)

Extractors cover the whole map. Energy stays packed in the two base corners, and defences sit along the middle and
the extractor fields.

**Which units kill the most** (metal killed by attacking unit type, both players, all 1v1 replays):

![Units ranked by metal killed in 1v1](docs/top_killers.png)

At T1 the Incisor (`corgator`), the Grunt (`corak`) and the Blitz (`armflash`) lead. The heavy units at the top come
from the longer games. Regenerate all three with `python tools/viz_units.py [--map "<map>"]`.

**Winners and losers** (median by minute, all top-player 1v1 replays):

![1v1 winners and losers by minute](docs/winners_vs_losers.png)

Winners and losers are level at minute 5: 12 vs 11 extractors, army 826 vs 817. By minute 10 the winners lead with
24 extractors to 19 and 52.7 metal/s to 42.3. 1v1s are won by out-expanding after the opening, not by the opening
itself.

**More numbers from the 1v1 replays** (107 games, 214 players):

| | |
|---|---|
| Game length | median 14.9 min (middle half 11.6–22.5) |
| First factory, players / win rate | vehicle plant 76 / 55%, bot lab 130 / 48%, air plant 6 / 17% |
| Faction chosen, players / win rate | Armada 123 / 52%, Cortex 53 / 34%, random 38 / 66% |
| Commander deaths | recorded in 105 of the 107 games |

These are counts from this set of games, not a balance verdict: players who pick random may differ in skill from
those who pick a faction.

Most 1v1 games are decided at T1: only 41 of 107 winners build a T2 factory. Expansion, the first construction
turret by about five minutes, and the T1 army decide them. By 3:00 the winners average 8.4 wind turbines,
5 extractors, about 6 fighters and 0.2 towers.

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

The last release (v0.1.0) predates the rework. A new release follows once Anarvā wins its 1v1s; until then,
build from source.

### From source (developers)

- Build the core under MSYS2 MinGW64 (`tools/build_dll.sh`, or `ninja -C ref/build BARb`).
- Deploy with `tools/install.ps1 -Name Anarva -Dll <built SkirmishAI.dll>`. It refuses, changing nothing, while
  a running BAR holds the library.
- Test one game at a time: `python tools/batch.py runs/<name> --games 1 --par 1 --me Anarva:anarva --opp BARb:hard
  --maps "<map>"`, then `python tools/check_game.py runs/<name>/g00`. That compares the game with the 1v1 winners,
  including the 3:00 build on the same map.
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
