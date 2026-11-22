# Anarvā — progress log

**Goal:** one Anarvā beats **6 BARb (hard)** opponents on **all map types** (open, chokepoint, mixed,
water). Machine-readable state is in [`progress.json`](progress.json).

## Milestones

| # | Target | Status |
|---|--------|--------|
| M1 | 1v1 vs BARb hard, at least a 2:1 win ratio on all map types | in progress |
| M2 | 1v2, winning a majority on all map types | todo |
| M3 | 1v3 | todo |
| M4 | **1v6 on all map types** | todo |

## Layout

- `Anarva/stable/`: the AI. It contains `AIInfo.lua`, `AIOptions.lua`, `config/anarva/*.json`, and
  `script/anarva/` with `main.as`, `init.as`, the managers and `misc/brain.as`.
- `Anarva/README.md`: install, lobby and online notes for players.
- `tools/`:
  - `install.ps1` deploys the AI into BAR.
  - `run_match.py` / `batch.py` run headless matches (batch prints a scoreboard by map type).
  - `run_replay.py`, `index_replays.py` and `fetch_replays.py` handle replay analysis.
- `ref/`: extracted BARb configs, CircuitAI source, game unit defs, and the replay index.

## Done

- **Army quota scaling.** Waves commit 30% → 55% of ground power. Raid packs are at least 3 raiders and
  grow to 40% of the raider pool.
- **Broken-squad recall.** A squad that drops below 40% of its peak goes home and regroups.
- **Eco recycling:**
  - solar, wind, tidal and advanced solar once fusion-tier power carries the base
  - fusions once 2+ advanced fusions carry the grid
  - T1 makers once T2 makers carry conversion

  Recycled types are blocked from being rebuilt; if energy collapses, the block is lifted.
- **T1 unit salvage** in the late game.
- **Jammer intel:** phantom threat on seen jammers, a loss heatmap that orders Dragon's Eyes, and on
  jammer alert air scouts, a higher scout quota and a Juno.
- **Strategic planner:** anti-nuke, Juno, EMP/tactical launcher, nuke under anti-nuke cover, and shields
  over the most valuable infrastructure.
- **Test infrastructure:** headless batches (about 1.2 s per game minute when run alone), 1vN support,
  and replay playback analysis.

## Key findings about BARb

1. It sends about 60% of its metal into buildings, so the army stays tiny: around 6k army metal against
   50k in statics at 40 minutes.
2. Its armies almost never launch. In a 40-minute game there were 0–6 ATTACK squads and 3 RAIDs, against
   about 109 lone artillery tasks.
3. Raids keep going until the *leader* dies, so survivors trickle in one by one.
4. It never builds Juno, anti-nuke, tactical/EMP launchers, nukes, shields or walls.
5. Its old-energy reclaim only fires when a new generator finishes, and only within 1000 elmos of base.

## In progress / next

- [ ] Baseline batch b1 (12 games, 1v1, all map types)
- [ ] A/B: economy split rebalance (`anarva_b`)
- [ ] Reference curves from top players (local plus public high-skill replays)
- [ ] Factory composition and timing tuned from those curves
- [ ] Counter-response to scouted enemy composition
- [ ] Walls and dragon teeth at chokes
- [ ] 1vN play: hold chokes, scale the economy, then break out

## Experiment log

| id | what | result |
|----|------|--------|
| t1 | first build vs BARb hard (Avalanche) | behind at 45 min; found army-power undercount and the reclaim-as-loss bug (both fixed) |
| role-hist | fight-task histogram | armies almost never launch |
| b1 | baseline, 12 games 1v1 | running |
