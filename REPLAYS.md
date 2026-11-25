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
