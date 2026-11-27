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
- **Owner's game fixes on Comet Catcher (cc1-2):** no lab/builder energy waits, energy planned for lulls, one energy price
  for plants, radar warning value, T2 lab job carries the gate's return, spare-constructor rule reverted. cc2: no energy
  stall, 18 advanced solars, 4 radars, T2 lab 13:03, extractors 24 and 66 M/s at 12:00 (the owner's game: 8-10 and 20).
  cc1: raided from the start, extractors 2-5, energy stalls at 4 and 16 min. Both lost on points (buildings 0.5-11k vs
  34-40k); trades 0.63 / 0.61. Next: Defend (answer raids, #106) and towers at our far extractors (BARb's 13.5k defence).
- **Detachments and caretakers (df4-5, Comet Catcher, Armada vs Cortex):** threats are weighed with no free units (the
  whole army out on a raid never looked at Grunts at our extractors) and answered by the nearest units detached from
  lower-value ops; caretakers offered whenever none is queued and valued by the builders (BARb's quota built 0 all game).
  df4: 13 detachments, 1 lab 0 caretakers, bank 1068-1399, army 367 vs 2894 at 12:00, lost at 15:25. df5: 97 detachments,
  10 caretakers, army 4195 vs 6055 at 20:00, kills 114/145, points loss; but 43 extractors lost, metal 52 -> 18 M/s from
  12 to 20 min (BARb 40 -> 105). Next: towers at raided extractors.
- **Constructor value bounded by the horizon (sw5-6):** yield x work/2 summed every free spot was quadratic in the spot
  count (22597 vs a Pawn's 183 at 2:00); now the claim schedule V(N+1)-V(N) within the horizon (500-640). Constructors
  still win (ratio 1.9-4.8 vs Pawn 1.4-3.0) because the fighter's value is the marginal WinShare of one global battle:
  behind (12 vs 236), one Pawn adds ~0.009 of the stake. Raids are local fights against single raiders; the fighter is
  worth the raid losses it stops - next. Swing at 4:00 both runs: metal 6.6-8.9 vs 18.1, damage share 0.13-0.22.
- **Fighter value per enemy group (sw7):** each seen enemy group (single linkage within weapon range) is a fight with
  stake dps x H x our producers' metal/hp; the larger of that and the global fight stands. sw7: BARb's seen units were
  one group, so no change (groups 73-93 vs per-type 113-144). Swing moved to 3:00 on buildings (820 vs 1430) with metal
  income equal (11.2): we bank 808 vs 580 at 1:00 and 507 vs 142 at 3:00 - BARb's commander spends ~600 in the first
  minute (2 extractors + 3 solars), ours ~370 (2 + 2).
- **Losses fed back (fb1, owner: "ignores losses? is there no feedback loop?"):** a claimed extractor yields until the
  horizon or its measured life (no floor); the producer metal lost per second, over the horizon, joins the stake an
  army defends. fb1: metal 15.8 = BARb at 4:00, 68.6 vs 43.3 at 12:00 (best yet); but bank 2643 vs 1 and army 1966 vs
  5330 at 12:00; army 11844 vs 7685 at 20:00 with kills 22/141 - it doesn't engage. Points loss.
- **One defence for launch and continuation (fb2):** the running op read Cover(squad, whole walk) - 16.5 where launch read
  7.5 for the same spot: launch/pull-back every update, 24-30 units idle. Now the launch terms. Pull-backs 37 -> 11, the
  army raids (28 units at 8:00) - but constructors walked 3400-4570 out and died (399 extractor picks, 5 built).
- **Producer job value capped by measured life (fb3):** the core's extractor/plant value runs to the horizon or the
  measured producer life x the spot's keep against our producers' mean keep (SetProducerLife). fb3: 40 extractors, 3
  constructor deaths, metal 57.1 vs 38.9 at 12:00 and the bank spent; but army 1188 vs 5745 - lost at 14:00.
- **Reverted: unseen enemy army from its estimated economy (fb4).** Earned (estimated income integrated) - killed -
  buildings at our static per extractor read 60-113k strength against BARb's real 5-12k army metal: unscouted spots
  count as possibly theirs and integrate into an army that doesn't exist; fighters looked useless against it, the
  bank sat at 1030-1403. The unseen army needs sight (scouting), not a prior.
- **Scouting was zeroed by a dictionary read (sc1-3):** a missing key leaves the out value undefined - CellSurvival read
  sent = died = the cell's z (2800, 560), survival 0, so no scout ever had value (0 scouts all game, fb3; we saw 50-56% of
  BARb's army). Every unguarded `get` (20, incl. Production's per-type unit counts, caretaker use, unit facts) now checks
  the return. sc3: cellSurv 1.00, 4 scouts out by 3:00. Rule added to CLAUDE.md: end a game at the swing (tools/swing.py).
- **Sight after the scout fix (sc4):** enemy army known 3836 vs real 4226 at 12:00 (fb3: 3195 vs 5745). Lost at 19:00.
  The gap stays the opening: metal 8.9 vs 18.1 at 4:00 - our 7 extractors by 3:12 die to the first Gators (1:43 on),
  BARb towers its own from 2:06. swing.py now counts energy as a gap only when our bank is empty and theirs isn't.
- **it1 -> it2:** a boost (assisting the lab) ended only when energy bound; the first constructor boosted 37 s instead of claiming. Now it ends on any better non-boost pick: first constructor's extractor at 107 s (was 157), the 2:00 swing gone; next swing 3:00 army 162 vs 386.
- **Fighter valued against the enemy at its ready time (it3):** measured growth of the strongest enemy surface strength seen x (build + walk). it3 stopped at 2:00 on buildings 565 vs 640 (one solar; the opening varies by seconds run to run) before any growth was measured (grow 1.00) - not yet judged.
- **fg1 (full game, all of today):** ready-time growth 1.02-1.07 (small). The lab swung to the army: 91 Pawns, 6
  constructors; army 2104 vs 2938 at 12:00 (fb3: 1188 vs 5745) but metal 6.6 vs 15.8 at 4:00 and 20.4 vs 55.5 at 12:00,
  banks 1000-1500 unspent from 12:00. Points loss. Between fb3 and fg1 the same lab choice (constructor vs fighter) swings
  the whole game from economy to army: the two values come from different models (claim schedule vs win share) and
  their balance, not either one, is what decides. Next: one model for both - each unit's value as the metal it adds or
  saves over the horizon in the same simulation (claims that survive the measured raids vs raid losses it prevents).
- **[ANV-CONVAL] logs the constructor value's inputs (cv1):** 0 before the lab (no constructor to build), then 626 -> 371 -> 86-167 as constructors are added and the horizon shortens with measured losses (H 272 -> 146, Lm 1081 -> 426). The fb3/fg1 split (454 vs 0.02 at 1:00) is the timing of the lab's first pick, not the formula: run-to-run variance, judged by mechanism.
- **Replay view, first 4 minutes (replays.db: 24 Armada bot-lab 1v1 wins vs fg1):** winners by 4:00 - 0 towers (0-1),
  9 extractors (6-10), 5 constructors (3-6), army 609 metal / 12 units (365-826). fg1: 1 tower, 4 extractors, 4
  constructors, army 150. Winners don't tower early; they build MORE of both economy and army - we are not choosing badly
  between them, we spend too slowly (the 2:00-3:00 swings: commander, lab, constructors idle or late, bank standing).
  Next: spending throughput from the first minute, not towers.
- **Energy planned for the bank we can spend (en1-3):** winners make 174 E/s at 2:00 vs our 70 with the same metal, and
  spend their bank (214 vs our 562). Our plan spread the bank over the planning horizon (10711 s early: 0.05 M/s). Now
  the bank adds bank / job window, at most the idle build power's pull (en2 asked full capacity for any bank: 673 E/s at
  8:00, army 378 vs 2485). en3: energy 387 vs 408 at 8:00, bank 127/33/22/11 at 4/6/8/12 min (was 500+), metal 31.8 vs
  27.2 at 8:00. Army still behind (679 vs 2176 at 8:00, 3266 vs 5570 at 12:00); energy high mid-game (886 vs 688, 2942
  banked at 12:00). Points loss.
- **Energy need counts the bank (en4, mechanism not confirmed):** a gap needs a plant only if it would empty the bank
  before one comes online. en4 still reached 1020 E/s with 3230 banked at 12:00 - plants also come from the builders'
  own picks (payback at the energy price), not only the need trigger; to trace next. Lost at 14:00 (army 1824 vs 6615).
- **Bank energy bounded by the plant (en5):** a plant for the bank's extra spending pays only while the bank lasts, so
  the extra energy is at most bank x the best plant's make per metal. en5: energy with BARb to 8:00 (427 vs 486), army
  1479 vs 1890 at 8:00 (closest yet); but the plan still climbed 330 -> 800-900 E/s and energy reached 1342 with 3860
  banked at 12:00, army 603 - lost at 14:00. Suspected loop: the plan's E/M ratio is measured from what we pull, and
  building energy-costly plants (advanced solars) raises it - more plants raise the plan that orders plants. Next: the
  ratio from what spending the metal produces (factory and builder output), not from the pull that includes the plants.
- **Plant construction out of the energy ratio (en6):** no overshoot (485 E/s vs BARb's 818 at 12:00; plan 177-719).
  The game went another way: metal 4.3-11.2 M/s from 6:00 (extractors lost to raids), lost at 16:00 - one game, the
  energy mechanism judged on its own. Games swing between economy and army losses run to run.
- **en6 raids, traced:** Incisors killed 5 solars, 2 extractors and a constructor 200-400 from base at 3:00-5:20. Responses
  went in piecemeal: e.g. 2 units at strength 8.4 vs defence 10.8 (expected loss 8846) while the rest stayed on other ops.
  The detachment refused more units because each costs its op a share of the op's value, and op values for a single
  raider read 15000-16000 (EnemyValue + OursThreatened): detaching never paid, so a losing 2-unit fight went ahead instead
  of a winning one with the army. Next: what a raider target is worth (the damage it can do before it is stopped, not the
  sum of everything it threatens), so the detachment's arithmetic can concentrate the army at home.
- **A raider's threat to the commander by its kill chance (rv1):** was the whole game's value for any raider in reach of
  the commander (15000-16000 per home op, no op gave units to another). Now GameValue x CommPDeath x this enemy's share of
  the threat near it. rv1: 44 detachments; ahead at 8:00 for the first time on both - army 918 vs 540, metal 39.2 vs 31.8,
  bank 114. Then 43 extractors/solars lost before 7:00 and metal 20.4 vs 56.4 at 12:00; points loss.
- **rv1 losses, traced:** nearly all to single Grunts at outer extractors 640-1920 from base, 5:00-12:00. A Grunt kills an
  extractor in seconds; our units need 30-50 s to walk there: an answer sent after the raid starts is too late for far
  extractors however well it is chosen. Winners (replays.db): singles spread early across their half, then one main squad;
  ~2 extractors lost by 12:00 vs our 12-19. Next: pickets - a unit stationed by each outer extractor group, worth the
  raid losses it prevents there (measured loss rate at that group x how much sooner it arrives than the main army)
  against what it adds to the main squad's fights.
- **Pickets (pk1):** a unit stationed by an extractor where losses were measured and the army can't arrive before one
  dies; worth losses there per second x H x its win share against the raiders seen there, against its metal at the lab's
  value per metal of army. pk1: 229 assignments (e.g. Pawn -> (624,4160): 1620 lost in 391 s, win 0.77, 487 > 27); 28
  extractors lost; army ahead at 12:00 (1857 vs 1231), kills 116/208. But metal stalls at ~20 M/s from 8:00 while BARb's
  grows (50.4 at 12:00): expansion after 8:00 is the gap now. Points loss.
- **pk1 expansion after 8:00, traced (not yet fixed):** 8-12 constructors, 64-74 unclaimed spots, but 6-8 extractors: 8
  built vs 22 lost after 8:00. 6 constructor deaths only. 328 job switches ([ANV-SWITCH]) - e.g. "1->4 left 1672": a
  caretaker job dropped for energy with 1672 build-s left, the "any job yields to energy when energy binds" rule - jobs
  left half-built. Lead to confirm next: how often that rule fires now that the energy plan moves more.
- **Reclaim no longer steals extractor jobs at their price (rc1):** the job left is worth its yield over the horizon
  (AssetValue), not its cost x a build-power share. [ANV-SWITCH] in pk1: mostly to RECLAIM (type 16) - 49 extractor and
  24 energy jobs dropped; "to energy" was only 21. rc1: extractors 14 at 12:00 and 24 at 20:00 (pk1: 6-8), metal 109 vs
  133 at 20:00 (closest yet), army 7687 vs 9980; but a weak opening (2-7 extractors, army ~170 at 4-8 min) and still 31
  extractor jobs dropped for reclaim. Points loss.
- **Commander may assist (ca1):** BARb's CBRepairTask::CanAssignTo refused every commander; winners' commanders spend 27%
  of their time assisting, and winners field 5 constructors + 12 fighters by 4:00 - more than one unassisted lab can make.
  ca1: 153 commander assist picks; army ahead at 12:00 (3107 vs 2880), kills 100/150. But 6 constructors and 2
  extractors at 4:00, and 2-3 extractors after 12:00 (metal 6.6 vs 155 at 20:00). Next: what the constructors did instead
  of extractors in ca1 (assisting builds too?).
- **Pickets from seen raiders (pk2):** before any measured loss, each seen raider's reachable sites (it gets there and kills before our army arrives) carry 1/n of it. pk2: 2 extractors lost before 6:00 (rv1/ca1: 3-5), army 2417 vs 3024 at 12:00; but extractors stayed at 4-6 (metal 15.8 vs 45.6 at 12:00). Points loss.
- **One op per raid spot (rs1):** raid spots carry no id, so the same corner was picked each update ([ANV-AWARE] aw1: ops [1@6800,752 1@6800,752 2@6800,752]). Now an op's spot is taken. rs1: distinct targets; but army 108 at 3:00 and 2 extractors at 4:00 - the opening again; lost at 18:00.
- **Opening replay view (24 Armada bot-lab 1v1 wins vs rs1):** winners place the lab at 58 s (46-65); its first 3 minutes
  make 4 constructors and 12 combat units, mostly Ticks (armflea), e.g. "ck ck flea flea flea pw flea flea flea pw".
  rs1: lab at 128 s; 8 of its first 12 units constructors, 4 combat units. The opening plan to build as one decision:
  lab by ~1:00 (what delays ours past 2:00), then the Tick's value - it is a raider and scout at 1/4 of a Pawn's cost,
  valued by us as a scout only - and constructors only while a spot can be claimed before the raids we see.
- **Plants off the lab's site (lb1-2):** PlaceNextTo put solars on the planned lab footprint (nearest-home direction): 17 failed lab starts 53-110 s, lab at 128 s in rs1. Now plants keep clear of the lab sites: lab at 75-78 s, 0-2 failed starts (winners 58 s).
- **Reverted: raider value (tk1).** Raid targets per visit over the scouts' life - Scout::Life() is the horizon until a
  scout dies, so a Tick read 17-980 visits (value up to 4571): the lab built only Ticks, no constructors, metal 6.6 vs
  48.6 at 12:00. The raider's value needs its measured life (raiders lost per raider-second), not a floor; without a
  measurement it has no basis yet.
- **Reverted again: raider value with measured raider life (tk2).** Life measured right (13-28 s early), but one visit
  counted a whole raid target's value (~600, assumed killed) while raids killed almost nothing (4 kills by 12:00): 143
  Ticks, 7 Pawns, 6 constructors, lost at 14:00. The value must be what raids actually kill: enemy metal killed during raid
  ops per raider-second, times the raider's measured life - 0 until a raid has killed something.
- **Raider worth from measured raid kills (tk3):** enemy metal killed within a raider's reach on raid ops, per raider-second, x the raiders' measured life, at the unit's dps against theirs; 0 until a raid has killed. tk3: no runaway (19 Ticks, 124 Pawns, 7 constructors; raid values 19-110); even at 4:00 (army 354 vs 344), metal 40.5 vs 43.3 at 12:00; then collapse 12-16 min (metal 2.0, army 617 vs 6228). Points loss.
- **Enemy memory in production (mm1):** types seen and out of sight still count, fading over the horizon. mm1: a mixed
  lab (72 Pawns, 63 Maces, 21 Ticks); but kills 12 vs 151 all game - ops "target gone" after losing 3800-7000 metal for 0
  killed. Owner: "maybe your fighting principles are kinda bad", "you had 1 unit type bulked in one ball".
- **Attack-move for routes and pickets (ft1):** on a plain move squads walked past what shot them. ft1: still 13 kills vs
  75; 71 ops, 7 killed anything (925 metal). The fighting itself needs redesigning from the replays (winners: one main
  squad holding their half, mostly idle; singles spread early; fights taken with an edge), not another term.
- **Formation from replays (#116):** new `[REPLAY] FORM` analyzer line; 4 winners' replays played back. In contact,
  short-range types lead (Pawn, Blitz, Pyro at the front) and longer-range ones stand back by about their range edge
  (Mace +161, Can +181, Samson +457). Single-type squads are normal. Table in REPLAYS.md. Next: each of our units fights
  from its own reach in contact.
- **Fight from own reach (kt1, #116):** `Facts::FiresMoving` exposed (every common land fighter of both sides has turret
  weapons); Micro steps a unit that outranges the nearest enemy back to its own reach. kt1: 11 kite orders (Pawns rarely
  outrange what they meet), but ops with kills 38/72 and 5335 metal killed (ft1: 7/71, 925), kills 52 vs 223; ahead at
  4:00 (metal 27.3 vs 15.8); army behind from 8:00 (1317 vs 4230 at 12:00). Points loss.
- **FIRST WIN vs BARb hard (pk3, pts_win at 20:00, Comet Catcher, Armada vs Cortex):** producer losses recorded at
  their full cost (metal + yield until rebuilt, MexPorc::RaidLoss) instead of their price, so pickets are worth what
  they save: 351 picket assignments, 4 of 27 extractors lost 4-12 min (kt1: 15 of 22). Metal 59.4 vs 36.1 at 12:00,
  116 vs 50 at 16:00, 199 vs 94 at 20:00; buildings 81015 vs 25579. Armies close at 20:00 (5476 vs 6135) and kills
  40 vs 261 - the fighting gap (#116) stays. A points win, not a kill. Next: repeat it, other maps.
- **Repeats of pk3's build (rp1-3):** rp1 Comet loss at 13:00, rp2 Comet points loss, rp3 Canis loss at 17:00. 1 win in
  4 games on this build: pk3 was not yet a repeatable result.
- **rp2 deaths traced (#116):** BARb has more army AND more buildings with about our income: we lose 3-5x the units.
  Pawns die to Incisors (39: fast raiders they chase) and Pounders (26: splash on clumped Pawns - our splash term read
  1.00 for Pawns); 40 deaths at 2500-3000 from base in ops of up to 46 units pushing into their side. Next: splash
  counted per enemy type against our spacing, no chasing what outruns us, and pushes valued with the defence they meet.
- **Pickets hold their posts (pc1-2):** on attack-move they chased Incisors away (39 Pawn deaths to Incisors in rp2); plain move to the post: 15-18. Both games lost (18:00, 15:00). Record on the pk3-line builds: 1 win in 6.
- **Op depth logged (dp1, `forward` in [ANV-FIGHT]):** all 32 ops were in our own third - 3938 metal lost, 0 killed;
  lost at 15:00. Not deep pushes: fights at home. Micro totals: 292 contact-seconds, fired 185, outranged 103 (hit with
  nothing in our reach), no reply 89. Pawns (range 180) are outranged by Incisors and Pounders. Next: the army's range
  against what they field - the lab's per-type value with the range gap.
- **dp1 production traced:** the lab isn't idle - metal bank 0-20 from 6:00. Metal is low (8.9 at 6:00, 22.7 at 10:00 vs
  BARb 22.7 / 41.7) and goes to energy: 21-28 E per M with 1700-2600 energy banked, against the winners' 12-15 E per M
  (replays.db medians). Extractors 3-4 at 4-6 min (winners 9). Next: the builders' plant picks while energy is banked -
  the planner's need test counts the bank now (en4), the builders' payback pick does not.
- **Energy need vs the next plant (en7):** the bank against one plant's online time, not the whole gap's (quadratic). en7: energy still 405 E/s with 2167 banked at 8:00 (~20 E per M): the builders' own plant picks (payback at the energy price) are the remaining source. Army 594 vs 2036 at 8:00; points loss.
- **Builders' energy price counts the bank (en8):** plant picks with 1500+ energy banked 149 -> 47 of 124-277. Energy still 367-560 E/s with 2000+ banked; army 279 vs 2089 at 8:00; lost at 12:00. Army production by 8:00 stays at 300-600 metal in every recent game against BARb's 1300-2100.
- **First-8-minute spend split vs winners (REPLAYS.md):** winners ~9070 metal by 8:00, army 3242 (36%), energy 1858, extractors 950 (~19); ours 5000-6600, army 700-1100 (12-18%), energy 2000-2560, extractors 600-650 (~12). Both levers: more extractors early, less energy.
- **Energy plan's inputs logged ([ANV-EPLAN], ep1):** planned 128-474 E/s in the first 8 min - near the winners' actual 173/239/334/513 at 2/4/6/8 min; ratio 11-19 E/M (winners ~12-15). Our energy looks high per metal because our METAL is low (income swinging 5-23 M/s as extractors die). Root gap: extractors (~12 by 8:00 vs ~19), not energy.
- **Builder roles (REPLAYS.md):** winners' commanders build 16.5 of 31 energy buildings and 4 of 19 extractors by 8:00; constructors claim the spots. Ours reversed. Opening plan design point: assign jobs across builders by comparative advantage (or charge the commander's walk with its risk and the base work it leaves), not each builder's own best pick.
- **Commander by comparative advantage (cr1):** a commander job scored by the time it saves over the best other builder. cr1: 16 extractors by 8:00 (was ~12), metal 36.4 = BARb at 8:00; commander still mostly extractor picks (234, much of it before constructors exist); army 756 vs 1940 at 8:00, lost at 13:00.
- **Lab keeps its priority (lp1, WIN on points):** BARb's RecruitTask dropped the lab to low priority whenever metal was short - with the bank spent, always; builders took the metal. lp1: army 3780 vs 4720 at 12:00 (cr1: 1242 vs 5872), metal 167 vs 137 at 20:00, buildings 62235 vs 32919; kills 41 vs 247. Second win.
- **Repeats of lp1's build (lr1-3):** lr1 Comet points loss, lr2 Comet loss at 15:00, lr3 Canis loss at 17:00. Record on the latest builds: 2 wins (pk3, lp1) in 13. Army at 8:00 now closer in some games (lr1 1359 vs 1543) but swings run to run (lr2 324 vs 2020); kills still 22-81 vs 138-180.
- **lr2 traced:** metal 42.7 vs 28.4 at 8:00 but army 324 vs 2020: the lab made 24 units in 8 min and no caretaker existed (nano=0). Build power is valued only on spendable metal (unspent income + bank), ~0 now that constructors draw everything. Next: value lab build power by what the metal does as army vs in the builders' jobs (value per metal of each), not by leftover metal.
- **Lab build power by army vs builder value per metal (bp1-2):** caretakers 1-2 by 8:00 (lr2: 0). bp1 loss at 14:00 (army 810 vs 3100 at 8:00), bp2 loss at 18:00 (540 vs 995). Record on the latest builds: 2 wins in 15.
- **Reverted: realized-value feedback on fights (rz1-2).** Gain on value x (killed/value of ended ops): ops 30 and 14 (was ~70), losses per game down, but the army stood by - rz1 lost at 13:00 to an army of 2416, rz2 points loss. A passive army concedes the map. (Finding kept: 304 ops in 8 games, the 54 that lost >500 each were predicted to lose ~1000 and launched because the summed target value was larger; trade 0.45.)
- **Square law's losing case corrected (fg2-3):** the weaker side kills (S/D)^2 of the defenders' metal, not of the target's value. Losing fights are no longer launched; fg2-3 still lost (18:00, 19:00), trades 8304 lost / 2948 killed and 10659 / 2771 - so the losses come from fights predicted as WINS: the defence at launch is underestimated (unseen units, reinforcements arriving). Next: the defence an op meets, measured from how fights went (defence revealed vs predicted).
- **Reverted: measured defence ratio at launch (dr1-2).** Launch defence x (defence ops met / predicted): trades 0.30 and 0.60, losses at 15:00 and 13:00 - no change. Record on the latest builds: 2 wins in 21.
- **Fight replay view (dr2):** ours Pawns only (range 180), 316 from the nearest enemy; BARb a mixed squad (Brutes, Mists 700, Pounders, Incisors, Wolverines 710) holding 1050-1400 away - outranging us 4x. Next: the lab's answer to a ranged mix (units that reach them: range, speed to close, or artillery of our own), judged per enemy type as seen.
- **Why the lab stays on Pawns vs the ranged mix (dr2):** Rocketeer (475, unguided slow missiles: hit 0.17 vs moving targets, correctly) and Mace (380) don't reach Mists/Wolverines (700-710); no bot-lab unit outranges them. Winners' squads (README army tables): Pawn early, Flash/Pawn 6-10 min, Mace/Stumpy from 10 - vehicle-plant units that close fast or soak the range gap. Next: which lab to run against the enemy mix as seen (the vehicle plant's answer vs the bot lab's), a production decision above unit choice.
- **Second factory among new kinds (vp1-6):** a duplicate lab brings no new units (caretakers give build power cheaper);
  the core's held factory choice is re-decided while unbuilt; BestLabVsEnemy no longer falls back to the opener's bot
  lab when nothing is in sight. Now it ranks the vehicle plant first (vp6: armvp 0.06 vs armhp 0.04 - on its scout,
  with no enemy mix in view), but no vehicle plant was built: vp5 no second factory, vp6 an advanced bot lab and another
  bot lab at 708 s from another path. All lost (12:00-19:00). Record on the latest builds: 2 wins in 27. Open: which
  path still orders bot labs; scoring factories against the remembered enemy mix (Production's memory), not the mix in
  sight.
- **Vehicle plant built (vp7):** the factory re-decision no longer aborts a job a builder is on (it flipped vp/advanced lab). vp7: vehicle plant at 402 s (winners' second factory median 7:29), but it made 27 Rovers (scouts) and 20 Blitzes; vp8 none. Both lost (17:00, 19:00). Record: 2 wins in 29. Next: why Production values the Rover so high from the vehicle plant.
- **[ANV-TRADE] per-type live trade (tr1):** Pawn dealt 8670 / got 13426 (0.65), Tick 3722 / 13083 (0.28) over 18 min; only Pawns and Ticks built, no vehicle plant this game; lost at 18:00. Record: 2 wins in 30. Every unit type we field trades below 1 against BARb's mix.
- **What kills Cortex units in Armada wins (REPLAYS.md):** Stumpy/Bulldog vs Pounders and Brutes, Blitz and light lasers vs Incisors - vehicles and towers, not Pawns. Our Pawn/Tick army trades 0.65/0.28. Next: the vehicle plant every game and the Stumpy's value (armour soaking the range gap) from unit facts.
- **Why the vehicle plant isn't built reliably (tr1, vp8):** its job is valued only as build power (leftover metal it spends), which swings +1061 -> -489 with the bank: tr1 builders took it 41 times and dropped it; vp8 never. A new kind of factory is worth its units (what its best units add over the best we can build now, per metal, x the metal it will turn into units). Next: pass BestLabVsEnemy's per-lab value to the core's factory value.
- **Factory edge (fe1-2):** a factory of a kind we don't own gets value from its units (LabVsEnemy edge x metal it processes). Still no vehicle plant: AiGetFactoryToBuild returns the advanced bot lab first whenever the tech gate allows it - a fixed order, tier 2 before any new T1 kind. Pawn trades 1.01-1.37 in these games; both lost (16:00, 13:00). Record: 2 wins in 32. Next: tier 2 vs a new T1 kind decided on the same edge (what each lab's units add), not by order.
- **Tier 2 vs new T1 kind by return per metal (fe3-4):** the new kind's edge reads 0 - LabVsEnemy scores a lab by its single best unit's strength per metal, where Blitz ~ Pawn. fe4 (vehicle plant by another route at 517 s) trades: Centurion 1.22, Blitz 0.58, Pawn 0.31, Rover 0.19, Tick 0.13 - our heavy T1 unit is the only one above 1, and the lab rarely builds it. Both points losses. Record: 2 wins in 34. Next: the lab's unit values against our own measured per-type trades (the [ANV-TRADE] data the live term already reads).
- **Scout worth measured (sv1-2):** enemy metal first seen within a scout's sight per scout-second x scout life (the model before scouts serve). Ticks 27 -> 1-2 per game. The lab then made almost only Pawns (71, 64; trade 0.50-0.56) and no Centurion: a unit's live-trade correction needs it to have fought, and before that the model rates the Pawn higher per metal. Both lost (16:00, 14:00). Record: 2 wins in 36.
- **Canis River, current build (cn1-2):** two points losses; army at 8:00 596 / 1080 vs BARb 2665 / 2408, at 12:00 2492 / 2096 vs 5827 / 5010; cn1 ended with armies level (3805 vs 3920) but buildings 8540 vs 30363. Same picture as Comet Catcher. Record on the latest builds: 2 wins in 38.
- **Reverted: squad spacing by the enemy's blast radius (sp1-2).** Pawn trade 0.50 / 0.54 (before 0.50-0.56); lost at 14:00 and 19:00 - splash is not what loses the fights. Record: 2 wins in 40.
- **#116 design (1), unreachable enemies give no power (rc2-3):** against an enemy that outranges us and is at least as fast, a unit's power is 0 (it never closes); power scales by the reachable share of the mix. rc2: 6 Centurions dealt 17806 / got 15144 (1.18) vs 62 Pawns 7851 / 27694 (0.28); rc3 kills 47 vs 46 (first even count). Both lost (18:00, 15:00). Record: 2 wins in 42. The first army change that moved trades.
- **#116 design (2), factory follows composition (fc1-2):** with (1) in SurfPower the vehicle plant is now built every game (677 s, 373 s); it makes Blitzes (trade 0.42 / 0.69) and Rovers, no Stumpies; no Centurions this time. fc1 points loss, fc2 loss at 14:00. Record: 2 wins in 44. Next: why the Stumpy (1800 hp, range 350 > Pounder's 315) loses to the Blitz in the vehicle plant's pick.
- **Stumpy vs Blitz in the vehicle plant (fc1):** Stumpy 0.21/metal (per-type 59, hit 0.28 - slow shells vs the fast part of the mix) vs Blitz 0.25 (per-type 24, already x0.46 by its live trade). Close; the Stumpy's cost (225 vs 110) and mix-wide hit chance decide it. Next (design 1 continued): a unit's value against the types it's for - its hit chance per enemy type, not averaged over the mix - so a Stumpy is judged on the Pounders and Brutes it hits, the Blitz on the Incisors.
- **Current build repeated (cb1-2):** back to Pawns only (92, 71; trades 0.69 / 0.40), no Centurion, no vehicle plant; cb1 loss 14:00, cb2 points loss. rc2's Centurions and fc1-2's vehicle plant were game-dependent: (1) zeroes power only against enemies both longer-ranged and as fast - BARb's artillery is slow, so Pawns still read as able to close on it. Record: 2 wins in 46.
- **Closing damage (not changed):** gapDmg is a weighted average over the mix, and the global mix weights each enemy by its strength (sqrt(dps x hp)), not by count - so a sum over enemies needs the mix rebuilt with unit counts beside the strength weights. Design note for #116: the fire a squad takes while closing = sum over enemies in range of dps x gap / our speed, shared over our units.
- **Closing damage summed over enemy units (gd1-2):** Mix carries the units each entry stands for; gapDmg = sum of count x dps x gap / our speed over our army count (hypothetical mixes keep the average). gd1-2: lab still mostly Pawns (32, 43), one Centurion (2.51); lost at 12:00 and 16:00. Kept (correct arithmetic); not enough to change the pick. Record: 2 wins in 48.
- **Live efficiency per metal (ef1-2):** a type's correction is its damage dealt per metal fielded over the mean of our fought types (the sqrt-of-trade correction missed rc2's Centurions at 4.5x the Pawns per metal). ef1-2: lab still Pawns (only type that fought: efficiency 1 against itself); Pawn trades 0.85 / 0.80 (recent 0.28-0.70), kills 89/129 and 50/111; ef1 points loss, ef2 loss at 17:00. Record: 2 wins in 50. Still open: trying a type that hasn't fought.
- **Reverted: one fought type corrected against the model (ex1-2).** The next type up was the cheapest (ex2: 56 Ticks, lost 13:00), not the heaviest; ex1 Pawns again, points loss. Record: 2 wins in 52. What a 'try an untried type' decision needs: the untried type's value with the model's measured error for units like it (by size/cost), not just the tried type marked down.
- **Reverted: candidates compared at equal metal (gm1-2).** nb copies for the costliest fighter's metal, granularity included: still Pawns (30, 39) - Gran flattens toward 0.71 for an army of any size, so extra bodies cost little. gm1 kills 61/62, lost 16:00; gm2 points loss. Record: 2 wins in 54.
- **Formation (#117, fm1-2):** Facts::DirectFire exposed (Rocketeer, Centurion direct; Mace/Pawn/Blitz/Stumpy arc). In contact each unit stands at its own range from the nearest enemy (short range front, long range behind); direct-fire units of a squad spread sideways on the line. fm1-2: 164 / 226 placements; army still nearly all Pawns (little to arrange), Pawn trades 0.70-0.71, one Centurion 1.31; lost 13:00 / 16:00. Record: 2 wins in 56. Kept: it acts only in contact and is what mixed squads need.
- **swe1 -> swe2 (swing method, spectated):** swe1 swung 3:00 on metal (6.6 flat 2-4 min): constructors assisted the next constructor 35 times (valued as build power). Assist on a constructor now worth one extractor's yield sooner: swe2 constructors 59 extractor picks, 0 assists; swing moved to 4:00 (metal 8.9 vs 13.5, army 291 vs 258 ahead).
- **swe3 (scout warning value):** the Tick rose 0.64 -> 1.6-1.95 per metal but still lost to Pawn (2.69) and constructor (2.82); first scout ~200 s again. Swing at 4:00 on army (183 vs 430; winners 609): before any enemy is seen the lab takes their army = ours and never prepares for the raid. Next: fighters valued against the raid due by the opener's computed arrival time (#41/#103 'army by the first raid').
- **Reverted: fighters valued against the modelled raid (swe4).** Raising the expected enemy lowered each fighter's share gain (the win-share trap: far behind, one unit adds little): Pawn 0.71 vs constructor 2.08, army 54 vs 215 at 3:00 - a minute earlier swing. The first raid's real stake is the producers it can kill before an answer, not a share of a big fight: value fighters by the raid loss they prevent (as pickets are), not by win share against a larger army.
- **First-raid fighter value, swe5-8 (swing method, spectated, one game each, a fix between):**
  - swe5: raid loss a fighter prevents (opener's raid model) - duel 0.01-0.02 (SurfPower vs sqrt(dps x hp) scales); army 108 vs 215 at 3:00.
  - swe6: duel on one scale - firstRaid 85492 (whole stake), all Ticks, army 504 vs 215 but metal 8.9 vs 11.2 at 3:00.
  - swe7: raider rate capped by income - ahead on metal (11.2 vs 8.9) and army (442 vs 258), totals level (1107 vs 1108); swung on buildings (no constructor in 12 units: the value used the whole horizon, ~10700 s early).
  - swe8: value over one lab slot - too small (192): constructors first, army 0 vs 146 at 2:00.
  - The window is between one slot and the horizon: how long the raid goes unanswered if not now, which depends on the lab's next picks. Next: the unanswered time from the lab's own queue of values.
- **swe9, unanswered-time window:** fighter value over the time the raid will have gone unanswered (>= one slot). Lab: Pawn, constructor, Pawn, constructor, Pawn, Pawn, then Ticks; at 4:00 army level (309 vs 301), buildings ahead (1455 vs 1280), total ahead (1764 vs 1581). Swing at 4:00 on metal (6.6 vs 18.1; damage share 0.19).
- **swe10-11:** square-law duel (Ticks no longer chosen as raid answers): swe10 army 540 vs 355 at 4:00 but 12 Pawns in a row, metal 6.6 vs 20.4 (the raid model's raider count kept growing). Raider count from sightings once seen: swe11 lab Ck Pw Pw Pw Ck Ck Ck Pw Pw; at 3:00 metal 11.2 vs 13.5, buildings 965 vs 1000, army 162 vs 258 with 471 metal banked (lab throughput). The early game is now near parity; the swings are within a unit or two.
- **swe12 (bank over a job window):** at 2:00 ahead on metal (8.9 vs 6.6) and army (162 vs 146), buildings 460 vs 640 (one solar); 532 of the start bank unspent (winners 214); no caretaker yet. Early game near parity on every stat; stops now at one-building gaps. Next: spending the start bank as fast as winners (commander + first constructors).
- **swe13-14 (raid targets):** unseen spots capped at our extractor count (swe13: ops still to 6800,752 / 6960,5888, swing 4:00 on metal 11.2 vs 18.1); raid-spot yield valued until the enemy could rebuild, as a seen extractor (swe14: stopped at 2:00 on buildings 495 vs 790 - one solar in the opening, before any raid; 543 of the start bank unspent vs winners' 214). The 2:00 opening gap recurs in about a third of runs (swe8, swe12, swe14).
- **swe15-20, the late lab:** the commander failed to start the lab 11-15 times (lab at 81-104 s vs ordered at ~51 s): out of build range behind our solars (swe15: stopped 206-239 from a site needing ~192), then overlapping the commander when placed beside it (swe16), then its own half-built frame on the site with the job unaware (swe18-19). Now: lab placed at the commander's build distance, and a builder continues its own unfinished building found on the site. swe20: lab at 85 s, 3 failed starts; stopped 2:00 on army+buildings (694 vs 786, buildings level 640). Pickets from the modelled first raid (swe18+) and raid-target caps (swe13-14) are in; the first fighters still reach their corners early in some runs.
- **Spectator, swe13-20:** no game kept a fighter home before the first raid - single Pawns left for the far corners
  each time (raid-spot value cut 250 -> 58-96 but still positive, and a free unit takes any positive target); the
  modelled-raid pickets never fired before contact (nR near 0 at 2:00); the first raid (1-2 Grunts or an Incisor,
  2:49-3:06) cost 1-2 extractors every game. Next design step: a free unit leaves for a raid only when the raid beats
  what that unit would save at home when the predicted raid arrives (picket value at the arrival time, not now) - one
  comparison across Pickets and Command, not two separate thresholds.
- **swe21-25 (Comet Catcher, one game each with spectator + swing stop):**
  - swe21: launches weighed against home ("stay home", 693 lines): no early corner raids; stopped 4:00 on income (6.6 vs 20.4), 3 extractors at 4:30.
  - Replay view, Comet Catcher Armada winners (replays.db ea25036b Hellontoast, 18a2046b Artur91): vehicle plant at 69-77 s, a constructor vehicle every 40-60 s with Rovers between, extractors 3/6/8/12 and 3/5/7/9 at 2/3/4/5 min. Our opener chose the lab by its fighter's strength per metal only: the bot lab.
  - Lab now chosen by its plan value (with the wait to cover its draw); horizon's map crossing at the earliest raider's speed before we have an army (army speed 0 made it 11590 s and the hover plant won, swe22-23, no lab at all); energy gap carried by the bank like metal ("90/s short of 90" held the lab); every building placed at the commander's build distance (wind failed 42-102 times).
  - swe24: vehicle plant at 64 s; stopped 4:00 on income (4.3 vs 18.1): 2 Blitzes stayed on a corner raid while 2 Grunts killed 3 extractors + 3 solars. Running raids are now recalled when meeting a threat saves more ([ANV-CMD] recall raid; fired in swe25: "gains 14, meeting the Incisor saves 52"). The minelayer bypass ahead of the plant's value comparison removed.
  - swe25: plant 67 s, constructor vehicle first at 100 s (winners 91-106), army ahead at 2:00 (141 vs 120); stopped 2:00 on buildings (565 vs 690): the commander built extractor, solar, extractor, plant; winners extractor x3, solar x2, plant. The pre-lab producer choice (Leontief share of the lab's draw) ranks energy before the lab draws any. Next: the opener as one design (CLAUDE.md), not another single term.
  - swing.py polls each second (the game runs ~15x real time; the 5 s poll let swe22 run to 7:18).
- **swe26-32 (Comet Catcher, one game each, spectator + swing stop):**
  - swing.py: buildings alone no longer stop a game (a split, not a loss, when total value is level: swe26 680 vs 686 with army 220 vs 86); damage/kill share need the same tenth margin as the rest (swe27 stopped at 5:00 on 0.40 vs 0.43 while ahead 691 vs 460 army, 1800 vs 1700 buildings - the best game of the series).
  - Opener: energy plants join the build-before-the-lab test (swe30: extractor, solar, extractor, solar, plant 74 s; buildings 410 vs 550 at 1:00 against 255 before). A plant's pre-lab output counted only as far as free storage holds it (didn't fire: the bank wasn't full).
  - Commander's comparative advantage counts constructors still in production (core).
  - Constructor value over producers' survival so far, exposure/(losses+1), floored by the threat horizon (swe31: constructors at 106/154/180 s vs winners 91/167/249; but then almost only constructors, army 141 vs 386 at 3:00). Early (72 s) the exposure is still below the threat horizon (~200 s) and the Rover won again (swe32: constructor at 125 s).
  - Threat of a raider = what it can destroy before our answer, nearest first (one Rascal read 5297-11500 and the army chased scouts, swe30-31).
  - **Where it stands:** the early-game valuations rest on two horizons that disagree - the threat horizon (V / their income + crossing, ~200 s early) for investments, and stake x win-chance for fighters. Single-term fixes move the plant between all-Rovers and all-constructors (swe30 vs swe31) and the opener between one and two solars. Winners on this map do one constructor, then Rovers, then the next constructor (~76 s apart), army 155-265 at 2:00 (replays.db ea25036b, 18a2046b). Next: one life model for every producer and constructor - the time until the enemy's raids (opener's raid model: arrival, rate, kill time vs our response) take it - replacing the threat horizon in both, designed as one (CLAUDE.md).
- **swe33-34:**
  - Commander risk out of sight computed from the unseen raiders the opener's model gives them (square law vs the commander, their damage over job + escape) instead of "the whole game" (risk 4166 at danger 0.0 blocked every base solar 48-184 s, energy flat at 50 E/s, swe32): CommRedirect 20 -> 0, solars back among its jobs (swe34).
  - SpotLife: an extractor's life from the raid model (first raid, round trips, share of sites one raid clears before our answer, kill time vs answer), floored by the threat horizon; the constructor value counts each spot over its own life (life 963-1854 s, swe34).
  - Opener sites by the commander's path time: worse (23 failed orders, first extractor 16 s), reverted.
  - **Open, blocking the opening every game:** build orders refused by the engine right after they are given ([ANV-REORDER] "cmds after 0", every game; [ANV-BUILDFAIL] every 2 s with the commander moving, out of range, canPlace=1). swe33: the vehicle plant at 118 s after 6+ refusals; swe34: one solar refused 13 times (45 -> 75 s). Checked and not the cause: BAR gadgets Prevent Strange Orders (only CMD.INSERT builds), Build Blocking API (blocked defs only), Builder Priority (rejects its own command, keeps the queue). Next: log the unit's command queue the frame after the order and the engine's own command rejection, and read Unit Orders Debug.
- **swe35, refused orders:** moving into range first doesn't help - the move is refused too (7 of 8, at 222, 106-108 inside build range, and 27-63 on the footprint; one order held at 80 with "cmds after 1"). Range is not the cause. Each refusal counts as a build failure: the order is re-issued, after two the builder leaves the job, after TASK_RETRIES the job is aborted and the site blocked (BuilderTask.cpp OnUnitIdle; BARb's own comment: "engine's ability randomly disregard orders"). Cost: the first solar 10 -> 31 s (winners 16 s), the plant's starts, the third extractor never. Open hypotheses: (1) orders reach the engine some frames later at 60x speed and an idle from the previous order is counted against the new one; (2) a gadget's AllowCommand refusing every command for the commander at times (not Prevent Strange Orders, Build Blocking API or Builder Priority; Unit Orders Debug, Share Unit Command unread). Next probe: log the queue on the next frames after an order (latency), and the engine's command events, before changing more decisions.
- **swe36-37, the refused orders were BARb's watchdog (#118, owner: "barb decision making residue"):** `CBuilderManager::Watchdog` (every 30 frames) called a builder lost when its queue read empty while our order was still on its way (60x headless), nudged it 256 away (`OnUnitMoveFailed`), the nudge replaced the build order and expired -> a failure every 1-2 s, retries, the builder off its job, sites blocked. Now lost only if empty at two passes with no order between: failed builds 10-23 -> 5-7 by 2:00 (swe36-37); buildings level at 2:00 (640 vs 640, swe36).
  - Commander's unseen-raider risk counts only raiders built early enough to walk to the site: CommRedirect 0 (swe37; it read risk 3700-4341 at danger 0.0-0.4 in swe36).
  - Harness: `build_m` (mobile builders and factories - factory defs have canMove and were counted nowhere); swing.py's total value includes it.
  - swe37 stopped 3:00 on army (31 vs 240), income 8.9 vs 13.5: the vehicle plant made one Rover and two constructors in ~110 s with energy short on both sides. Next: why the plant under-produces (energy plan vs the plant's draw, and the plant's queue).
- **swe38-41:**
  - Joining a build valued by the build power our resources can feed (the commander assisted an energy-starved constructor ~60 s at 0/1150 E, swe37): swe38 assist ~9 s, energy 70/80/110.
  - Start value's expansion term counts claims only while they pay (was -1072..-1497 everywhere): start moved to (832,2392), next to the players' (936,2562) (swe39).
  - Builders step off their own site before building.
  - **Script blindness, the game's build blocks:** BAR's Build Blocking API blocks wind turbines on low-wind maps (and water/geothermal units where there is none) via team rules params `unitdef_blocked_<id>`; the AI couldn't see them and the commander ordered a wind turbine 21 times over 64 s (swe39-40, plant at 122-124 s). The core reads them every 10 s and makes blocked defs unavailable ([ANV-BLOCKED]); the opener skips unavailable plants. (SCRIPT_SIGHT.md: exposed.)
  - swe41: failed builds 8; at 3:00 total value 2426 vs 2038, buildings 1290 vs 950, energy 160 vs 151, income level - the best 3:00 of the series; stopped on army alone (141 vs 258; winners 186-527).
- **swe42-43, strength on one scale:** the plant's square law mixed the core's threat damage (ours) with sustained dps (theirs): ours 19 vs 143. Both now sqrt(dps x health); the army only (commanders out both sides, they stay home in 1v1); unseen floor = max(our surface army, the raiders the opener's model gives them) - sSurf + sAir had counted a both-domain unit twice (E 1665 vs 832). swe43 reached 4:00 (army ahead at 2:00, 181 vs 146; stopped on income 13.5 vs 18.1, army 212 vs 626). SurfPower's per-type power was still in threat damage (19 vs 1227 per type): now dps too (swe44).
  - **The flaw left:** a fighter is valued by how much it raises a global win share S/(S+E); behind (E 869 -> 1714 vs our 198) one more fighter barely moves it and the plant builds constructors - the gap grows. Players build army when behind. Next: value a fighter by the losses it prevents in the fights that come (their raid groups against our home defence - army + commander + towers), not a global share.
- **swe44:** SurfPower in dps too. The plant now matches the Comet Catcher winners: constructor at 83 s, then a Rover every ~9 s (winners: constructor 91 s, Rovers every 4-8 s). At 3:00 army 248 vs 129, total value 2178 vs 2109; income 8.9 vs 13.5. Stopped on damage share (0.07): two lone Rovers (62 metal) died to Grunts while scouting (113 s, 180 s), our first raid group (6 Rovers) still on the way to their corner. Next: lone scouts into Grunts (Rover vs Grunt facts: who outranges whom), and the income gap (3 extractors at 3:00).
- **swe45, best of the series:** EffThreat's plain strength moved to dps too (with SurfPower in dps and plain in threat damage every unit read many times stronger: lone Rovers attacked Grunts, swe44). Plant: constructor, Blitzes and constructors. At 4:00 army 660 vs 441, buildings 1350 vs 1190, total 3005 vs 2581, kill share 1.00; stopped on metal income alone (11.2 vs 18.1): BARb out-expands; our raids go to unseen spots at their far corners ("target gone", 40-90 s each, 43 metal killed).
- **Job share (core, untested in a game):** `AnarvaJobTime` divided a job's value by 1 + its assignees, the builder itself included - its own job read at half value against any other: constructors switched extractor <-> radar every second for 14 s (swe45, 206-219 s), extractors 4 vs BARb's 7 at 4:00. Now the others only. swe46 was stopped at once: the owner opened BAR (installed build = this one).
- **Metal income (owner: "you should have addressed the metal income issue"; "barb is not even that efficient in metal production and we are just using it as a starting point"):** swe45 had 4 extractors at 3:00 and 4:00 against BARb's 5 and 7 (constructors 2/4 vs 4/5); the first constructor took 54 s for its first extractor (walk + job switching). Changes (untested, BAR open): job share excludes the builder itself (core); the constructor's value adds its build power's spending of unspent metal (income + bank over a producer's life - pull, up to build power x extractor metal per build-second), over the claims' horizon - the unspent-share discount alone made constructors worth less exactly when metal floated. BARb is a gate; the yardstick is the winners' curves (Comet Catcher: 8.9 M/s at 2:00, 13.5-15.8 at 4:00; BARb reached 18.1).
- **swe46 (after the owner's BAR closed):** constructors 1/3/5 at 2/3/4 min - level with BARb's 2/4/5 (the spend term works) - but extractors 3/4/4 vs 3/5/5, income 11.2 vs 13.5 at 4:00 (stopped there; army 550 vs 484, total 2995 vs 2904). The swe45 "switching" was a misread: [ANV-PICK] lines carry no unit id - several constructors, 1 real [ANV-SWITCH]. The real cause: metal at 0-2/1300 while jobs were ranked by walk + build time as if metal were free - 2 solars, a nano and 2 extractors from 5 constructors. Change (core, untested - the owner is playing): a job is no sooner than its metal arrives (cost beyond the bank / this builder's share of income), so in a stall the cheap paying jobs (extractors) come first. Not installed yet.
- **swe47-48:** metal-arrival job time (swe47: no stall - 380 banked - constructors took base solars 139 vs extractors 178, 3 extractors 2:00-4:00, 2 lost to Grunts, the army 1.5-3x BARb's dealt 0 damage). Two-way comparative advantage (constructors leave base work the commander does sooner): swe48 reached 5:00, the series' best - total 4030 vs 3406, buildings 1970 vs 1660, kill share 0.67; stopped on income 13.5 vs 18.1 (extractors 5 vs 7 with constructors 6 vs 5).
- **Metal-stall priority (core, untested; installed at 1:18 as the owner started BAR):** in a stall, builders on jobs that make no metal are passive, extractor builds get the metal first (swe48: 106 extractor picks at 0-1 metal, 5 extractors vs 7 at 5:00). swe49 cancelled at start (owner playing).
- **Busy builders (core, untested):** the comparative-advantage tests treated the other builder as free: a constructor left an extractor to the commander (factor 10-500) while the commander built solars - extractors scored 8584-48527 for the first constructors at 133-149 s, ~80 s of nano/assist/towers (swe48, spectator). Now the other builder's time includes finishing its current job. Open: one Grunt valued at ~6000 in recalls (swe48).
- **CPU (owner, 2026-11-27: "i ran a game of my friend vs anarva and cpu is at 100%"):** nothing of ours was running; BAR's spring.exe ~1.35 cores at minute 26. Its infolog shows the engine's hang detector at load naming the skirmish AI (the start planning: ~29 candidates x an opener plan each). Added [ANV-CPU] (AI time per update, mean/max per minute, units). Next: a long headless game to find the loops that grow with the unit count (SpotLife per free spot x our units, OursThreatened's kill walk per enemy, comparative advantage over all builders) and cut them.
- **Owner's friend game (2026-11-27 01:42, Supreme Isthmus, Anarva vs [AoW]Vritrasura + biong; replay analysed with the new FACT/SHAPE lines):**
  - Economy fine to minute 12 (31.9 M/s at 14:00); from 13:45 to 25:00 both factories sat with EMPTY queues (FACT q0) while "executing", both banks full (1850/1850 M, 2265/2265 E): production 990 -> 305/141/52/0 metal/min, army 346 units flat from 16:00, power 59 -> 4, labs dead 22:52-23:46. Cause: a factory order was issued once and trusted (`buildIssued`); orders lost on the way (delayed under the 100% CPU, or the finish-time dequeue of the same type) left the factory idle until the task timed out (~70 s per unit). Fix (core): re-issue when the queue holds no build a check after the order. Not a skill gap - a production bug.
  - Squad shape (SHAPE): the players' biggest squads aspect 5.3, ~520 long (lines); ours 2.0, 110-170 (clumps) - matches the owner's screenshot (#119); facing ~50 deg, not conclusively perpendicular (one game).
- **T2 lab (owner: "you cancelled t2 lab 5 times"):** friend game - armalab job failed to start 42 times (constructor 592 away, still, empty queue: lost orders), lab stood at 17:09 vs the opponent's 10:41. BARb's watchdog answered a lost order with a nudge away (counted as a failure, job aborted after the retries, site blocked). Now it re-sends the same order ([ANV-REISSUE]). Untested (owner's BAR open).
- **Expansion first (owner: "change the way you think then", after the Vritrasura replay view):** the constructor value no longer scales spots by our army's map control (the raid model SpotLife already prices raid risk - counted twice, far spots read worthless early) and no longer zeroes when one constructor is idle or assisting (the marginal gain over all constructors already counts it; the gate read 0 most of the friend game: 2 constructors by 5:40 vs Vritrasura's ~15). Untested (owner's BAR open).
- **CPU (#121):** [ANV-PROF] found Scout::Update at ~90% of the script (1373 ms per game minute, 34 ms at once by minute 4): its greedy pick loop rescanned every cell x asset x earlier pick at every pick. Now each cell's fixed value is computed once and the direction term updated per pick: 158 ms/min, max 3 ms; the AI's mean update 1.14 -> 0.42 ms (swe51). The worst update (29-30 ms) is now in the core (builder job picks next). swe51: 6 constructors but 3 extractors at 4:00 (BARb 4 and 8).
- **swe52:** a new pick counts as a fresh order (the re-send had put an old solar back over a just-picked extractor, spectator swe50): income level with BARb at 4:00 (15.8 vs 15.8), extractors 6 vs 6, total value 3065 vs 3024; stopped on army (220 vs 344). Constructors still spend long on GUARD (assisting the plant). CPU: per-frame cache of the production facts the job valuation looped all units for, per candidate.
- **swe54-56:** DefenceGain (fighters valued by raid losses prevented); factory re-send only after two empty checks (early re-sends duplicated builds); the core's value horizon at least the raid model's life of our extractors (swe55: constructors picked nano turrets 35 vs extractors 16 - extractor 546 vs nano 151; swe56: extractor 135 picks, nano 2, median extractor 52 vs nano 1969). swe56 still 4 extractors vs 8 at 4:00: metal at 0 from 3:00 (the plant drew the bank against extractor builds), far spots first (683-1035 while a 246 spot waited). Now: the factory is passive in a metal stall while an extractor is being built.
- **swe58-59:** extractor metal discounted for energy only while energy binds (swe58: 4th extractor at 143 s vs 202); defence value just in time (swe59: at 4:00 army 330 vs 129, buildings 1700 vs 1390, total 3160 vs 2709, kills ours; stopped on income 11.2 vs 18.1 - extractors 4 vs 7: a constructor took 76 s to cover ~800 elmos to its extractor, cause unknown; [ANV-PICK] now logs unit id, position and speed).
- **swe60-61 (unit ids in [ANV-PICK]):** a constructor assisted the plant's next constructors for 90 s at speed 0 - the assist was valued as an undiscounted extractor while the real extractor job carried the energy-binding and kept-share discounts: now priced alike. swe61: income ahead at 3:00 (12.9 vs 8.9), army 93 vs 360 (BARb army-heavy); stopped on army. Constructors still flip jobs (#1252: extractor -> nano -> llt within 70 frames): they re-pick every ~15 frames and the nano's build-power value rides an "overflow" that jumps whenever the plant is between builds, over the raid-model horizon (2331 s). Next: build power valued on sustained overflow only; the army/expansion balance (army 93-330 vs BARb 129-581 across swe57-61 while income swings with it).
- **swe62-63, why constructors don't claim:** build power on sustained spare metal (swe62: fewer flips, still 3 extractors at 3:00). [ANV-MEXVAL] (swe63): the extractor job's window is the value horizon H, 275-340 s (once 34653), because the raid model's life of our extractors is short (army away -> each raid clears every exposed site -> life = time to the first raid, floored by the threat horizon). So V = yield x ~300 - cost = 260-450 and assisting the plant's next constructor (90-213 builder-ms/metal) beats claiming (107-250). The model is wrong twice: a raided spot is rebuilt and keeps producing (its value over the horizon is yield x H - raids x RaidLoss, not yield until the first raid - RaidLoss already counts cost + yield until rebuilt), and H swings 275 -> 34653 between calls. Next: value an extractor over a stable horizon net of expected raid losses (raids = H / life x RaidLoss), the same in the script's constructor value and the core's job value.
- **swe64:** assisting a unit in a factory valued as joining it (factory power as B) - constructors now pick extractors (76 vs 8 nano, 1 assist), 5 extractors built by 208 s, but 2 lost to raids (3 standing at 4:00 vs BARb 6); army 110 vs 626, kills 0 vs 1; stopped on income 8.9 vs 15.8. The economy side now claims; the open side is the army: too little (the plant's fighter value) and not defending the claimed spots.
