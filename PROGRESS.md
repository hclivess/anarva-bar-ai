# Anarvā — progress log

**Goal:** first win **100% of 1v1** games against BARb hard, then one Anarvā beats **6 BARb (hard)** on **all
map types** (open, chokepoint, mixed, water). The yardstick for *how* it plays is the top players' replays
(`runs/replays.db`, see [REPLAYS.md](REPLAYS.md)), not BARb. The reasoning is in [STRATEGY.md](STRATEGY.md)
and [TACTICS.md](TACTICS.md).

## Milestones

| # | Target | Status |
|---|--------|--------|
| M1 | 1v1 vs BARb hard, every game | **not met.** The early "2.25" (2026-11-23) came from a build that still ran BARb's logic. Since the rework (constants → decisions, flags folded) no full 1v1 has been won yet |
| M2 | 1v2 | not met (lost 2026-11-25, Comet Catcher, dead at minute 11) |
| M3 | 1v3 | not started |
| M4 | **1v6 on all map types** | not started; the harness supports it (`batch.py --pool big --n1 6`) |

## Method

- **Reason first, test second** ([CLAUDE.md](CLAUDE.md) §0). Fix what a strong player would call obviously wrong,
  as computed decisions, in batches; then play a few games to see the batch work. Tests confirm; they
  don't substitute for reasoning.
- **Read what the AI did.** Each test reads the build log (`[ANV] built`), the builder pick log
  (`[ANV-PICK]`: the job taken and the best of each other type), the economy line per minute and the
  Director's strength ratio, then compares the curves with the replay database's winners.
- **No hand-picked numbers** ([AUDIT.md](AUDIT.md)). A fix that adds a cutoff, band or gate is a bug.

## Layout

- `Anarva/stable/`: the AI (`AIInfo.lua`, `config/anarva/`, `script/anarva/`; the brain is `misc/brain.as`).
- `core/circuitai.patch`: Anarvā's changes to BARb's CircuitAI (branch `anarva129` in `ref/circuitai`).
- `tools/`:
  - `install.ps1 -Name AnarvaDev -Dll <core>`: a side-by-side test copy.
  - `batch.py`, `run_match.py`: headless matches.
  - `replay_db.py`: the replay database.
  - `gen_facts.py`: unit facts.
  - `analyze_maps.py`: map analysis.
- `installer/`, `build.py`, `.github/workflows/`: per-OS release archives.
- `ref/` (gitignored): CircuitAI source, unit defs, replays.

## 2026-11-25: first games after the rework

1v1 vs BARb hard, mostly Avalanche and Throne, 6–14 minute caps unless noted. Each line is a symptom, its
cause and the fix (details in issues #81–#88).

| Symptom | Cause | Fix |
|---|---|---|
| reclaimed its own wind turbines from frame 660 | horizon = time played × share, so 0 s at start | horizon = enemy time to match what we own + map crossing |
| Cortex Anarvā ordered Armada extractors and turrets | random side: the core learns the faction when the commander spawns | redo side-specific init when the side changes |
| reclaimed fresh Thuds | "obsolete" = worse than the single best buildable unit | outclassed by a higher factory tier |
| no extractors at start; energy storage at 0:43; metal storage at 0:32 | "storage full" gates; the game starts full | overflow = income beyond what build power can spend |
| builders never compared jobs by time | (band × 1e12 + seconds) packed in a float lost the seconds | exact key; job time = travel + build + payback at shadow prices |
| lab first, then 20 LLTs over extractors | ranked by cost; NOW/NORMAL bands | stock-aware payback; defence below income |
| far extractor jobs invisible | 2000-elmo radius for extractors vs 10000 for energy | removed |
| 14 extractors, metal full, energy 30/s | energy priced at the converter rate while it bound; energy queued only once stalled | shadow price; energy queued whenever needed, planned for factory output |
| lab built only constructors (army 86 for 10 min) or 49 constructors | "behind → unlimited constructors" | claim walk time over the horizon, army first while weaker |
| bigger army read r=0.3, never attacked | D-gun counted as 111k dps: commander = 113 Pawns | D-gun excluded: commander ≈ 4.6 Pawns |
| crash in every longer game | scripts moved units across task modules | core refuses cross-module / nil / player moves |
| commander pulled off every job (40 claims in 5 min) | script forward claims overrode the core | removed; script decides only risk |

Full-length games (30-minute cap) so far:
- Avalanche: lost at minutes 12, 10 and 10.
- Throne: lost at minute 20, and crushed at minute 19 (army 86 vs 12,870) when the run was cut.

The latest batch (D-gun and strength fixes) is being played.

## Experiment log (early build, 2026-11-22 to 11-24; not re-measured since the rework)

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
| r9 | + scale knob vs default (with opener), 16 games | **9W 4L 3D (2.25): shipped on** |
| r10 | + production + map-driven constructor share | 2W 1D 8L: the chooser loses fights; stays off |
| abs1 | **current best vs BARb hard**, 16 games both sides | **6W 6D 4L (1.5)**; 3 of 4 losses are commander kills; water weakest |
| r11 | + commander safety vs BARb hard, 16 games | **9W 3D 4L (2.25)**, 6 commander kills, ≥2:1 on every map type: **M1 met, shipped** |
| m2-base | 1v2 vs BARb hard, big maps, separated starts | **0W 11L 1D**: out-ecoes each BARb, but the army is ~40% of their combined; the commander dies when pushed back |
| m2-fortify | 1v2 + Fortify | 0W 9L 1D: no help |
| m2-commsafe | 1v2 + commander works only in the protected zone | 0W 3L: the base itself gets overrun; root cause is the economy |
| r12 | 1v1 vs BARb: + waste handling (converters, nanos) | 6W 7L 3D (0.86) vs 2.25: rejected |
| r13 | 1v1 vs BARb: + moho gate + payback tech gate | running |

## 2026-11-26 night: findings to carry forward

- Single-game tests on Canis River, one at a time (owner rule). All lost; best mid-game so far: 19 extractors,
  3 factories, army 3004 at minute 12 (then lost the big fight to Pounders vs massed Pawns).
- Fixed tonight (each from a traced cause): raid churn (launch on the same test a raid must keep passing),
  evacuation flip-flop (escape jobs carry value), energy price cap, extractor metal discounted only while energy
  binds, splash and dodging in unit strength, a factory's raid loss = its lost production (the last one: the game).
- Win-probability model (replays, relative to the opponent, AUC up to 0.87): energy-income lead and extractor lead
  decide 1v1s. Against BARb our biggest costs are energy at minute 3, metal income at minute 4 (8 vs 16/s) and the
  army from minute 6 (BARb 1866 vs our 129).
- **Next (the opener/start model):** winners take 3 extractors by 60 s from a start next to a 3-spot cluster because
  the commander then boosts the lab: a boosted lab (150 + 300 build power) draws ~3x a lone lab's metal. Our opener
  and start choice plan for an unboosted lab, so after one extractor and a solar they build the lab and every later
  extractor is a 500-1300 elmo walk (Canis, round 35). Model the commander's boost in the opener's draw and the
  start choice, then re-test.
