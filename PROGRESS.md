# Anarvā — progress log

**Goal:** one Anarvā beats **6 BARb (hard)** opponents on **all map types** (open, chokepoint, mixed,
water). Machine-readable state is in [`progress.json`](progress.json).

## Milestones

| # | Target | Status |
|---|--------|--------|
| M1 | 1v1 vs BARb hard, at least a 2:1 win ratio on all map types | baseline 7–3 (2.33), mostly points; testing new build |
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

## Added since the first build

- **Director:** postures follow Sun Tzu's force-ratio ladder (TURTLE, HOLD, BALANCED, PRESSURE,
  ALLIN), with the reasons logged.
- **Scouting decides scale vs army:** the core's constructor-vs-army knob (`buildpowerRatio`) is set
  from the scouted threat. When blind, it hedges and sends scouts; a greedy enemy gets punished.
- **Wave control:** the core's own squad thresholds were unreachable, so armies never launched.
  Waves are now script-owned and sized by the Director.
- **Capability-based production:** units are scored from runtime stats (damage against air, surface
  and underwater, health, range, speed, cost) against the scouted enemy mix, plus a screening value
  against heavy and artillery armies. Robust to balance patches.
- **Eco gate:** moho upgrades (+6 m/s for +17-20 E/s upkeep) only start when energy headroom carries
  them.
- **Energy:metal curve:** tried a lower, pro-derived curve and reverted it. Energy income also gates tech here (see STRATEGY.md §15).
- **Commander safety:** it starts hiding from minute 3 at a lower threat and a wider danger radius.
- **Fortify:** in HOLD or TURTLE, turrets plus dragon's teeth go up at the hottest front cell.
- **Continuous scouting** for real line of sight, not radar dots.
- **AA counter:** static anti-air over infrastructure, scaled to the enemy air metal we've seen.
- **Docs:** `STRATEGY.md` maps every principle to the code, and lists the limits (per-shot target
  priority, projectile and AoE dodging).

## In progress / next

- [x] Baseline batch b1 (12 games, 1v1, all map types)
- [x] Economy split rebalance (now in the main profile)
- [x] Reference curves from top duels (team-game curves pending playback)
- [x] Factory composition from capabilities (Production chooser)
- [x] Counter-response to scouted composition (AA towers, production scoring)
- [x] Walls and dragon's teeth at the front (Fortify)
- [ ] b2: measure the new build vs the baseline
- [ ] 1v2 → 1v3 → 1v6 on the big-map pool (`batch.py --pool big --n1 N`)
- [ ] Release packaging and installers (Windows and Linux) per the house standard
- [ ] Companion widget for projectile/AoE dodging and build-priority toggles (game side, see TACTICS.md §7)
- [ ] Front labs and rally points by travel time vs risk (TACTICS.md §8)
- [ ] Final: record the best games in the real client and add GIFs to the README

## Experiment log

| id | what | result |
|----|------|--------|
| t1 | first build vs BARb hard (Avalanche) | behind at 45 min; found army-power undercount and the reclaim-as-loss bug (both fixed) |
| role-hist | fight-task histogram | armies almost never launch |
| b1 | baseline, 12 games 1v1 | 7W 3L 2D, ratio 2.33; all losses from the team-1 start; only one commander kill |
| replays | top duels, rated 38-55 | winners: 54 m/s and army close to eco value at 10 min; losers over-build defence |
| b2 | new build vs BARb hard | stopped after 3 losses: the lower energy curve locked out fusion (0 fusions, 750 E/s at 30 min); reverted |
| b3 | new build with BARb's energy curve, 12 games | running |
