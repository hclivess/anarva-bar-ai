# Replay library

Every strategic claim in Anarvā is checked against replays and cites them ([CLAUDE.md](CLAUDE.md) §1).
This file says what the library holds, how replays are categorised, and which findings rest on which set.

## Layout

| Folder | Format | Source | Count |
|---|---|---|---|
| `ref/top_replays/` | 1v1 | top duels (`--preset duel`, every player OpenSkill >= 40) | 24 |
| `ref/lib/2v2/` ... `ref/lib/8v8/` | 2v2, 3v3, 4v4, 8v8 | top team games (`--preset team --team-size N`) | 10 each (downloading) |
| `ref/lib/ffa/` | FFA | `--preset ffa` | 10 (downloading) |
| `ref/top_team_replays/` | team games (mixed sizes) | earlier download | 9 |
| `ref/vsbots_replays/`, `ref/vsbots_solo/` | humans vs bots (team, solo) | local games of humans beating BARb | 15, 12 |

Each folder has an `index.json` (from `tools/fetch_replays.py`): id, file, format, map, minutes, players
with skill and faction, winners. `.sdfz` files are not committed; rerun the fetcher to rebuild a folder.

## Categories

A replay is categorised on several axes. Findings are reported per category and do not transfer to
another category unless the replays show it.

1. **Format:** 1v1, 2v2, 3v3, 4v4, 5v5-8v8, FFA, humans vs bots (1vN). Format changes what is safe: in team
   games one commander's death does not end the game, in 1v1 it does.
2. **Map type:** open, choke, mixed, water (`ref/maps.json`, the same classes the test harness uses).
3. **Length and outcome:** minutes, winner, and how it ended (army wipe, commander kill, surrender).
4. **Play style per player:** measured from the analyzer output, not assigned by hand. Each player gets
   the style whose feature is furthest above the median of the same format and map type (a z-score
   within the category, so no fixed cutoffs):

   | Style | Feature (from `[REPLAY]` lines) |
   |---|---|
   | eco boom | metal income at minute 10 relative to army metal |
   | early aggression | army metal and first contact time before minute 6 |
   | turtle / porc | defence metal share |
   | air | air units' share of army metal |
   | T2 rush | minute the first T2 lab finishes |
   | commander play | commander distance from start, minutes 3-8; share of time in contact |
   | sea | naval share of army metal |

## Tools

- `tools/fetch_replays.py <out> --preset duel|team|ffa|teamffa [--team-size N] [--min-skill S] [--want N]`
- `tools/run_replay.py <out> <demo...> [--par N] [--minutes M]` plays replays headless with
  `tools/replay_harness` (economy every minute, builds, commander every 5 s, commander builds and deaths).
- `tools/analyze_replays.py` (economy curves), `tools/analyze_comm.py <runs> [--only list]` (commander).

## Findings and the sets they rest on

| Finding | Set | Where |
|---|---|---|
| Commanders leave the start at ~3 min; in 1v1 median 300-1160 out over min 3-11, LLTs ~2700 out; in team games 1400-2900 out | 60 replays: 24 duels, 9 team, 27 vs bots (runs/comm_study, 2026-11-24) | STRATEGY.md §30 |
| BARb's commander stays 350-450 from start all game and dies there (76 of 168) | the same 27 vs-bots replays | STRATEGY.md §30 |
| In 1v1 the commander is the king: early expander only while army and constructors are few | Vritrasura108 (#48); to be measured per minute in the duel set | issue #48 |
