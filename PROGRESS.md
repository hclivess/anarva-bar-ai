# Anarvā — progress log

**Goal:** one Anarvā beats **6 BARb (hard)** opponents on **all map types** (open, chokepoint, mixed,
water). Machine-readable state is in [`progress.json`](progress.json). The reasoning behind each
module is in [STRATEGY.md](STRATEGY.md) and [TACTICS.md](TACTICS.md).

## Milestones

| # | Target | Status |
|---|--------|--------|
| M1 | 1v1 vs BARb hard, at least a 2:1 win ratio on all map types | first build 7–3 (2.33), mostly points wins; improving it module by module |
| M2 | 1v2, winning a majority on all map types | not started |
| M3 | 1v3 | not started |
| M4 | **1v6 on all map types** | not started; the harness supports it (`batch.py --pool big --n1 6`) |

## Method (learned the hard way)

- **One change at a time**, behind a feature flag (`F_*` in `brain.as`, `install.ps1 -Flags`).
- A variant plays **head-to-head against the best-measured build**, every map from **both sides**
  (16 games), 30-minute games with a points verdict from minute 20.
- A module ships **on** only when it wins. Defaults are always the best-measured configuration.
- **No static thresholds** in new logic. Decisions are live marginal-value comparisons. Remaining
  tunables are listed as debt in STRATEGY.md §16.

## Current defaults (best measured)

First-gen economy and commander configs, with these modules **on**: eco recycling and T1 salvage,
jammer intel, strategic structures (luxuries gated on force ratio), and the first-gen recall. Everything
else is off pending tests (see the status table in [README.md](README.md)).

## Layout

- `Anarva/stable/`: the AI (`AIInfo.lua`, `AIOptions.lua`, `config/<profile>/`, `script/<profile>/`).
  Profiles: `anarva` (main), `anarva_fg` (first-gen configs, for bisecting), `anarva_b` (old A/B).
- `tools/`:
  - `install.ps1` (`-Name`, `-Flags`)
  - `run_match.py`, `batch.py` (`--me`, `--opp`, `--n1`, `--pool big`)
  - `fetch_replays.py`, `run_replay.py`, `index_replays.py`, `analyze_replays.py`
- `installer/`, `build.py`, `.github/workflows/build.yml`: per-OS release archives (Windows and Linux).
- `ref/` (gitignored): extracted BARb configs, CircuitAI source, unit defs, strategy texts, replays.

## Key findings

1. BARb sends about 60% of metal into buildings, so its army stays tiny, and its gathering squads
   only launch at `max(quota, enemy's 2nd-biggest group)`, which is often unreachable.
2. Raids continue until their *leader* dies, so survivors trickle in one by one.
3. BARb never builds Juno, anti-nuke, tactical/EMP launchers, nukes, shields or walls, and treats
   geothermal as a last resort.
4. Top duel players (48 player-games rated 38–55) look the same for 8 minutes. Winners then reach
   53 m/s and keep army value close to eco value by minute 10, go T2 around minute 14, and don't
   over-build static defence.
5. **Energy also unlocks tech** in this engine (fusion needs about 840 E/s), so copying the pros'
   energy:metal ratio starved fusion (b2).
6. **Starvation is the failure mode.** Every regression so far was economic: a lower energy curve (b2),
   a scale knob that cut the economy when behind (b3), a production chooser that never built
   constructors (r6).
7. With games == maps, each map is played from one side only. Side and map advantage confound the
   absolute scores, so every map now gets played from both sides.

## In progress / next

- [x] Round 7: production chooser vs base. Even (4–1–4), not yet a gain.
- [x] Round 8: constructor-rich opener alone: 13–2–1, shipped
- [ ] Map analysis: offline per-map profile (extractors, base distance, paths and chokes, water, geo vents) loaded at game start
- [ ] Next one-at-a-time tests on the new base: scale knob, then production again
- [ ] Rework waves: launch when the gathered force can win *its* fight, and don't hold units at home
  while the map is lost.
- [ ] One-at-a-time tests: scale knob, tech gate, moho gate, waste, redirect, fortify.
- [ ] Constructor marginal value (replace the core-share placeholder).
- [ ] Geothermal decision (payback vs exposure and blast cost; needs vent positions).
- [ ] Team-game reference curves (top 2v2–8v8 replays playing back now).
- [ ] Legion test pool (Legion is disabled in the current harness).
- [ ] 1v2 → 1v3 → 1v6 on the big-map pool.
- [ ] Companion widget: projectile/AoE dodging, build-priority toggles, napalm avoidance.
- [ ] Front labs and rally points by travel time vs risk.
- [ ] Final: record the best games in the real client and add GIFs to the README.

## Experiment log

| id | what | result |
|----|------|--------|
| t1 | first build vs BARb hard (Avalanche) | behind at 45 min; found army-power undercount and reclaim-as-loss bugs (fixed) |
| role-hist | fight-task histogram | armies almost never launch (0–6 attacks vs 109 lone arty tasks) |
| b1 | first build vs BARb hard, 12 games | **7W 3L 2D (2.33)**, mostly points; all losses from the team-1 start |
| replays | top duels, rated 38–55 | see finding 4 |
| b2 | new bundle vs BARb | stopped: lower energy curve locked out fusion |
| b3 | new bundle (BARb energy curve) vs BARb, 12 games | 3W 8L: economic death spiral |
| h1 | all modules vs first build | 3W 4L 1D |
| h2 | without production and scale knob vs first build | 2W 4L 2D |
| h3 | all modules, strategic gated, vs first build | 1W 5L 2D |
| h4 | without strategic and fortify vs first build | 0W 6L 2D |
| h5 | first-gen configs, all modules, vs first build | 1W 4L 1D (6 games) |
| h6 | first-gen configs, modules mostly off, vs first build | 0W 5L 1D: always-on scouting, AA, recall and fusion recycling hurt |
| h7 | **everything new off** vs first build | **5W 3L (1.67): the new default** |
| h8 | h7 + reasoning modules bundle | 3W 4L 1D |
| h9 | default + waves + quotas vs first build | 2W 1L 1D, 3 incomplete |
| h10 | default + production vs first build | 3W 2L, 3 incomplete |
| r6 | default + production (± waves) vs default, both sides | 0W 4L 2D after 6 games: no constructors from the chooser; stopped and fixed |
| r7a | default + production (fixed) + waves + quotas vs default | 3W 2D 4L (10 of 16): no gain |
| r7b | default + production (fixed) vs default | 4W 1D 4L (10 of 16): even; losses on mixed/water with an eco gap |
| perf | throughput | 7 parallel engines run below real time with idle CPU; now 1 variant × 4 games in parallel |
| team replays | top ≤4v4 team games | boom harder and T2 5–6 min earlier than duels |
| r8 | default + constructor-rich opener vs default, 16 games | **13W 2L 1D (6.5)**, 4 commander kills, all map types: **shipped on** |
