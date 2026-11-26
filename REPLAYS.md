# Replay library

Every strategic claim in Anarvā is checked against replays and cites them ([CLAUDE.md](CLAUDE.md) §1).
This file says what the library holds, where the parsed data lives, and which findings rest on which set.

## Layout

| Where | What | Count |
|---|---|---|
| `ref/lib/<format>/` | recent games of the official leaderboard's players (Season 3, ~400 players on 4 boards), built by `tools/build_library.py`; formats 1v1, 2v2, 3v3, 4v4, big (5v5+), ffa, teamffa, uneven | 500 (107 are 1v1) |
| `ref/lib/index.json` | per replay: id, file, format, map, minutes, players with skill and faction, winners, top players | 500 entries |
| `runs/replays.db` | the parsed data (below) | grows as replays are played |
| `runs/replay_logs/<id>.txt.gz` | the analyzer's raw lines per replay | one per played replay |
| older sets: `ref/top_replays/`, `ref/top_team_replays/`, `ref/vsbots_replays/`, `ref/vsbots_solo/` | early duel, team and humans-vs-bots downloads | 24, 9, 15, 12 |

`.sdfz` files and the database are not committed; `tools/build_library.py` rebuilds the library.

## The replay database

`tools/replay_db.py run` plays every replay in the index once, headless, with the analyzer widget
(`tools/replay_harness/LuaUI/Widgets/zz_replay_analyzer.lua`), and stores it in SQLite. It skips replays
already stored, so a restart never replays anything; 1v1 goes first.

| Table | Contents |
|---|---|
| `replays` | id, file, format, map, minutes, winners, status (`done` / `nodata` / `noengine`), end frame |
| `teams` | team, ally, side, player name, skill, won |
| `stats` | every minute per team: metal/energy income, current, storage, expense; army / defence / eco metal; units, constructors, build power, extractors and their income, factories |
| `built` | every finished unit: frame, team, unit, metal, tech level, air/sea/static/builder/armed, range, factory flag, position |
| `dmg` | damage and metal killed by attacker unit vs victim unit |
| `comm`, `cbuild` | commander every 5 s (position, distance from start, hp, command, armed metal around), what it built and where |
| `events` | first hit, commander death, end, winners |
| `motion` | combat units' speed and turn use per minute and kind |

Commands:
- `python tools/replay_db.py status`: progress per format.
- `python tools/replay_db.py ingest <playback dir> --id <id>`: parse an existing playback.

Before 2026-11-25 the analyzer died at the first kill in every replay (helpers declared after the callins
that used them), so earlier playbacks carried almost no data.

## Categories are discovered, not assigned

No category is written down in advance: a hand-made label ("eco boom", "turtle") decides what the games
are allowed to show, the same mistake as a fixed threshold. Categories come out of the data:

1. **Features, not labels.** Every player-game becomes a vector of measured features (economy curve, army
   composition by kind and tier, defence share, tech timings, expansion, commander behaviour, first
   contact) plus the context as numbers (team size, map size, chokiness, water share, faction).
2. **Clusters from the data.** Features are standardised and clustered without supervision; the number of
   clusters is chosen by fit (BIC), not fixed (`tools/cluster_replays.py`).
3. **Description afterwards.** Each cluster is described by the features that set it apart.
4. **Findings are per cluster,** with the member replays listed.

## Findings and the sets they rest on

| Finding | Set | Where |
|---|---|---|
| 1v1 winners by minute: extractors 3.4 / 9.0 / 14.1 / 20.1 / 23.6 and constructors 3.7 / 7.3 / 12.7 / 20.2 / 29.4 at minutes 2 / 4 / 6 / 8 / 10; second factory by minutes 6–8 (factories 1.4 at 6, 2.0 at 8, 2.7 at 10); army 593 / 1185 / 2756 / 4460 at minutes 4–10 | 61 1v1 games, `runs/replays.db`, 2026-11-25 | README status table |
| 1v1 openings: 6–8 energy plants in the first 14 builds; 120–190 E/s at minute 2 | 1v1 Eye of Horus (Aqo vs Baldric) and Pinewood Derby (PRO_Jamerz vs PLT_Atosty), 2026-11-23 | issue #86 |
| 1v1 losers trail the winners on extractors from minute 4 (6.5 vs 8.0 at 4; 11.8 vs 22.2 at 8) | first 11 1v1 games in the DB | issue #82 |
| Commanders leave the start at ~3 min; in 1v1, median 300–1160 out over minutes 3–11; in team games 1400–2900 out | 60 replays: 24 duels, 9 team, 27 vs bots (runs/comm_study, 2026-11-24) | STRATEGY.md §30 |
| BARb's commander stays 350–450 from start all game and dies there (76 of 168) | the same 27 vs-bots replays | STRATEGY.md §30 |

## Milestones of the 1v1 winners (replays.db, 107 winning players, 2026-11-26)

When each milestone first appears (minutes), and in how many of the 107 games it appears at all:

| Milestone | Games | Median | 25%-75% |
|---|---|---|---|
| First lab or plant | 103 | 1.1 | 0.9-1.2 |
| First construction turret | 102 | 4.7 | 3.7-5.7 |
| First T2 factory | 41 | 12.7 | 9.7-16.0 |
| First T2 extractor | 34 | 14.9 | 11.1-17.2 |
| First fusion | 24 | 16.6 | 13.2-20.7 |
| First advanced fusion | 9 | 18.2 | 17.4-18.8 |
| First T3 gantry | 12 | 26.3 | 24.3-30.8 |
| Juggernaut / Behemoth / Titan | 1 each | 41 / 46 / 33 | - |

Most 1v1 games are decided at T1 (only 41 of 107 winners build a T2 factory): expansion, the first construction
turret by ~5 minutes and the T1 army decide them. Query: first `built` frame per (replay, team) for the unit names
of each milestone, 1v1 winners only.

## Squad formation in contact (#116, 2026-11-26)

`[REPLAY] FORM` (analyzer widget): per type in a team's biggest squad, its count, weapon range and mean distance to the
nearest armed enemy. Played back: 4 Armada bot-lab 1v1 wins of 14+ minutes (`runs/formplay/`: Gasbag Grabens x2,
Devil's Postpiles, Feast of Hades); both teams, snapshots where the squad was in contact (nearest enemy within twice its
longest range). Small set: a lead, not a rule.

| Type | Range | Snapshots | Median distance behind the squad's front | Mean count in squad |
|---|---|---|---|---|
| Pawn (armpw) | 180 | 29 | 0 | 6.5 |
| Blitz (armflash) | 180 | 15 | 0 | 6.5 |
| Pyro (corpyro) | 230 | 23 | 0 | 3.1 |
| Fido (armfido) | 650 | 11 | 63 | 8.5 |
| Mace (armham) | 380 | 10 | 161 | 10.9 |
| Can (corcan) | 275 | 8 | 181 | 2.9 |
| Samson (armsam) | 700 | 3 | 457 | 2.0 |
| Morty (cormort) | 850 | 50 | 0 | 8.8 |

- Short-range units lead; longer-range units stand behind by roughly the range they have over the front - each fights
  from its own reach. (Morty at 0: in these snapshots it was the squad's only type.)
- Big single-type squads are normal (Morty ~9, Mace ~11, Fido ~8.5): a ball of one type is not the fault in itself; ours
  failed because it walked into fire without fighting (ops ending "target gone", 3800-7000 metal lost for 0 killed, mm1).
- Next to measure: winners vs losers separately, and how often the main squad holds versus chases.

## Where the metal goes in the first 8 minutes (2026-11-26)

Metal of everything built by 8:00, by category: 24 Armada bot-lab 1v1 winners (replays.db, unit costs from `built`)
against three of our games vs BARb hard (en8, rp2, kt1; Comet Catcher, Armada vs Cortex).

| Category | Winners (median) | en8 | rp2 | kt1 |
|---|---|---|---|---|
| Army | 3242 | 699 | 1122 | 1107 |
| Constructors | 1050 | 1210 | 680 | 660 |
| Extractors | 950 | 600 | 600 | 650 |
| Energy | 1858 | 2480 | 2015 | 2560 |
| Labs + caretakers | 1320 | 960 | 500 | 1420 |
| Towers + radar | 652 | 60 | 145 | 205 |
| **Total** | **~9070** | 6009 | 5062 | 6602 |

Winners spend ~45% more by 8:00 (more extractors: ~19 vs our ~12) and put 36% into army against our 12-18%; we put more
metal into energy than they do in absolute terms.

## Who builds what in the first 8 minutes (2026-11-26)

24 Armada bot-lab 1v1 winners (replays.db `cbuild` for the commander, `built` for all): by 8:00 a median of 19
extractors and 31 energy buildings. The commander builds 16.5 of the 31 energy buildings and only 4 of the 19
extractors; constructors take 15 extractors. The reason (comparative advantage): the commander is the best builder per
second and the costliest unit to lose, so it builds at base where nothing needs walking; the fast, cheap constructors
claim the spots. Ours did the reverse (rc1: commander picks 155 extractor, 87 solar).

## Our fights against BARb's, in contact (dr2 played back, 2026-11-26)

| | Anarvā | BARb |
|---|---|---|
| Median squad size in contact | 15.5 | 17 |
| Composition | Pawns only (range 180), ~14.5 | Brutes (350) ~11, Mists (700) ~5, Pounders (315) ~4.5, Incisors (230) ~3, Wolverines (710) ~1 |
| Median distance to the nearest enemy | 316 (outside our own 180) | 1050-1400 (outside our reach) |

One short-range type in one ball against a mixed squad that fights from range: BARb's rockets and artillery outrange the
Pawns four times over and shell them without entering their reach (owner: "1 unit type bulked in one ball").

