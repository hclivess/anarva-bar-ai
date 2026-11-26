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
- **Commander deaths, tallied (20 games, cmd_m33-85):** all at 12-19 min, mostly 13-15; killers Thud 10, Leveler 10,
  Raider 7, Rogue 3, Mist 3, Grunt 2; half near base (<650), half far out (>1000). One cause, many routes: BARb's main
  push of splash units (Thuds, Levelers) arrives at 13-15 min and the commander is in it wherever it stands.
  Escape-to-the-army (guard a soldier) took it to the front - reverted. Next: answer the push itself - see it coming
  (its direction and strength from the last-seen enemies) and meet it with the army and towers before it reaches the
  base, while the commander steps back from its path; and stop massing Pawns into splash (130 lost to Levelers).
- **Pawns into splash (cmd_m75 minutes 15-17):** Production scored Pawn 0.36-0.47 per metal vs Warrior 0.24-0.29, Hammer
  0.17-0.21, Rocko 0.11-0.14 against a mix with Levelers - the Pawn wins on dodging (enemy hit chance 0.41-0.52, as if
  it moves at top speed under fire), yet Levelers killed 130 Pawns. The dodge term also rests on a measurement (Hammer/
  Rocko 15-28% hits on fast raiders), so it is real for raiders on the move; whether massed Pawns in a fight move like
  that isn't knowable from unit facts. Next: measure each of our types' hit rate taken from each enemy type live in
  this game (the damage events), and let it replace the modelled HitChance once there are hits to count. Live game
  data, not a replay table. Script blindness to add to SCRIPT_SIGHT.md: per-shot hit/miss by attacker and victim type.
- **Live trade (committed c87b9db) and the conversion gap:** unit choice corrected by each type's live damage dealt /
  taken (Pawns x0.13 vs Levelers): the lab builds Warriors and Hammers; two games (cmd_m89, cmd_m92) with the
  commander alive at 20:00, army 14080 / 10102 (winners 12967), ratio 3-17x - both lost on points: BARb's buildings
  29343-29651 vs ours 850-1720 and its metal income 87-154/s vs ours 20-22 (winners ~37). The army never ends the game.
  Enemy base as a target, now six games with every gate tried (seen / judged / peak / win gate / their commander):
  all six weaker than the build without it - reverted for good. A base we can't see can't be judged; the army needs
  to see it (scouting, or the army's own advance as a scout) and our late economy must grow past ~20 M/s.
- **Idle army holding the most exposed producers - tried two ways, reverted (cmd_m96, cmd_m98):** at the most exposed
  producer the army went forward and was destroyed by minute 14; gated by "we win there" both games still collapsed
  (army 0 by 12-14, extractors to 0-1). The committed build (c87b9db) stays the best: army 10102-14080 at 20:00,
  commander alive. Its open gaps: raiders kill our buildings late (41 in minutes 16-19) while the army waits at home;
  our metal income stalls at ~20/s (winners ~37, BARb 87-154); the army never ends the game.
- **Inherited constant removed - unit-target reclaim (cmd_m99/m100):** every reclaim of a unit (stuck or unfinished
  ones of ours) carried a fixed cost {1000, 0} and 0 s of reclaim time, so it read 1000 metal for nothing and builders
  reclaimed 1352 times in minutes 10-16 while extractors stalled at 11-12. Now its metal x build progress, its build
  time x progress at our reclaim speed. Extractor picks 193 -> 890, extractors 22-23 at 10-12 min (winners 26.6),
  metal income 44-46 (was 27). Lost: the commander died at 14:08, 1116 out, a Gator beside it.
- **Commander at base (cmd_m102):** with the redirect's safe job held, the commander still died at base (17:52, a Pyro):
  its safe job was guarding a factory 303 from base, inside the base fight. Cause in the scoring of safe places:
  a spot's risk uses EscapeTime = the walk to the nearest factory, so a factory in the fight reads as the best
  escape and a quiet structure far from it reads dangerous. Next: escape = leaving the reaching enemies' range
  (their longest range over our speed, from where they are), not reaching a factory.
- **Ops keep the launch's catch test (cmd_m104/m106):** the army (48-51) followed one fleeing unit to their base while
  their push took ours and the commander; a running op now ends when its target is out of reach and moving away at
  least as fast as the squad. cmd_m106: commander alive at 20:00, army 8046 at 12:00 and 11669 at 18:00 (ratio up
  to 11.5) - lost on points: extractors 22 -> 7 from minute 12 to 18 (raids), their buildings 33231 vs ours 2255.
  Open: the late extractor erosion and the army that never ends the game.
- **Catch share in unit power - reverted (cmd_m108):** multiplying every unit's power by the share of the enemy it can
  catch pushed the lab back to Pawns (35, the fastest bot) and Levelers wiped the army at minute 12 (6304 lost).
  Catching raiders is a separate job from holding the fight: it needs its own (fast) units valued by the raids they
  stop - towers, or a vehicle answer - not a factor on the main army's choice.
- **Raider hunters as a production job - reverted (cmd_m110):** valued by the measured raid loss rate x catch share x
  win chance, shared among hunters: 24 of 69 units went to it, mostly Fleas and Pawns (fast and weak), the army was
  2701 at 10:00 and the game lost at 11:49. Command has no hunting role (a squad moves at its slowest), so hunters
  built were spent as weak fighters. A raid answer needs both: a unit that wins against the raider class and catches
  it, and a separate squad for it. Until then towers (covered producers live 1240-5572 s vs 171-308 uncovered).
- **Why the strong army sits idle (cmd_m111, skip log):** a raid spot is worth one extractor (~750) and its defence
  counts every enemy that can reach the squad on its way (40-67 of our ~100): every raid read -2000..-4000. Valuing
  the enemies on the way as gain too (cmd_m113) launched 22 raids from early on and the army never grew (518 at 12:00)
  - reverted. The mismatch is real but the cure has to be the defence side: what fights the squad on a long walk is
  not their whole army (it can't be everywhere), and an early raid must not trade the army's growth for one spot.
  Pattern of the last ten tries: targeted fixes of inconsistencies held; every change that adds aggression or a new
  role regressed in its first game. Single games vary widely - changes of that kind need several games each.
- **Raid defence sampled along the path (cmd_m115 g00):** an enemy counts where it can reach the path by the time the
  squad is there (now / half way / target) instead of Cover(squad, whole walk). Armada vs Cortex: commander alive,
  army 12796 at 20:00 (ratio 14.5), extractors 20 at 12:00, our buildings 4535 at 20:00 (baseline 850-2255), 13 raids
  without an early bleed; points loss (their buildings 28429). Note for testing: `--games 2` swaps seats - g01 had
  Anarva as Cortex (a different matchup: 139 raids, 125 pulled back). Compare like with like by repeating
  `--games 1` runs.
- **The real trade (cmd_m116, 35-minute cap, ended 19:11 with the commander):** damage taken 133978 vs dealt 59937
  (0.45), units killed 29 vs lost 208. The Director's ratio (2-17 in strong games) compares our army with the enemy
  army in sight, so it flatters us whenever theirs is unseen; the harness dmg_out/dmg_in is the honest yardstick.
  The gap to close is the trade itself (how and where our army fights), before conversion or scoring.
- **Their commander (cmd_m118 damage log, cmd_m120 test):** BARb's commander dealt 91731 damage to our Pawns in one game,
  more than all other enemies together - it fights at the front, and its death would end the game. Valued at the game
  when all our free strength beat its defence: 7 ops went for it, it survived, trade 0.33, lost at 14:01 - reverted.
  Its threat (D-gun, 3700 hp) is underrated by the generic threat number; the live trade per enemy type (damage it
  deals us / damage we deal it) is the honest measure of what it takes, and the next thing to wire into its defence.
- **Live enemy threat (cmd_m122) - reverted:** each enemy type's threat x sqrt of its live trade against us over the
  average made every defence larger; the army avoided fights, the base fell, lost at 11:35 (trade 0.37). The tallies
  stay exposed (AiDamageFrom/To). Of the last 20 tries, the changes that held were fixes of inconsistent or inherited
  logic (reclaim 1000, keep vs launch tests, rez pool, escape time); every change of how bold the army is regressed.
- **Fire order by dps per remaining health (cmd_m124, cmd_m125, two like-for-like games):** units shoot the armed enemy
  in reach with the most dps per health left (Lanchester's order), buildings after; was metal value per health.
  Trade 0.85 and 0.95 (the five games before: 0.45-0.89), commander alive in both, army 5846 / 13390 at 20:00 -
  both points losses (their buildings 27465-31728 vs ours 3605-4072). The trade is now near even; the economy gap
  (our extractors fall to 7-9 by 20:00, their income 87-239/s) decides the points.
- **Towers not one at a time - reverted (cmd_m127/m128):** 29 of 38 producers were lost uncovered (covered live 1364 s
  vs 152 s, cmd_m125), so the one-order-at-a-time tower gate was dropped: two games, trade 0.49 / 0.47 (the build
  before: 0.85 / 0.95), the first lost at 16:30 with 2 extractors at 8:00; towers 5 / 16. Builders on towers are
  builders off extractors early; the tower rate needs the builder's time weighed, not just the site's value.
- **Tech 2 (cmd_m129-m132) - reverted:** BARb's income runs 87-239/s on upgraded extractors, ours 20-40; we never build
  the advanced lab. Its tech gate wants the lab's cost banked (it costs more than our whole storage) or moho payback
  under the next extractor's (always 28 s, raided spots reopen). Affordability over the build time and the moho
  upgrades in the factory value: the gate passed once (payback 68 s vs horizon 153 s) but no advanced lab was built,
  and the two games traded 0.63 / 0.51 (vs 0.85 / 0.95) - reverted. The core's factory job ranks the lab by
  build-power value only (negative), so even an approved T2 lab loses every builder pick: the core needs the same
  upgrade value the script computes.
- **Tech 2, second try (cmd_m133-m135) - reverted:** upgrade value shared by the factory choice, the tech gate
  (affordability over the build) and the factory job (AiTaskAdded sets its value). The gate approved the advanced lab
  once, but no tier-2 factory job was ever created, so nothing carried the value and no lab was built: the step from
  "allowed" to an enqueued factory job (core FactoryManager / AiIsSwitchTime) is where T2 stops. Next: trace that step.
  Also learned: cmd_m131/m132 (no lab built either) traded 0.51-0.63 vs 0.85-0.95 for the same effective behaviour -
  single-game variance is that wide.
- **Tech 2 path wired end to end (cmd_m136):** our tech decision names the next-tier lab itself (NextTierLab: our
  constructors' build options) for both the switch and the factory choice (was BARb's config pick, never higher tier);
  the factory value and the factory job carry the extractor-upgrade value; affordability is judged over the build.
  The gate still answers "not yet": moho payback 154-179 s vs the next extractor's 28 s, and the surplus doesn't cover
  the lab during its build. With the gate closed play is unchanged. The decision now rests on that return-rate
  comparison: whether the next extractor's 28 s should count its measured short life (uncovered producers live
  ~150 s) - an extractor that dies before it pays twice isn't the better investment.
- **Other maps, same build (Armada vs Cortex):** Gasbag Grabens lost at 15:50 (trade 0.45, commander dead), Feast of
  Hades lost at 17:52 (trade 0.51, commander dead) with the winners' economy (26 extractors, 53 M/s at 12:00) and an
  army of 15456 at 16:00. The gaps are not Canis's: the fights lose ~2:1 and the commander dies when the fighting
  reaches it. Those two decide every game; economy and army size are no longer the gap.
- **Trade from live damage (cmd_m138/m139) - reverted:** Assess::trade = (killed + owned metal) / (lost + owned metal)
  reads ~0.8-1.0 while the damage exchange runs 0.45-0.89 - the prior (all we own) swamps the evidence. Replaced by
  damage dealt / taken from the per-type tallies shrunk by our army's health: two weak games (lost at 16:00; economy
  to 0 extractors by 16:00). The tallies are biased: damage from unseen attackers ('?') isn't counted, so the AI read
  1.6 while the real exchange was 0.67. A trade input needs all damage taken (the harness's dmg_in counts it).
- **Honest trade, all damage counted (cmd_m140/m141) - reverted:** with all damage taken in the tally the AI read
  0.6-0.7 (honest) and both games were lost at 13:00 (trade 0.47 / 0.31). Knowing it loses fights, the army waited
  while BARb grew. The measurement is right; acting on it by caution alone doesn't win - the fights themselves must
  get better. Core fix kept (AiDamageFromAll = all damage taken).
- **Splash lanes and their commander's live threat (cmd_m143-m147) - both reverted:** lanes one enemy aoe apart:
  trades 0.53 / 0.53. Their commander dealt our Pawns 163168 in one game (cmd_m144); its threat scaled by its live
  trade alone took it off the top of the damage log, but the trade stayed 0.56 / 0.46 and both games were lost -
  Grunts, Gators and Rogues took its place. Every single lever moves the losses to the next enemy unit.
- **Game value = ours + theirs (cmd_m149/m150) - reverted:** pricing a lost game at what we own plus what we'd take
  (all commander risk tests, the last factory, a threatened commander): the commander still died (15:20, 19:26),
  trades 0.75 / 0.60. Its deaths are not a pricing question at the margin - the commander is in the fight because the
  fight comes to it (base pushes) or because its jobs are where the fighting is.
- **Against BARb as Armada (cmd_aa1, Canis):** lost at 13:13, trade 0.68, commander dead - the same failure as against
  Cortex and on the other maps. Across three maps and both BARb factions the two decisive gaps are the same: fights
  trade ~0.5-0.95 against us, and the commander dies when fighting reaches it (13-19 min).
- **Experiment - the commander never fights (cmd_nf1/nf2):** CommDefend off; the commander still died (17:10 at base,
  15:34 1228 out) with 0 fights. Its deaths aren't caused by its fight decisions: it is killed where it works when
  their army arrives. The answer is the army's: meet the push before it reaches the commander, or keep the commander
  where the army is between it and them.
- **Route-aware safe place (cmd_m152/m153) - reverted:** the commander's safe job scored on the risk half way as well
  as at the destination: trades 0.49 / 0.55, one economy collapse (army 0 at 20:00), one commander death at base.
- **Concentration kept (cmd_m155-157, #93):** stragglers join the squad's centre before fighting; trades 0.84 / 0.63 /
  0.77, no regression. **Combined build reverted (cmd_all1-4):** tech gate by return over life, raid value, choke line
  and turret by fight model together: 0 Flashes, no T2, up to 31 light lasers, economy collapsed (5-12 extractors).
- **What winners field (replays.db):** Canis winners by 12:00: 22.9 Flash, 21.7 Pawn, 8.2 Flea (fast raiders); Feast
  winners (mostly Cortex): 46.9 Gators. Defences: ~10-13 light lasers by 12-16 min plus heavy lasers, AA, mines -
  light lasers are what players build. The gap is the army: theirs fast raiders in numbers, ours slow Warriors/Hammers
  from a bot lab; the opener picks the bot lab by strength per metal, so the vehicle plant (Flash) never comes.
- **Raid value reverted (cmd_lab2-5, Canis, Armada vs Cortex).** Per-raider bound: 89/235 Fleas, economy gone. Marginal
  (shared open spots): 20/16 Fleas, trades 1.21 / 0.69, but extractors lost by 8:00 rose to 10 and 9 (vs 4 and 9 without:
  cmd_m155/156) and income fell to 14-16 M/s - production spent on raiders left our own spots unanswered. Extractors
  built by 4/8/12 min: ours 6-7 / 15-19 / 28-29 (cmd_m155/156) vs Canis winners' median 9 / 22 / 30 (replays.db): the
  earliest gap is the opening's expansion rate, before any raid.
- **Opening: extractor before lab, enemy lab by symmetry (op0-4, Canis, Armada vs Cortex).** The opener took the lab
  the moment it was affordable (28 s) and the first constructor a tower at 109 s against a lab-first raid estimate
  (99 s; BARb's first unit came at 2:00). Now an extractor the commander builds first is weighed (its yield until the
  lab's first constructor could reach it vs the lab's production lost), and the enemy's lab is expected when ours stood.
  Lab 59-97 s (winners ~61), first tower 207 s (winners ~217). Extractors built 4/8/12 min: 8/15/24 and 5/18/29 (before
  6-7/15-19/28-29; winners 9/22/30); income at 12:00 40 and 50 (before 41-45). Both lost: op3 on points, op4 by the
  commander's death at 12:28 with 25 extractors standing.
- **Commander fight exposure (op5-6):** P(death) at the target now counts the fight's time under fire plus the escape
  (escape alone let it fight Levelers 1561 out at stake-risk 36, op4). Both still lost with the commander dead, but
  after the army fight was lost: op6 defended the base against Thuds 759 out (stake 6260, trade 0.49), op5 had no
  army left by 16:00 (trade 0.30). The deaths follow the army's trade, which is the gap now (0.3-0.85 over op3-6).
- **Unit mix per enemy type (sp1-2):** a unit is valued by what it adds in a separate fight against each enemy type seen
  (WinShare saturates where a matchup is won); splash and hit chance weighted by the damage each enemy deals. Before:
  84-107 Pawns and nothing else (owner: "do you build anything else than fucking ticks?"); now Pawns, Maces,
  Centurions, Rocketeers, Flashes, Pincers, Stumpies (sp2, t2e-g). Income at 12:00 up to 58-65.
- **Tier 2 reaches the game (t2a-g).** Four blocks found in turn: (1) the gate compared against the next extractor and
  "banked" metal - production spends all income, so never; now the upgrades' return (producer life after the build /
  payback) against production's best value per metal; (2) producer life before any loss was the sum of all exposures
  (10575 s at 2:00 - lab from 2:00, army starved, t2a); now the mean age; (3) payback lacked the T2 constructor and
  the time until lab + constructor + upgrades stand; (4) factory.as also required FactoryValue > 0 (overflow it lets us
  spend), always negative for an advanced lab - the gate stood open 7 min with no lab (t2d/e). Now: advanced lab at
  9:23 / 11:57, first upgraded extractors 13:15 / 13:52, 6 and 3 by 15-18 min (t2f/g) - replays.db 1v1 winners: lab
  10%/50% at 8.4/12.7 min, first upgrade 9.8/14.8 min (107 winners, 34 ever upgrade). Both games lost (trade 0.52 /
  0.69), the commander dead at 18:32 and 15:33.
- **Where the army dies (t2e-g):** mostly within 1000 of our base after 12:00 (t2e: 13571 of ~15000), while ops lost
  ~1000 a game. Command sent every free unit to any defended target: all 66 units to a raid spot worth 614 at defence
  2.5, five times in 8 s (t2e 12:56). **Tried and reverted (tm1-2):** a unit joins an op only while its added gain beats
  its metal x time away / horizon - ops shrank to 1.1 units per raid and 5.6-8.9 per enemy op, but trades 0.43 / 0.64,
  income 12-20 at 8:00, both lost: units left out of ops get no defending orders, so the army only fought in smaller
  pieces. The gap is that idle units at home don't hold a position or gather; that needs a defence posture, not
  smaller ops. #60 (retreat at 50% health) checked: already live in the core (ShouldRetreat), config ignored.
- **Grouped reinforcements and commander walk-out, reverted (rf1-3, cs1-3).** Free units joined a running fight only as a
  group stronger than what can reach their path (waits 8-24 per game): trades 0.66 / 0.79 / 0.50 / 0.35 / 0.52 / 0.49,
  all lost - no change from ~0.55-0.6. The commander's "walk out of their reach" safe job fired 0 times in 3 games: its
  deaths came where it stood outside every known enemy's reach (Reaper at 823, an unseen attacker 2651 out, a
  Leveler at 318), i.e. from enemies not seen in time, not from a missing escape. Six games of the same code ranged
  0.35-0.79: single-game differences of this size are noise.
- **Radar (#99, owner raised it three times):** Brain::Radar values a radar by what it covers that isn't under radar
  (the commander at the game's value) x the unseen share of the enemy ((ours - seen) / total). rd1-3: 3-4 radars per game,
  first at 1:22 / 2:16 / 1:42 (1v1 winners: median 3.3 min, 5 by 12:00). Trades 0.56 / 0.55 / 0.60; rd3 the closest
  game yet (pts loss, army 5600 vs 6900 at 20:00, commander alive); rd1/rd2 commander dead at 202-415 from base.
  Facts gained: RadarRange, CloakCost, CloakCostMoving, DecloakDistance (gen_facts.py); CmdCloak bridged.
- **Commander home + cloak (ck1-3, #65/#99):** deaths at 13:56 / 19:30 / 18:00 (was 12-15), two at 194-226 from base
  (base overrun), trades 0.46 / 0.77 / 0.76; cloak used (risk 2-54 vs energy ~1 metal-eq/s). But unwatched-ground refusals
  (43-206) kept the commander off early extractors: 4 at 8:00 in ck2/ck3. Fixed: ground is known empty before the
  earliest enemy raid can arrive (Opening::raidArrive). Granularity (#101) added in the per-type fight value.
- **Batch bt1-3** (commander known-empty ground before raids, upgrade constructors within life, anti-nuke after a
  silo could exist, granularity #101): trades 0.45 / 0.94 / 0.49; bt2 the closest yet (pts loss, army 7203 vs 7641 at
  20:00, commander alive); bt1/bt3 lost at 12:00 (commander at 1247 and 168). No anti-nuke built (was 14 picks at 13 min).
  No T2 lab in any of the three. 4 extractors at 4:00 in all three: the opener now takes a third extractor first (spot 49,
  ~20 s path detour on Canis) and the lab stands at 86-101 s.
- **Upgrade assists (#102, owner):** the core refused extra builders on any job its current build power finishes within
  BARb's goal build time (config constant) - no T1 constructor ever joined a T2 extractor upgrade. Removed; the join value
  (W/B - W/(B+b) at the job's yield) decides. An upgrade's yield is now the extra over the extractor it replaces (was its
  whole output, ~4/3 too much).
- **Tier 2, staggered upgrades at all build power (as1-6):** as1-3 (before) never opened: the payback counted all n
  upgrades by one constructor before any earned (1251-1820 s). Now upgrade k earns from k x tau, tau at all our build
  power (#102 assists). as4-6: gate opens again, labs at - / 14:56 / 7:34, still no upgrade by the end; all lost (0.82 /
  0.75 / 0.43). as6: income 75.6 at 12:00 (our highest) with an army of 162. **Next:** ProducerLife is floored by
  Horizon() (the earliest the enemy could take all we own), which is huge early: the gate read 36x vs the army's 24x and
  opened at 1:48 (as4). The floor must not make an early life look long.
- **Tier 2 on measured life (ml1-3, mu1-3):** the tech gate uses the producer life measured in this game (exposure /
  losses, or mean age), not floored by Horizon(): it opens at 3.8-5.1 min, labs at 9:34-12:39, first upgrades 13:31 and
  15:23 (mu2/mu3) - replays.db 1v1 winners: lab median 12.7 min, first upgrade median 14.8. Upgrade-spot rejections are
  logged ([ANV-MEXUP]). All games still lost (trades 0.38-0.64): T2 timing now matches the winners; the army's fights don't.
- **Units fight what is in reach (fr1-3):** Command moved squads with plain moves; units with an enemy in reach didn't
  fire in 20-35% of contact samples (mostly Pawns beside Gators on group moves: forward-arc weapons can't shoot what
  they walk past; [ANV-IDLE], id1). Now a unit with a visible enemy it can hit attacks the one with the most damage per
  remaining health (retreats excepted). Trades **1.23** / 0.92 / 0.75 - the first above 1; fr1 army 10685 vs 4590 and
  fr2 6909 vs 6341 at 20:00, commander alive in both, but both lost on points: their buildings 37785 / 28174 vs ours
  3968 / 2990. The stronger army never pressed their economy. Next: attack when ahead.
- **Square-law defence memory (sd1-3):** a pull-back's revealed defence is S x sqrt(lost/killed) (square law, as
  FightGain prices loss) and is forgotten when the place is in sight again; max skip defence 23-370 (was 34795, fr1).
  Trades 0.78 / 0.97 / 0.78, armies near even at 20:00 (5543 vs 6141, 5747 vs 6711), but extractors fall 10-12 -> 3 and
  buildings 1065-3880 vs 28-29k: the loss is now our economy, not the army.
- **Towers at raided extractors (tw1-3):** the core skipped every non-urgent job where enemy influence was negative, so
  tower orders at raided extractors stood untaken (up to 139 s) and were replaced unbuilt. Lifted for defence jobs (the
  builder's risk is weighed by builder safety). Towers by 8/12 min: 4/7, 2/3, 3/4 (was 1/4, sd3; winners 6.2 by 8:00).
  Trades 0.64 / 0.42 / 0.62, all lost; extractors still fall (lost 14-23 per game).
- **Path-length opener (pl1-3):** the commander's walks are priced by the engine's path length (bridged AiPathLength);
  the lab at 60-61 s (winners ~61) in two of three. pl3: 25 extractors and 50.8 M/s at 12:00, army 2x BARb's at 20:00
  (17186 vs 8315) yet lost on points (buildings 5085 vs 28810): "army idle while stronger" minutes 12-20.
- **Fight gain by the square law (sq1-3):** FightGain read WinShare S/(S+D) as a win probability - a squad 5.5x the
  defence carried a 15% chance of losing everything and pulled back from undefended raid spots. Now the stronger side
  wins losing metal x (D/S)^2, the weaker loses all and kills (S/D)^2. Army idle while stronger: 1 minute per game (was 9).
  sq2 the closest yet: trade 0.99, 97 M/s at 16:00, buildings 15820 vs 29276, army 7314 vs 8200 (pts loss). Pull-backs
  still 54-103 per game.
- **Outranged units close or leave, reverted (or1-3):** a unit inside a visible enemy's reach but out of its own
  closed on it if faster, else left its reach. Outranged hits 5-14%, standing still under fire 9-12% of contacts
  (before 5-23% / 5-15%): no measurable change; trades 0.83 / 0.52 / 0.87, all lost (or1 buildings 10850 vs 24830).
- **Early army gap (replays.db, 107 1v1 winners):** army 602 / 1110 / 2010 at 4 / 6 / 8 min vs ours 108-267 / 270-324
  / 486-810; income 19 / 31 / 41 vs ~10 / 16-23 / 29-33. Winners lose ~2 extractors by 12:00 (ours 14-23); only 40% of
  theirs have a tower within 400 - the army holds them. Their commanders REPAIR (assist) 33-39% of minutes 1-5.
- **Commander assists the lab, reverted (ca1-3):** valued at its build power x the lab's metal per build-second, capped
  by spare metal, x production's value per metal. It took the commander off expansion (3-4 extractors at 4:00), all lost
  at 13-17 min, commander dead in all three. Assisting only pays with the income to feed it; ours is half the winners'.
- **Opener: extractor-first charged the simulated lab delay (ob1-6):** the lab now stands at 50-67 s (was 60-119);
  all three full games lost (trades 0.6 / 0.52 / 0.89), 3-6 extractors at 4:00 (winners 9).
- **Start position (st0-1):** Canis winners stand at the centre of a triangle of three spots 127-179 away (e.g.
  (2525,5854), (1634,5323)) and build them at 9/16/23 s; our candidates (cluster averages of 4-5 spots) never included
  it, and we chose (2464,5696), 51 from one spot and 248 from the next. Each spot's triangle with its two nearest is now a
  candidate: (2528,5877) scores 132244 vs 128689, and the pick became (1627,5323) - a winners' start. But from there the
  opener builds one extractor, a solar and the lab: the extractor-first test compares "extractor then lab" with "lab
  now" and the extractor's energy makes the lab wait; winners build extractor x3, solar x2, then the lab (~61 s). Next:
  weigh short sequences (extractor, plant, lab), not single steps.
- **Opener sequences, reverted (st2-5):** trying extractor -> plant -> lab in the extractor-first test left one extractor
  before the lab; charging the lab's delay only past the earliest raid gave three commander extractors but 30 s apart
  (13 / 43 / 77 s) and the lab at 101-105 s, and moved the start pick to (2400,6000) with 300-380 walks between spots.
  Income at 4:00 9.9 either way (winners 19). The opener's single-step tests interact with the start valuation; a
  short-sequence plan (the retired rollout planner) is the next approach, not more single-step terms.
- **Bounded opening plan search, reverted (sp1-4):** before the lab, every plan of up to three steps (the three nearest
  extractors by path, energy plants) then the lab, scored by the plan value. Re-planned each step, the lab never came
  (8 extractors and 16-20 M/s by 4:00 - the winners' income - but no lab, no army); committed to the taken plan, four
  extractors then the lab at ~134 s (worse than the committed opener's lab at ~52 s). The plan value counts resources
  gathered and nothing of the army needed by the earliest raid, so more extractors always beat the lab. The opener
  plan value must count the army the raid needs (#41 just in time) before a sequence search can help.
- **#103 raid term (dr1-4):** producers beyond the commander's defence reach (its speed x the producer's health over a
  raider's dps + its range) meet the raid with only the lab's units. Start picks: the two triangle centres Canis
  winners use ((1627,5323), (2528,5877)). The re-applied plan search still chose four extractors and the lab at ~108 s
  (these spots are within reach, so the term charges nothing): planner dropped again, the term kept. What stops
  players at three extractors is the army needed by the first raid, not losses beyond reach.
- **Lab only once energy covers its draw, reverted (en1-5):** 4-minute checks looked better (13.9-15.7 M/s, 6-8
  extractors, 82-84 E/s at 2:00), but in full games the lab stood at 75-87 s and extractors at 4:00 were 2-4; trades
  0.72 / 0.59 / 0.56, 17-22 extractors lost, all lost; the checklist's first gap became "no factory at minute 1". Winners
  have both by minute 1 (the lab and 79 E/s): with 2-3 extractors and two solars before the lab, which our single-step
  opener can't reach without the army-by-raid term (#103/#41).
- **Constructor queue in the extractor-first gain, reverted (cq1-2):** charging each spot the wait for every open spot
  nearer the lab made far spots look most valuable: the commander walked off, no lab by 4:00 (2-3 extractors, 5 M/s).
- **First lab by plan value (vehicle plant), reverted (vp1-5):** choosing the lab by the plan value (constructor speed in
  TailGrowth) picked the vehicle plant (armcv walks 54 vs 36). Army at 4:00 doubled (330-361) but extractors stayed 1-6
  through 12:00, income 4-23, all three lost at 17-19 min with the commander dead (trades 0.69 / 0.56 / 0.63): the
  constructors didn't expand faster in play, and production went to Rovers, Flashes and mine layers.
- **Commander division of labour, reverted (dv1-2, #105):** on a walk-dominated job (walk > its build time) with a
  constructor around and energy short, the commander built the best plant at base instead. Triggered 3-6 times, but
  3 extractors and ~8 M/s at 4:00 (no change): the first constructor came at 111-128 s, so there was little to divide.
  The constructor timing itself (the lab's first products) comes before the division.
- **Commander near base by comparative advantage, reverted (dv3-4, #105):** walk-dominated jobs left to constructors,
  the commander on base energy or assisting the lab (11-13 times a game). No change: 3-4 extractors and 8-10 M/s at
  4:00, 8-9 units. dv4 had four constructors by 142 s and still 4 extractors by 4:00 - the constructors don't expand
  (their picks go to radar, towers, winds). The constructor job choice is the next piece of #105.
- **Radar from the earliest raid (rr1-5):** nothing hidden can be near before the earliest enemy raid can arrive, so a
  radar is ordered only when it would stand by then. First radar 152-197 s (was 80-136 s; winners' median ~198 s,
  replays.db). Full games rr3-5: trades 0.77 / 0.82 / 0.79, all lost at 17-18 min with the commander dead near base;
  rr5 reached 26 extractors and 54.6 M/s at 12:00, 89 at 16:00. Kept (timing matches the replays, no regression).
- **Both halves of the division of labour together, reverted (cd1-7, #105):** constructors redirected from jobs that
  cost them relatively more than the commander to the nearest open extractor; the commander kept at base on energy or
  the lab assist. 4-minute checks: 11-13 units (was 8-9), 6 winds, but 3-4 extractors; full games cd5-7: extractors
  1-7 all game, trades 0.63 / 0.36 / 0.39, all lost (12, 15 min, pts). The redirect enqueued extractor jobs at the
  nearest open spot regardless of whether it could be held; outer spots died (10-18 lost) and income never grew.
- **Plan over within-reach spots and plants, reverted (nr1-2):** restricting the commander's pre-lab plan to spots
  within its build reach plus plants brought back "energy forever": solar after solar, no lab by 4:00 (re-planned each
  step, "one more plant then the lab" always beat "the lab now"), and the start moved to a corner. The plan value
  rates any producer before the lab above the lab: it must count what the lab's units are worth by when they are
  needed (#103/#41) before any search over it can work - the core of the #105 design.
- **Committed within-reach opening plan, reverted (nr3-9):** with the plan taken followed and the pool limited to spots
  where the walk is shorter than the build (+ plants), the commander builds three extractors at 13/35/48 s and one solar,
  the lab at 69-97 s. Full games: trades 0.52 / 0.66 / 0.63, all lost; nr7 29 extractors and 57.7 M/s at 12:00 (pts loss).
  4:00 income still 8-10: the first minute isn't where the 4-minute gap is.
- **Replay walk-through (winner d346036b, Canis) vs ours (rr5):** their lab makes 2-3 constructors then a Tick about every
  3 s; constructors claim 10 extractors at 700-1660 from start by 4:54 with towers/radar forward; 165 E/s at 2:00. Our
  lab made 7 constructors by 4:18 and almost no army (54-108), constructors claim <1 extractor each.
- **Army composition vs players (28 Armada-vs-Cortex 1v1 winners, faction from the commander):** metal per game
  559 / 2251 / 4590 / 6478 by 0-4 / 4-8 / 8-12 / 12-16 min vs ours 233 / 1180 / 3949 / 4841. Theirs: Pawn/Rover/Flash
  early, Flash 42% at 4-8, Stumpy 25-32% and air from 8 min. Ours: Centurion 61-72% from 4 min (speed 45 - catches
  nothing). Per-type fight value dropped the speed/reach factor: next fix.
- **Reach factor in the per-type value, reverted (rc0-3):** each unit counted against an enemy type only by its speed
  over theirs. From a bot lab alone that means 100% Pawns (rc1-3), trades 0.77 / 0.67 / 0.30, all lost at 17-18 min
  with the commander dead. The winners' mix (Flash, Stumpy, air) needs a vehicle plant and air, so composition and
  factory choice move together.

## State at the end of 2026-11-26

Kept: fights (in-reach fire, square-law pricing, decaying revealed defence), radar timed to the earliest raid, towers
at raided extractors, tier 2 by measured return with assisted upgrades, the commander's watched-ground rule and cloak,
granularity and per-type unit value, path-length walks in the opener, triangle start candidates. No 1v1 win yet:
the first four minutes are at half the winners' income and army, and extractors are lost from minute 6. What helped
and what didn't is consolidated at the top of CLAUDE.md; the opening design is on issue #105.
- **Constructors on non-extractor jobs counted as spare, reverted (cv1-5):** the lab made 4 constructors instead of 7
  and 11-15 Pawns by 5:00 (army 324-648 at 4:00, was 54-270), extractors lost 10-13 (was 14-23); but with 2-4
  constructors by 8:00 that still don't claim extractors, extractors stayed 2-11 and income 6-37; trades 0.80 / 0.63 /
  0.78, all lost at 18-19 min with the commander dead. Fewer constructors pay only if each claims extractors: the
  constructors' job choice has to change with it (#105).
- **Spare-constructor count + constructor redirect to extractors together, reverted (cj0-3):** 53-59 redirects a game,
  army 270-540 at 4:00, but extractors 3-13 and 14-17 lost, income up to ~26; trades 0.46 / 0.85 / 0.54, all lost with
  the commander dead. Even together, redirected constructors take the nearest open spot on our side whether it can be
  held; the winners' constructors claim far spots under the cover of a Tick swarm and forward towers/radar. Holding the
  spots (what makes a far extractor worth claiming) is the missing part of #105.
- **Army measured against winners (#106):** replay analyzer now logs squads and the alive army; 6 Armada-beat-Cortex
  replays vs ours: winners 14-22 combat units at 6:00 (ours 5), singles spread early then one main squad that mostly
  stands in its own half; main squad Rover/Pawn early, Flash/Pawn 6-10 min, Mace/Stumpy from 10. Details on #106.
- **Hold state (hd1-4, #106):** free units stand at the median point of our extractors and the base (least summed
  distance), not the base centre. Trades 0.67 / 0.83 / 0.97, commander alive in 2 of 3 (0 of the last 6), extractors lost
  12-19; all lost (18 min, pts, pts). Kept: the structure players use; the early army is still too small to hold much.
- **Hold + constructors on non-extractor jobs counted as spare (hc1-3):** trades 1.04 / 0.89 / 0.91 (best set average,
  ~0.95), combat units at 6:00 9 / 17 / 8 (was 5; winners 14-22), commander alive in 2 of 3. Lost on points twice
  (buildings 1467 / 1730 vs 30726 / 32476) and once at 13:00: extractors still fall (4-15 held, 12-19 lost) and our
  buildings are a tenth of BARb's. Kept. Next: what the buildings gap is made of.
- **In-fight defence by the square law's inversion (df1-3):** D = S x sqrt(lost / metal sent), independent of kills
  (lost/killed read 448-491 in the first seconds: 205 launches pulled back 1-2 s later in hc2). Pull-backs 21 / 15 / 33
  per game, largest defence pulled back from 50 / 91 / 26; **commander alive in all three** (first full set); trades
  0.76 / 0.77 / 0.92, df3 killed 119 units for 93. All lost on points: BARb's buildings 20-37k vs ours ~1k (#107).
- **Enemy buildings over the horizon (#107), reverted (ev1-6):** valued as ours (yield over the horizon, factories by
  their production) the army hit BARb's economy (their buildings 14-18k at the end, was 20-37k) but over-committed:
  trades 0.46 / 0.64 / 0.67; with our losses also valued over the horizon (metal + share of income/army) 0.46 / 0.62 /
  0.46, economy collapsing in ev4. The principle holds; our fight estimate can't carry a higher stake yet - more value
  means more fights we can't win. Kept: extractors valued at the metal of their own spot, not the map average (owner:
  "different metal spots have different values"), in the enemy value, raid loss and threatened-producer value.
- **Per-fight range gap and splash vs measured squad spacing, reverted (fs1-3, #108):** both sides' power computed
  against the units actually at the fight (SurfPower with the squad's median nearest-neighbour spacing). The army got
  far more cautious (206-591 skipped fights a game, 31-82 pull-backs) and traded worse: 0.57 / 0.50 / 0.64 against
  0.76-0.92 committed. The model's numbers are not calibrated to what fights actually cost: the next step is to check
  the per-fight estimate against measured fight outcomes ([ANV-FIGHT] lost vs killed per op) before it decides.
