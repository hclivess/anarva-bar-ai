# Replay library

Every strategic claim in Anarvā is checked against replays and cites them ([CLAUDE.md](CLAUDE.md) §1).
This file says what the library holds, how replays are categorised, and which findings rest on which set.

## Layout

| Folder | Format | Source | Count |
|---|---|---|---|
| `ref/top_replays/` | 1v1 | top duels (`--preset duel`, every player OpenSkill >= 40) | 24 |
| `ref/lib/<format>/` | whatever the top players played (1v1 ... 8v8, FFA) | `tools/build_library.py`: recent games of the official leaderboard's players (Season 3, ~400 players on 4 boards) | 500 (building) |
| `ref/top_team_replays/` | team games (mixed sizes) | earlier download | 9 |
| `ref/vsbots_replays/`, `ref/vsbots_solo/` | humans vs bots (team, solo) | local games of humans beating BARb | 15, 12 |

Folders only say where a replay came from; they are not categories. Each folder has an `index.json` (from `tools/fetch_replays.py`): id, file, format, map, minutes, players
with skill and faction, winners. `.sdfz` files are not committed; rerun the fetcher to rebuild a folder.

## Categories are discovered, not assigned

No category is written down in advance: a hand-made label ("eco boom", "turtle") decides what the games
are allowed to show, the same mistake as a fixed threshold. Categories come out of the data:

1. **Features, not labels.** Every player-game becomes a vector of measured features from the analyzer
   output: the economy curve (metal/energy income by minute), army composition by kind (ground, air, sea,
   artillery, by tier), defence share, tech timings (first T2/T3 lab), expansion (extractors by minute),
   commander behaviour (distance by minute, share of time in contact, what it builds), first contact time,
   and the context as numbers too: team size, number of teams, map size, chokiness and water share from
   the map analysis, faction.
2. **Clusters from the data.** Features are standardised and clustered without supervision. The number
   of clusters is chosen by how well the model fits (silhouette / BIC over a range), not fixed.
3. **Description afterwards.** Each cluster is described by the features that set it apart from the rest
   (largest standardised differences of its centroid). A name, if any, is only shorthand for that
   description and is regenerated when the library changes.
4. **Findings are per cluster,** with the member replays listed, so a claim cites the replays it rests on.
   A finding from one cluster does not carry over to another unless the replays show it. Format is a
   feature like any other: if 1v1 and 8v8 commanders behave differently, the clusters will split them.

## Tools

- `tools/fetch_replays.py <out> --preset duel|team|ffa|teamffa [--team-size N] [--min-skill S] [--want N]`
- `tools/run_replay.py <out> <demo...> [--par N] [--minutes M]` plays replays headless with
  `tools/replay_harness` (economy every minute, builds, commander every 5 s, commander builds and deaths).
- `tools/analyze_replays.py` (economy curves), `tools/analyze_comm.py <runs> [--only list]` (commander).
- `tools/fetch_leaderboard.py` saves the official leaderboard (bar-rts.com/leaderboards, the page embedded on beyondallreason.info: Small Team, Large Team, Duel, FFA, top 100 each) to `ref/leaderboard.json`; it parses the page's data as data, nothing from the page is executed.
- `tools/build_library.py` builds the library from those players' games: ranked by each player's best position on any board, round-robin (each pass takes every player's next most recent playable game, best first) until 500 games, via the replay API's `players=` filter. Each replay lists its `top_players`; only their player-games are analysed.
- `tools/cluster_replays.py <playback dir> [--md CLUSTERS.md]`: feature vectors per player-game, Gaussian mixture with the cluster count chosen by BIC, each cluster described by its most distinctive features, with member replays and win rate.

## Findings and the sets they rest on

| Finding | Set | Where |
|---|---|---|
| Commanders leave the start at ~3 min; in 1v1 median 300-1160 out over min 3-11, LLTs ~2700 out; in team games 1400-2900 out | 60 replays: 24 duels, 9 team, 27 vs bots (runs/comm_study, 2026-11-24) | STRATEGY.md §30 |
| BARb's commander stays 350-450 from start all game and dies there (76 of 168) | the same 27 vs-bots replays | STRATEGY.md §30 |
| In 1v1 the commander is the king: early expander only while army and constructors are few | Vritrasura108 (#48); to be measured per minute in the duel set | issue #48 |
