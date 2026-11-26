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
- Tried and reverted: planning the opener for the boosted lab's draw. The lab came at ~3.5 min (the opener waited for
  an income the commander alone can't reach) and there was no army until minute 8. Winners take 3 extractors early
  because the spots are near their start, so the lever is the start position: the start choice still prefers a
  central start, 500-1300 elmos from later spots, because the expansion tail over the whole map outweighs the first
  minutes' walks.
- **Start position experiment (Canis River, one game each):** the players' cluster start (2464,5696), forced for one
  game, against the model's choice (2960,5296). Cluster start: 8 extractors at minute 4 (vs 4), 21 / 4 factories /
  army 3632 at minute 12, 26 extractors / energy 1496 / army 6407 at minute 16 (winners 28.9 / 1567 / 7807), army
  6108 vs BARb's 4670 at the end; lost on points (structures). The model's start (best earlier game) collapsed after
  minute 12. The start model is wrong: it still scores the central-forward start 1.5% higher. Suspect raid exposure
  (a forward start is nearer the enemy; the model counts only the first raid). Next: value repeated raid exposure in
  the start choice, then re-run the comparison.
- **Fixed matchup (Anarva Armada vs BARb Cortex, Canis River, one game each):** the commander now judges catch time
  by the enemy's current speed (a raider shooting buildings stands still). Extractors lost before minute 8: 8 -> 1;
  lab lost at 13.6 min instead of 3.4; minute 12: 16 extractors, 4 factories, energy 734, army 3321 (winners 26.6 /
  2.5 / 1021 / 5027). Lost at minute 14 to BARb's push (Pounders, Incisors, Brutes, Mist).
- **Next:** (1) scouts overbuilt - 52 Fleas from minute 8 to 14 (winners build ~1 per game); a scout's value must
  count its expected life and the scouts already out. (2) against Cortex's splash and fast raiders the lab still picks
  Pawns (78); Hammer/Rocko land 15-28% of shots on fast raiders. Check what Armada players field against Cortex in
  the replays (unit time map by matchup) for the reason, then the decision.
- **Armada vs Cortex, players' reason (replays.db, 28 Armada winners vs Cortex):** by 8:00 they build ~17 Pawns, ~10
  Blitz and ~6 Rovers (vehicle plant), **6.2 light laser towers**, 2.8 Fleas. Anarva in the same matchup: 0 towers by
  8:00, a 2nd and 3rd bot lab instead of a vehicle plant, 52 Fleas from minute 8 to 14.
  Causes to fix: (1) a tower is valued at one raid's expected loss, but Cortex raids repeat - it protects against
  every raid over the horizon (loss rate at the spot x horizon), so valued tower orders never beat an extractor;
  (2) the second factory is always another bot lab (BestLab); players add the vehicle plant for fast raiders;
  (3) scout overbuild.
- **Towers vs Cortex:** valued over repeated raids now (raids per horizon = horizon / raider round trip), and the
  energy switch no longer takes builders off valued jobs. Still 1 tower by 8:00 from 10 orders: no tower order fails
  ([ANV-BUILDFAIL]); they expire untaken - a job's lifetime is the minimum walk + build, so a tower that loses a few
  job comparisons expires before a builder is free. Next: a valued tower keeps its claim for as long as the danger it
  answers lasts.
- **Tower orders, traced with [ANV-TOWEREND]:** fixed three causes (pre-emptive orders live for the horizon; not
  auto-aborted for an unsafe path - towers go where raids come; an untaken order yields to a better site). Still 1
  tower by 8:00 against Cortex (players 6.2): the valuation itself. A site's expected loss = value x its share of all
  exposed value x raids per horizon concentrates on the best site; others sit barely above a tower's cost and lose to
  an extractor's horizon yield. Missing: what a tower kills (raiders' value) and the constructors it keeps alive.
  Next: value a tower by the raiders it would kill over the horizon as well as the loss it prevents.
- **Geothermal at 2:53 (cmd_m13):** all 300 E/s priced at the short-energy price made a 560-metal geo 2122 from base
  beat every extractor (killed 6:12; 5 extractors at 4:00 vs winners' 9). Winners' first geo: 5:15 earliest, 10:37
  mean, Canis 13:41 (replays.db, 31/107 1v1 winners). Fix: energy is worth pE up to production's need, the rest at the
  converter price; plants get the same site keep as extractors. That alone under-planned energy (133 E/s at 8:00,
  stall from 7:00) because the plan ignored the bank; it now counts income + bank / horizon (cmd_m15: one stall, at 14).
- **Towers, still 1 by 8:00:** a raid now clears several sites before it's answered and a tower counts the raiders it
  kills; orders are still worth 106-222 vs a cost of 94. Root cause: an extractor's own value ignores its raid risk
  (only the distance keep), so the tower that keeps it alive can't look worth it. 8 extractors died before 8:00 to
  Grunts/Instigators (cmd_m15). Next: price an extractor by its measured expected life at its site (ANV-JOBS producer
  life, 380 s), and a tower by the life it adds to the producers in its reach.
- **Metal price, continuous (cmd_m17 vs cmd_m16, Armada vs Cortex, Canis):** "metal floats" only fired when the bank
  would fill within one job; 1100/1250 at 10 M/s read as not floating, pM stayed 1, extractors beat turbines while the
  lab waited for energy. Now pM = spend / (income + bank/horizon once producing). Extractors built by 4:00/8:00 5/11 ->
  8/14, metal income at 8:00 17.6 -> 21.3, energy 331 -> 420 (winners 521), first construction turret 5:15 (winners
  4:42). Still lost (min 14): army 108 at 4:00, 702 at 8:00 vs winners 660/2044. Tower kills now limited by raiders
  seen (not 1): order values 192-337, still 1 tower by 8:00.
- **Army trades, self-reclaim (cmd_m19-21, Armada vs Cortex, Canis):**
  - Constructor value x the metal share we spend (script `Economist::MetalShare`, via the new `AiSmoothMetalPull`).
  - Unscouted raid spots expect the towers-per-extractor seen at their mean threat: ten lone Pawns at 5:40 had died
    to light lasers (3 kills / 193 losses); next game raids went 4-19 strong, 35 / 115.
  - EcoReclaim tore down new turbines at 2:29 and rebuilt them (metal back counted in full with 580 banked); now the
    metal back is priced at the metal share. cmd_m21: metal income 17.7 / 30.6 at 4:00 / 8:00, extractors 8 / 17,
    3 towers by 8:00, army 2416 at 12:00 (winners 5027); still lost at minute 14 (losses 1451 and 2435 at 10:00 and 12:00).
- **Army and commander, 2026-11-26 night (Armada vs Cortex, Canis, one game each):**
  - Ops sum each unit's threat x its SurfPower against the seen mix (EffThreat); army at 12:00 2430 -> 2862 -> 3510.
  - Commander: one test to start and keep a fight (CommNet); death risk from current health (was max) and from
    focus fire while the fight is won, shared among our units standing in the enemies' range now. Winners'
    commanders have an enemy within 600 only 4-9% of the time (replays.db comm, 1v1 winners). cmd_m37: the commander
    survived to 20:00 for the first time; the army collapsed at 9-10 min (lost 797 + 1382) and the base fell by 15.
  - Factory choice vs the enemy seen and scouts by per-cell survival: still a bot lab (Pawns 0.07-0.11 vs Flash
    0.06-0.11); Fleas 50 -> 0 by 14:00.
  - Open, in order: the army's collapse at 9-10 min vs Raiders/Levelers (composition and where it fights); the
    bank full again from minute 8-11 in most games (build power); towers still 1-4 by 8:00 vs 6.2.
- **Ops and commander, continued (cmd_m40-42):** ops infer the defence from their own losses (square law: strength x
  metal lost / killed) - 10-26 pull backs per game instead of 0; the commander's fight risk is the highest of where it
  stands, half way and the target (it had walked past Thuds toward a resurrected Pawn). cmd_m42: the commander
  survived until BARb's push reached the base at 14:13 (army 2592 at 13:00, lost 4767 in minute 14).
  Earliest gap again: 3 / 6 extractors at 4:00 / 8:00 (winners 9 / 19) with 500-1000 metal banked minutes 4-9.
  (Note: one headless game hung in pregame with no AI loaded, cmd_m39; batch's --minutes cap didn't stop it -
  runs are now wrapped in an outer timeout.)
- **Next (the earliest gap, cmd_m42):** in minutes 2-7.5 builders picked reclaim 361 times vs 91 extractors; by 5:00
  3 extractors and 13 turbines (winners 8 and 10.9 by 4:00). The pick log: reclaim 2.27 builder-s per metal of value,
  extractor 76 (33x worse). The extractor isn't undervalued by a slip but by a loop: its yield counts over the value
  horizon = measured producer life (~190-380 s, short because raids kill extractors), discounted by the spot's keep
  share, less 50 M + 500 E. Raids -> short life -> extractors look break-even -> fewer and undefended -> raids.
  Players break it by defending (towers 6.2 by 8:00, army presence) and holding 19 extractors at 8:00. Fix to
  reason out: value an extractor over the life it has where we defend it, and charge the defence (tower / army time)
  as its cost, instead of the life measured while undefended.
- **Army curve now at the winners' (cmd_m49, cmd_m56, committed e3ca9bd):** 5578 at 12:00 (winners 5027), 10266 at
  15:00, ratio 4-28 - yet lost: 17 kills all game, never at their base, and the commander dies (19:27, 1527 out).
- **Enemy base as a target - tried four ways, reverted:** valued at the game (ours + theirs) with its defence as the
  seen threat, the judged threat, the judged threat with a win gate, and the peak enemy army ever seen. All four games
  weak (cmd_m51/53/55/58: army 918-1836 at 12:00) vs both without (m49/m56: 4212-5578): early base attacks of 4-13
  units at 1:46-8:17 spent the army before it grew - early on even the peak seen is small. Their base needs to be
  seen (scouting) before it can be judged; Fleas are at 0 since the per-cell scout survival.
- **Commander in builder safety (cmd_m60):** its build jobs are weighed like any builder's with its loss priced at the
  game; it survived the game (4 retreats). The game was lost to a single lab: one factory all game (0:50) with 12-13
  builders, income 21-23 M/s and the bank at 1100-1400 from minute 10; the army collapsed at 11-14 (Rogues, Grunts,
  Thuds). A second lab scored 34-637 builder-ms per metal vs extractors 57-173 and towers 11-97 and lost every pick
  (winners: 2nd factory at a median 7:29, 94 of 103 games). Next: a factory is valued only by the overflow it absorbs
  (~9 M/s here) - what it adds is army, and the army is what holds extractors and wins fights. Value production
  capacity by what its units are worth to us (the Production fight value of its output over the horizon), the same
  measure the lab's units are chosen by, instead of the overflow alone.
- **Second factory and the commander (cmd_m61-69):**
  - The factory choice returned the advanced lab whenever tech allowed it (2247-3620 metal, value -1154..-3378 at the
    builders' prices), so no second T1 factory came. It now competes on that value: 3-4 bot labs per game.
  - Commander risk: escape is getting out of the enemies' reach (at home the factory was 0 s away, risk 0 in a base
    fight); the commander draws all the fire in reach (the enemy shoots the game); no fights while it escapes.
    Deaths moved but remain (14:45, 14:05, 15:44): the last one walked 1194 out to a build job - the core picks the
    commander's jobs without risk; builder safety acts only once danger is there. Correction: the job pick already weighs
    the site (CommanderTask -> CommWorth: P(death there) x the game); the risk is low where the danger is out of
    sight - a Mist outranges our sight, so a far site reads safe until it is seen. Next: the unseen part of the risk
    (CommFog) for the commander - players keep it within reach of the army and away from enemies (an enemy within 600
    only 4-9% of the time, replays.db comm), i.e. they treat unseen ground near the front as dangerous.
- **Commander deaths, continued (cmd_m71-81):** fixed in turn - the fight gain counted even if it dies; the redirect's
  safe job never held (50 redirects in 50 s 1242 out); ops pulled back on a revealed defence read from the first
  second (57227-90056) and relaunched fresh at the same group (~15 times in 40 s, 7586 lost to Levelers in a
  minute) - now the kill time gates it and pulled-back defences are remembered; the commander wasn't a defended asset
  and only raids could be recalled; the site risk counted the escape only, not the job. cmd_m75: commander alive at
  20:00, army 6060 at 17:00. Still the pattern in most games: the commander dies 1400-1800 out to Thuds / Mists,
  artillery that outranges our sight - the unseen danger (CommFog places it at their base). Next, in order: the
  unseen artillery around the front (where enemies were last seen, not their base); the composition against
  Levelers (130 Pawns lost to splash in cmd_m75).
- **Unseen enemy placed with the seen ones (cmd_m83):** CommFog measures the hidden army's distance from the known enemy
  nearest the spot (was their base). Kills/losses 78/79, the best trade yet; the commander died at home at 14:00 in a
  base overrun (15 Grunts + 7 Rogues; the army 500 away, strength 84 vs 25) - every safe place was in the fight. Next:
  the escape goes away from the danger (behind the army), not to the nearest factory when the factory is the fight.
