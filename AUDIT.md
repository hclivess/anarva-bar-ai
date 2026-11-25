# Audit: every random number and hand-picked constant

Rule ([CLAUDE.md](CLAUDE.md) §2): no random numbers, no constants. Every decision is computed from measured game
state, unit facts or replay evidence. This file is the inventory; it may only shrink. Each item is replaced by
the computed rule in its last column, behind a flag or switch, and measured.

Audited 2026-11-24 (four parallel reviews): AngelScript brain (`brain.as`), the other scripts, the JSON configs
the core reads, and the C++ core (BARb's CircuitAI + Anarva's patch).

## Summary

| Area | Random | Thresholds | Weights | Notes |
|---|---|---|---|---|
| `brain.as` | 0 (6 removed 2026-11-24) | 63 on by default, 37 off | 17 on, 19 off | S1-S4 structural issues below |
| other scripts | 12 (2 calls removed; opener weights, 256-elmo placement jitter remain) | 30 | 51 (45 fixed opener build orders) | storage-fraction economy flags gate brain decisions |
| JSON configs | unit-mix dice, random retreat levels, random energy caps, porcupine offsets, factory select offset | income ladders, quotas, limits, energy curve | per-unit threat/power mods, response matrix | some keys dead or misspelled |
| C++ core | 16 | 47 | 13 | + 4 commit timeouts; rand() seeded from the clock |

## Status 2026-11-24 night (code only; nothing has been played yet)

**Random numbers: none left.** Every `rand()`, dice, shuffle and random scatter in the core and the scripts was
removed, not gated: dice picks became value per metal, the constructor coin flip became "income unspent", random
map points became the enemy centre, scatter became a golden-angle spread, the Welzl shuffle was dropped (same unique
circle), `AiDice`/`AiRandom` are unregistered.

**The `decide` switch is folded in**: BARb's constant branches behind it are deleted, so only the computed paths
exist. All 59 script flags are folded the same way (brain.as 4008 -> ~2800 lines).

**Constants replaced by facts or decisions** (each with its derivation next to it in the code):
unit power (square law), threat map (flat in range, unknown = mean identified threat, padding = splash + movement to
the next update, long-range guns no longer excluded), task power margins and near-base factors (parity), retreat
(ShouldRetreat only), attack/raid/defend target choice (value per distance / per health, commander = its player's
share), squad standoff (target slip over one reload), spacing (splash geometry, full circle with the flanking
rule), regroup (packing radius, arrival time), joins and merges (reach time, concentration), builder job metric
(rank, then time per value), factory choice (strength added per second), unit fallback (value per metal), energy
(need and payback at the converter rate from converter defs), economy gates (overflow, time-to-empty/full, track
record), porcupine planner, build chains, per-unit config overrides, commander hide/assist caps, airpads, base range
(half-way to the enemy), waypoint spacing (turning diameter), LOS/height (engine reach at height), every 0.9/1.1/
1.2/1.25/1.5/2x/8x/16x margin; in the scripts: recycler, intel, phantom threat, shields/AMD/silo/mex/converter facts
generated from unit files (`tools/gen_facts.py`), order lifetimes (walk + build at mean build power), commander job
span (planning horizon), fortification spacing (unit radii), trade estimate (horizon decay, located kills),
production weights, economic position (#41), raided extractors (#43).

**Timers are decisions too (second pass):** orders carry no expiry clock (`NO_EXPIRY`: an order lasts until the AI
changes it); waits, scheduler periods, fallback tasks and checks run on the engine's slow-update tick (`SLOW_UPDATE`,
the AI's own decision rhythm) and the script modules on the same tick; work tasks last until done; leads come from
intercept, flight or update time; fake enemies are remembered while they could still be there; the heat grid cell is a
camera's sight diameter; metal clusters are what one turret holds.

**Config numbers (third pass):** every number read from the BARb JSON configs that reached a decision was replaced
by a fact or a decision, or its parse was deleted when it no longer reached one: response matrix, quotas, thr_mod
ranges, retreat levels, base-defence timeline, superweapon weights and conditions, energy table and factor ramp,
build delay, ms_pull, mex_max, eps_step, mex_up, excess, em_ratio (now measured from converter defs), goal_exec
(now game time), escorts, base/commander radii, point_range and cluster_range (now turret reach), infl_rad (weapon
reach), slack_mod, aa_threat, shields (any charge / full), hide, assist_fac, morph time, anti_cap, factory
importance/select/no_air/air_map, caretaker count, min_land (majority), and the map-region thresholds (largest
factory footprint; merge when a passage is a factory wide).

**What still has digits, all inside CLAUDE.md section 2's allowed set or deciding nothing:**
- Game, physics and math facts and unit conversions: 30 frames per second (`FRAMES_PER_SEC`, `SLOW_UPDATE` is the
  engine's 30-frame slow update), 65536 angle units, `sqrt(0.5)` ballistics, the exact octile heuristic `2 - sqrt 2`,
  `~sqrt(2)` diagonals, Euler's number, the engine's capture formula, a uniform turn's mean (`EXPECTED_TURN = 90`),
  "half the map" for majority, numeric guards (`1e-3`, `INT_MAX` as "never").
- Zero-K's pylon grid (`EnergyGrid`, `PYLON_RANGE`): BAR has no pylons, so it never acts.
- Debug drawing colours and log formatting.

## Highest impact, on by default (fix order)

1. **The army is chosen by dice.** `FactoryManager::RequiredFireDef` / `GetFacRoleDef` roll over `factory.json`
   tier probabilities with an income ladder (`income_tier`). Replace: Anarva's production chooser (`Brain::Production`,
   largest gap between target value share and built share, value = Lanchester strength per metal, plus the map's
   water share for amphibious units) for every pick, including constructors and the opener.
2. **Retreat levels are random draws.** `behaviour.json retreat.fighter [0.5,1.0]`, `retreat.builder [0.85,1.0]`
   read as a random range once per game per unit type (MilitaryManager.cpp:251, BuilderManager.cpp:268).
   Replace: retreat when the value of staying (damage still to deal) is below the value of surviving the trip home
   (time-to-death under incoming damage vs travel time).
3. **Constructor coin flip** (FactoryManager.cpp:1046-1048 `r >= RAND_MAX/2`, plus `BP >= income x bpRatio`).
   Replace: constructor value (unspent income over its life) vs army value of the same metal.
4. **Unit power formula** (CircuitDef.cpp:658-662 `sqrt(dps)*dmg^0.25*sqrt(hp+1.5*shield)/128`) feeds every
   engage/retreat/threat comparison. Replace: Lanchester strength from unit facts.
5. **Factory switch** (factory.as, `AiRandom(8000,12000)`). DONE 2026-11-24: higher tier only when the tech value pays.
6. **Energy**: random count caps per type (armwin [10,20], fusion [3,4]), clock-tied factor (`energy.factor`, only
   2 of its 4 points read), efficiency overrides. Replace: build on projected energy deficit, type by payback.
   Big energy placed at fixed `EnergyBase2` for cost >= 1000 with one builder: place by completion time (build
   power in reach) and risk.
7. **"Pushed back"** (`brain.as`: lostNear > 300 && > 1.5 x lostFar, near = 1500 elmos) cuts build power to
   max(0.35, ratio). Director clamps scale to [1,2], trade floored at 0.25.
8. **Storage-fraction economy flags** (economy.as:26-36: empty 20%, full 99%, stall 30%/60%, full 88%) gate
   expansion, production, conversion, salvage. Replace: time-to-stall projection.
9. **Trade estimate** (0.992/s decay, 50-metal prior, 3000/s kill cap) feeds ratio, scale, tech, moho pricing.
10. **Near-base multipliers** ("400% near base" DefendTask.cpp:268, "200%" RaidTask.cpp:298), per-task power
    margins (scout/raid 0.75, attack 0.8, bomb/anti-heavy 2.0), promotion floors (quota.attack 60).
11. **Fixed opener build orders** (commander.as:49-117): the first 12 units fixed whatever the map.
12. **Strategic clocks** (Juno minute 12, shields minute 14, tactical launcher minute 18, nuke minute 30, one
    order per kind per 4 min), Intel clocks and caps, phantom-threat squad sizes.
13. **Build-position jitter** (`task.as` shake = 32 squares: core moves every build up to 256 elmos at random).
14. **Threat map** (falls to half at range edge; THREAT_MIN = 1 as the "safe" cutoff everywhere).
15. **Builder task weights** (`1/(priority+1)^2`, energy x8, defence x2, 60 s max travel).

## Structural problems

- **S1** `Strategic::Fortify` runs the old F_FORTIFY path (off) whenever map analysis doesn't match our start.
- **S2** `Waste::metalOverflow` is only set when F_WASTE (off) runs: always false, so the tech gate's overflow
  branch and the Director's overflow scaling never fire.
- **S3** scout recruit ignored its air-lab list. FIXED 2026-11-24.
- **S4** live gates read core flags set by fixed storage fractions (item 8).
- Core `rand()` is seeded from the clock unless `random_seed` is set; start positions shuffle with
  `std::random_device` regardless. Until the random rows are gone, test batches should fix the seed.
- Bug: AttackTask.cpp:267 `distBE / sqOBDist` divides a distance by a squared distance.
- Dead/misspelled config keys: `energy.factor` points 3-4, `eps_step` (no effect when alone), `threat.vs`
  `raiders`/`vy`/`anti-heavy`, `buildpeed`, `quota.anti_cap: 2.0` (a probability of 2).

## Full tables


### brain.as

# brain.as constant / randomness audit

**What was audited:** `Anarva/stable/script/anarva/misc/brain.as`. The file was being edited while I worked on it: it grew from 3471 to 3530 to 3570 lines. All line numbers below point to the frozen copy taken at 19:32:
`C:\Users\CYPHER~1\AppData\Local\Temp\claude\1f222efd237d084e\cb4235e9-dd1d-4e28-aed7-09b22b884316\scratchpad\brain_snapshot.as` (3530 lines).
Code added after 19:32 is covered in section 4.

**How "on/off" was decided:** by tracing the dispatcher `Brain::Update` (snapshot l.3474-3527) and the callers in `manager/*.as`, not only by reading the flag names:
- **Live by default:**
  - Intel::Update (F_INTEL)
  - Assess::Update (always runs)
  - Director::Update (always runs; it applies `scale` because F_SCALE is on)
  - Army::CheckSquads (F_RECALL)
  - Recycler (F_RECYCLE)
  - Strategic (F_STRAT, which runs TerrainFortify through F_TERRAIN)
  - Hold (F_HOLD)
  - CommGuardUpdate and CommanderTask (F_COMMGUARD)
  - Production::MakeTask: only MineLayerTask (F_TERRAIN) and MohoConTask (F_MOHO)
  - Tech::Allowed (no flag; called by factory.as)
  - Intel::InitPhantomThreat (Init runs it unconditionally)
- **Off by default:**
  - Army::Update (F_QUOTA)
  - Army::MakeTask (F_WAVES)
  - Waste (F_WASTE)
  - Convert (F_CONVERT)
  - Energy (F_ENERGY)
  - Eco (F_ECOGATE)
  - Redirect (F_REDIRECT)
  - Scout (F_SCOUTMAP)
  - Storage (F_STORAGE)
  - CounterUpdate (F_AA)
  - The Production chooser (F_PROD)
  - Rez (F_REZ)
  - Expand (F_EXPAND)
  - F_BOOM, F_JIT, F_COMMRISK, F_COMMFWD, F_COMMSPOT, F_COMMZONE

**Structural findings (on by default, not literals, but they affect decisions):**
- **S1. A hidden off-flag path still runs.** `Strategic::Fortify` (l.1638) only returns early when `!F_FORTIFY && !F_TERRAIN`. When `TerrainFortify()` returns false (map not analysed, our start not matched, or no base), the *old F_FORTIFY heat-turret path runs anyway*. Its rows below are marked "on*".
- **S2. Dead input in live decisions.** `Waste::metalOverflow` is only written by `Waste::Update`, and that only runs under F_WASTE, which is off. So it is always false, yet these live code paths read it:
  - `Tech::Allowed`: T3 is now allowed *only* when the enemy fields super units.
  - The Director's overflow branch (l.2936) never runs.
  - `manager/economy.as:39` (factory assist) never sees it.
- **S3. Scout recruit ignores the air-lab preference.** In `Intel::Update` (l.1180-1182) `facs` (air labs preferred) is computed but never used. `FactoryReachedSoonest(basePos, null)` searches *all* factories, so a ground lab near base wins and the "air scout" becomes a ground scout. The same function, called with `basePos`, also always returns the same factory for Redirect guards (off by default).
- **S4. Thresholds borrowed from economy.as.** The live code relies on `aiEconomyMgr.isEnergyStalling / isMetalFull / isEnergyFull / isMetalEmpty`. `manager/economy.as:26-36` sets these with hand-picked cutoffs (0.2, 0.99, 0.3, 0.6, 0.88 of storage, and a 3-minute clock). That file is outside this audit, but every Recycler/Convert/Expand gate inherits those cutoffs.

---

## 1. RANDOM

| line | code (short) | kind | flag (on/off) | what it decides | live replacement |
|---|---|---|---|---|---|
| — | *no `AiRandom` / `AiDice` left in the snapshot* | RANDOM | — | — | — |
| (old 1151) | `facs[AiRandom(0,n-1)]` scout factory | RANDOM (removed) | F_INTEL on | which lab recruits the scout | Already replaced by `FactoryReachedSoonest`, but see S3. The replacement should score candidate labs by (scout build time ÷ the lab's free build power) plus the scout's travel time to the stalest target cell, and choose among air labs only when any exist. |
| (old 1940) | `AiRandom(0,99) < BuilderSharePercent()` | RANDOM (removed) | F_PROD off | constructor or army pick | Already a quota (l.1972). Remaining debt: `CORE_BUILDER_SHARE` (see section 3). |
| (old 2000) | `AiDice(scores)` | RANDOM (removed) | F_PROD off | which unit to build | Already "largest deficit" (l.2034-2041). |
| (old 2105) | `allFactories[AiRandom]` nano site | RANDOM (removed) | F_WASTE off | where the nano goes | Already `FactoryWithFewestNanos`. Better: place it at the factory where an added nano raises spent metal per second the most, i.e. whose queue is longest relative to its build power. |
| (old 2457 and 3044) | random factory for Redirect guard and commander assist | RANDOM (removed) | off / F_COMMGUARD path | which factory to assist | Already `FactoryReachedSoonest`. For Redirect: the factory with the largest (queued army metal ÷ build power), minus walk time × the builder's own rate. |

## 2. THRESHOLD / WEIGHT in code that is on by default (most damaging first)

| line | code (short) | kind | flag (on/off) | what it decides | live replacement |
|---|---|---|---|---|---|
| 2685 | `pushedBack = lostNear > 300.f && lostNear > 1.5f*lostFar` | THRESHOLD | Assess, always on | "pushed back". This cuts build-power `scale` to max(0.35, ratio) and blocks Expand | Pushed back when the metal we lose near home per second (decayed window) is more than our army can replace from income in the same window, i.e. lostNear-rate > income × army share. Equivalently, when the home-trade (killedHome/lostNear) is below 1 *and* lost home value per second exceeds what a defender bought now would save. No 300, no 1.5. |
| 2652 | `home = dist < 1500.f` | THRESHOLD | on (F_ZONES off) | which losses count as "near home". Feeds pushedBack, trade split and lostNearTotal (terrain hits) | Already written: `OnOurSide()` (nearer our base than any known enemy building). Make it the default, or use dist < half of the measured base-to-enemy path (`mapInfo.basePath` / enemy position). |
| 2915 | `scale = AiMin(1.f, AiMax(0.35f, ratio))` | THRESHOLD | F_SCALE on | eco floor while pushed back | Drop the 0.35 floor. Scale from the marginal value instead: one more constructor's income over the horizon vs. one more army unit's saved losses (lostNear-rate × the unit's share of needed power). Use the ratio unclamped, and keep the floor only at the constructors needed to keep the existing build queue busy. |
| 2933 | `scale = AiMin(2.f, AiMax(1.f, ratio))` | THRESHOLD | F_SCALE on | eco multiplier when not pushed back: never below 1, never above 2 | Scale = the buildpower at which one more worker's marginal income over Horizon() equals the marginal army it displaces at the shadow price 1/ratio (the same shadow price used in MohoConTask). Remove both caps. |
| 2903 / 2904 | `theirs / AiMax(0.25f, trade)` | THRESHOLD (called a "guard") | Director, on | needPower is capped at 4 × enemy threat. Sets ratio, i.e. scale, posture, Tech forced, the MohoCon shadow price and Hold. | The clamp is a decision, not just an epsilon. Use a guard on the trade estimate's own denominator (stake prior, see 2681) so that trade is never 0, and let needPower = theirs/trade run free. If low-trade estimates are noisy, weight them by their evidence (metal exchanged / army at stake) instead of flooring them. |
| 2666-2670 | `*= 0.992f` (85 s half-life) | WEIGHT | Assess, on | memory length of lostNear/lostFar/killed. Drives trade, pushedBack and everything downstream | Window = the time a fight actually lasts: the mean engagement time measured live, e.g. our army's travel time to the front (frontDist / allSpeed) plus the time to kill the enemy at our dps. Equivalently, decay per second = 1 − 1/(that time). |
| 2681 | `stake = 50.f` (F_STAKE off) | WEIGHT | on | prior in trade = (killed+50)/(lost+50) | F_STAKE's version (army metal at stake) is the live form. Make it the default, or use the metal of one squad at the current quota (`quota.attack` → metal). |
| 2674-2675 | `AiMin(enemyPrev-ev, 3000.f)` | THRESHOLD | on | max kills credited per second | Credit what the enemy could physically have lost in the second: cap at the threat-value of known enemies within our army's weapon range this second (bridge `AiGetEnemies` × in-range). Or, simpler, take kills from F_ZONES TrackKills (located deaths), which needs no cap. |
| 359 | `p < 0.4f*squadPeak && p < fresh` | THRESHOLD | F_RECALL on (F_NEWRECALL off ⇒ first-gen rule live) | when a squad is recalled | Recall when the squad's expected trade at its target is worse than what it returns as part of the next wave: p × trade < the threat it is engaging (bridge: enemy threat within its range + travel) ⇒ abort. F_NEWRECALL is halfway there (`fresh × min(1,trade)`). Replace `fresh` with the local enemy threat at the squad position. |
| 352 | `squadStart < 20 * SECOND` | THRESHOLD (cadence that commits) | F_RECALL on | 20 s with no recall | Grace = the squad's travel time to its first contact (MoveTime to its target). Before that, peak power is not yet established. Or no grace at all: peak is tracked anyway. |
| 829 | `ai.frame < 22 * MINUTE` | THRESHOLD | F_RECYCLE on (F_STORAGE off ⇒ this branch is live) | no T1 salvage before minute 22 | Salvage when the unit's value-per-metal as army (its power ÷ costM, relative to what the factory now builds per metal: the BestTurret/Score style ratio) is below 1 *and* the metal fits in free storage (Storage::Fits). No clock. |
| 829 | `metal.income < 30.f` | THRESHOLD | on | salvage only when rich | Drop it. The comparison above already covers it. If needed, require that the metal can be spent within the reclaim time: free build power × reclaim time ≥ costM. |
| 830 | `isMetalFull` gate | THRESHOLD (borrowed: economy.as 0.99) | on | no salvage when storage is full | Replace with `Storage::Fits(costM)` (already written, F_STORAGE). |
| 827/830 | `salvagePending.length() >= 2`, `15 * SECOND` | THRESHOLD | on | at most 2 salvages, one every 15 s | Unbounded but self-limited: salvage the next unit while the reclaimers' free build power can absorb it (reclaim time ≤ RECLAIM_TIMEOUT) and the metal fits. |
| 844 | `scouts.length() > 2` | THRESHOLD | on | keep at least 3 scouts before salvaging one | Keep as many scouts as Scout::Update's `worthy` count (cells whose vision value > scout cost). Salvage only scouts beyond that. |
| 820 | `distance2D(...) < 1200.f` | THRESHOLD | on | an "idle at home" T1 counts as obsolete | "At home" = not in any squad/hold task and on our side (OnOurSide), or within the reach of our base defences. Better: the unit is not assigned to an attack or raid task. |
| 701 | `MAX_PENDING = 3` | THRESHOLD | F_RECYCLE on | max concurrent eco reclaims | Allow the next reclaim while it fits (Storage::Fits) and idle build power exists (GetBuildPower − assigned). |
| 702 / 883 | `RECLAIM_TIMEOUT = 90 * SECOND`, `+10 * SECOND` | CADENCE (commits units) | on | how long a reclaim, and a salvaged unit taken from core control, stays committed | Timeout = the expected reclaim time (target costM ÷ reclaim speed of the nearest builder) + its walk time, plus a factor for queueing. A salvaged unit is returned as soon as that expected time passes. |
| 949 | `bigMake >= 0.6f*income && fill > 0.5f` | THRESHOLD | F_RECYCLE on | when solars/winds may be recycled | Recycle a plant when income − pull − (pending reclaim output) − its make ≥ 0 over the horizon *and* its reclaim metal (costM, fits storage) is worth more than its E/s × Horizon ÷ energyPerMetal. That is a direct value comparison. Fill is unnecessary once the surplus test is live. |
| 951 | `HasAfus() \|\| bigMake >= 3000.f` | THRESHOLD | on | advanced solars become recyclable | Same value test as 949 applied to adv solar. No 3000. |
| 959 | `surplus > AiMax(0.08f*income, 40.f)` | THRESHOLD | on | margin of energy that must remain after a recycle | Margin = the energy trend × the build lead time of the fastest replacement plant (the Energy namespace already computes trend and lead). That is exactly what stops a stall from being reversible. |
| 935 / 939 | `fill < 0.1f`, `stallTicks >= 15`, `bigMake < 0.5f*income` | THRESHOLD | on | when retired plants are un-retired (RestoreAll) | Un-retire when projected time-to-empty (current ÷ −net) < the lead time of the quickest big plant (the Energy::Update logic). Drop all three constants. |
| 984 | `highMakers.length() >= 4 && fill > 0.7f` | THRESHOLD | on | T1 makers recycled | Recycle a T1 maker when its metal per second (capE × eff, from Facts::Converter) × horizon < its reclaim metal, or when T2 makers already consume all the spare energy (spare − T2 capE ≤ 0 ⇒ the T1 maker is idle). |
| 757 | `m > 0 ? m : 20.f` (wind/tidal) | WEIGHT | on | energy assumed from wind/tidal (decides recycling and the stall valve) | Read the map: wind = (minWind+maxWind)/2 (Spring `Game.windMin/windMax`), tidal = `Game.tidal`. Or measured: e.income delta when a wind finished. Needs a C++ bridge getter if the script lacks it. |
| 1069 | `t2tier = d.costM >= 120.f` | THRESHOLD | on (InitPhantomThreat always runs) | which tier of army a seen jammer is assumed to hide | Tier from the jammer's build source (Facts::BuildOptions: built by a T2 lab or constructor ⇒ T2), the same rule `Tech::Tier` uses. |
| 1070 | `squad = IsMobile ? 4.f : 6.f` | WEIGHT | on | phantom army size behind a jammer (threat kernel) | Size = the units a jammer actually covers: jammer radius² ÷ the unit footprint spacing, capped by what the enemy could afford. Or use the measured mean enemy group size (`AiGetEnemyGroups` count ÷ groups). Live and sourced. |
| 1161 | `heat *= 0.995f` | WEIGHT | F_INTEL on | memory of where we die (eyes, fallback Fortify) | Decay at the rate at which a hot spot stops mattering: 1/(the enemy's mean revisit time), e.g. the mean time between losses in the same cell, measured. Or the same engagement window as the Assess decay. |
| 1169 | `ai.frame < 3 * MINUTE` | THRESHOLD | on | no vision or scout orders in the first 3 min | Remove. Every order below is already value-gated: heat over threshold, scouts below need. |
| 1178 | `(jamAlert\|\|blind) ? 90 * SECOND : 1<<30` | THRESHOLD (cadence) | on | scout recruit every 90 s while blind or jammed | Recruit a scout when the value of looking (Scout::Update's top cell value: our metal reachable × staleness) > the scout's MetalValue. Scout is off by default, so turn its valuation on for this gate. No timer. |
| 1179 | `scouts < (jam\|\|blind ? 4 : 2)` | THRESHOLD | on | max scouts | Scout count = `worthy` cells (value > scout cost) from Scout::Update. |
| 1199 | `maxEyes = jamAlert ? 16 : 8` | THRESHOLD | on | cap on Dragon's-Eyes cameras | No cap. Build another camera when the heat it would watch (metal lost per decay window there) > the camera's MetalValue. |
| 1202 | `threshold = jamAlert ? 250.f : 500.f` | THRESHOLD | on | minimum loss heat for a camera | threshold = MetalValue(eyesDef) (it pays back if it prevents losing its own cost). Under a jammer, divide by the jammer's hidden share. |
| 1207 | `lastEyesFrame < 3 * MINUTE` | THRESHOLD | on | per-cell camera cooldown | Cooldown = until the previous order's task timeout (2 min) or the camera standing. Either way, track the task instead of a clock. |
| 1217 | `distance2D(basePos) < 900.f` | THRESHOLD | on | "base already has sight" | `AiIsInLOS(hot)`, a live LOS test (the bridge has it). |
| 1224 | `AiMin(350.f, len*0.4f)` | WEIGHT | on | camera stand-off distance | Stand off by (eyes LOS radius − a little), from `eyesDef.losRadius`, so it still sees the cell centre, and no further. |
| 1225 | `EyesNear(hot, 450.f)` | THRESHOLD | on | camera already covers the spot | Radius = `eyesDef.losRadius` (unit fact). |
| 1331 | `costM >= 250.f` (infra) | THRESHOLD | F_STRAT on | what counts as "infrastructure" (NukeRisk value, shield value, AA) | Count every structure, weighted by costM. The sums are already metal-weighted, so the cutoff only drops small things. Or count what a nuke or bomber would kill: everything in blast radius. |
| 1306 | `AiMax(1.f, workers*0.5f)` | WEIGHT | on | build power assumed on the anti-nuke (readiness time L) | Use the build power actually free now: GetBuildPower − assigned, or the share Redirect gives, or the core's assist count for BIG_GUN tasks. |
| 1343 | `lastOrder[kind] > 4 * MINUTE` | THRESHOLD (cadence that commits) | on | one strategic order per kind per 4 min | Re-order when the previous order's task is gone (finished or timed out). Track the task handle like Storage's `countAtOrder`. |
| 1404 | `InfraValue() > 2.f*MetalValue(amd)*(n+1)` | WEIGHT | on | extra anti-nukes once an enemy nuke is seen | One more AMD when the infra *not* covered by existing AMDs (outside their radius, from the def) > its MetalValue. Or, with several silos seen: the missiles in flight beyond what current AMDs can stockpile. |
| 1410 | `minute >= 12 && junos < 1` | THRESHOLD | on | Juno against jammers | Build a Juno when the hidden metal under seen jammers (GetEnemyThreat(JAMMER) → metal) × the share inside Juno radius > MetalValue(juno). More than one if several jammer clusters are worth it. |
| 1418 | `AiMin(6.f, AiMax(0.f, (m-30.f)/25.f))` | THRESHOLD + WEIGHT | on (ratio ≥ 1) | how many shields | No count formula. Order the next shield while BestShieldSpot value × P(attack reaches it), from heat or arty threat, > MetalValue(shield) + its recharge energy over the horizon ÷ energyPerMetal. |
| 1419 | `minute >= 14 && e >= 1500.f` | THRESHOLD | on | shields allowed | Drop both. The energy cost is in the value test above. Energy affordability = spare E/s ≥ shield drain (from def). |
| 1422 | `value >= 2500.f` | THRESHOLD | on | minimum value under a shield | value ≥ MetalValue(shieldDef) + upkeep (see above). |
| 1374 / 1379 | `SHIELD_RADIUS*0.8f`, `*0.85f` | WEIGHT | on | overlap / coverage fudge | Use the true radius from the def. Coverage = d < radius, overlap = d < 2·radius minus the asset footprint. |
| 1259 | `SHIELD_RADIUS = 550.f` | FACT (hard-coded) | on | shield reach | Read from the shield's weapon def (`GetMaxRange` / shield radius) at init. |
| 1428 | `minute >= 18 && m >= 40.f ? (m >= 80.f ? 2 : 1)` | THRESHOLD | on | tactical launchers | One more tac launcher while its expected kill value (enemy static metal within its range from ForwardPos × hit rate) over the horizon > MetalValue + stockpile cost. |
| 1430 / 1363 | `ForwardPos(900.f)`, `AiMin(dist, len*0.5f)` | WEIGHT | on | where the tac launcher sits | Position = the spot on our side (OnOurSide) that puts the most enemy static metal inside its range (tacDef.GetMaxRange). |
| 1434 | `minute >= 30 && m >= 90.f && silos < 1` | THRESHOLD | on | nuke silo | Silo when the enemy metal inside one blast (largest cluster from AiGetEnemyGroups or enemy statics) × P(not intercepted: no enemy AMD seen) > silo + missile cost, within the horizon. |
| 1526 | `distance2D(high/choke) < 900.f` | THRESHOLD | F_TERRAIN on | which losses count as "at the choke" (the trigger for more turrets) | Radius = the max range of the turret standing there (terrainDef.GetMaxRange), i.e. losses the turrets could have prevented. |
| 1570 | `d < 0.25f*straight` | THRESHOLD | on | matching our start to an analysed start | The nearest analysed start. Reject only if another start is nearer to our base (unambiguous match). |
| 1581 | `lastFortify < 30 * SECOND` | THRESHOLD (cadence) | on | at most one fortify order per 30 s | Event-driven already (hit > hitAtLastOrder). Drop the clock, or gate on the previous order being built (terrainBuilt). |
| 1601 | `>= 3 * MINUTE` | CADENCE (commits) | on | unbuilt orders are forgotten | Track the actual tasks (count open DEFENCE tasks with terrainDef) instead of a 3-min assumption. |
| 1604 (with F_DEFSIZE off) | `need = 1` per attack | WEIGHT (implicit) | on | turrets per attack | F_DEFSIZE's metal deficit is the live form: needed = (EnemyArmyMetal − armyMetal − terrainMetal) ÷ turret cost. Better still, in power and at the trade rate. |
| 1616 | `forts % 2 == 1` | THRESHOLD | on | teeth on every other order | Teeth when the turret's DPS time gained (teeth slow attackers by the path detour ÷ speed) × the enemy army it delays > teeth cost. Otherwise none. |
| 1621-1622 | `k = -3..3`, `48.f*k` | WEIGHT | on | 7 teeth, 48 elmo spacing | Count = choke width (mapInfo `choke`) ÷ the teeth footprint (wallDef footprint × SQUARE_SIZE). Spacing = the footprint. |
| 1629-1631 | `k = -2..2`, `96.f + 48.f*(forts%3)`, `64.f*k` | WEIGHT | on (when a minelayer exists) | 5 mines, depth and spacing | Mines across the choke width ÷ the mine's damage radius (def). Depth = just outside our turret range from the choke, so mines hit before the turrets engage. |
| 1885 | `mlvOrderedAt < 2 * MINUTE` and `minelayers > 0` | THRESHOLD | F_TERRAIN on | one minelayer, retry every 2 min | Keep a minelayer while unmined choke width × mine value exceeds its cost. Retry when the recruit task is gone, not on a clock. |
| 2441 | `AiMax(elapsed, 60.f)` | THRESHOLD | on (Horizon feeds Tech, ExpandTask, the Production score, Convert, CommForward) | planning horizon floor at 60 s | Floor = the time to build the investment being judged: the payback must at least cover its build time. Or the enemy's travel time to us (frontDist / enemy speed). |
| 1932 | `AiMax(1e-2f, ratio)` | THRESHOLD (guard) | F_MOHO on | shadow price capped at 100× | Acceptable as a guard. Note that it caps the price. Use AiMax(1/needPower, ratio) so the cap follows the scale of the real values. |
| 1929 | `(C == 0) ? 1e9f` | CADENCE (sentinel) | F_MOHO on | the first T2 constructor is always built | Defensible (the first con turns an impossible upgrade into a possible one). Better: saving with C=0 = extra × U × (time until a T1 con could start them) − (MetalValue(con)). |
| 2952 | `ratio < 0.5f / 1.f / 1.5f / 3.f` | THRESHOLD | on* (posture gates the S1 fallback Fortify; otherwise log only) | posture bands | When TerrainFortify can't run, use "ratio < 1" (can't win an open fight) directly. Keep the bands for logs only. |
| 2957 | `pendingSince >= 10 * SECOND` | CADENCE | on | posture debounce (affects the fallback fortify) | Acceptable for logs. For decisions, use the ratio directly. |
| 3076 / old-path 3104 | Guard timeout `20 * SECOND` (`30 * SECOND`) | CADENCE (commits) | F_COMMGUARD on | how long the commander stays parked after a redirect | Timeout = until CommExposure at the job site ≤ 0 again. Re-evaluate every CommGuardUpdate (2 s) and release the guard then. Or the enemy force's MoveTime to the site. |
| 3439 | Guard `20 * SECOND` | CADENCE (commits) | F_COMMGUARD on | commander retreat duration | Same: release when CommExposure(commander position) ≤ 0, or when the attackers' arrival time has passed. |
| 3072 | `distance / comm.speed` (not MoveTime) | WEIGHT (inconsistent) | on | the commander's time home, used for exposure | Use MoveTime(comm.circuitDef, ·) as CommGuardUpdate does (l.3433), so both tests agree. |

### On* (S1 fallback: old F_FORTIFY path that runs when TerrainFortify returns false)

| line | code (short) | kind | flag (on/off) | what it decides | live replacement |
|---|---|---|---|---|---|
| 1645 | `ai.frame < 5 * MINUTE` | THRESHOLD | on* | no fortify before minute 5 | Drop. Gate on heat ≥ turret cost. |
| 1646 | `lastFortify < 30 * SECOND` | THRESHOLD | on* | order cadence | Gate on the previous turret being built or its task expiring. |
| 1649 | `forts >= int(4.f + m/6.f)` | THRESHOLD | on* | turret cap from income | No cap. A turret while the hot cell's loss rate × horizon > its cost and our army can't cover it (ratio < 1). |
| 1653 | `bestHeat = 150.f` | THRESHOLD | on* | minimum heat for a turret | heat ≥ MetalValue(turret) (it pays if it saves its cost). |
| 1659 | `d < 600.f \|\| d > 2600.f` | THRESHOLD | on* | front window | Front = cells on our side (OnOurSide) outside base LOS (`AiIsInLOS`). |
| 1666-1667 | `m >= 45.f` T3, `m >= 18.f` T2 | THRESHOLD | on* | turret tier by income | `BestTurret()` (power per metal), already written. Use it here. |
| 1676 | `AiMax(500.f, len - 250.f)` | WEIGHT | on* | turret placement | Place at hot − dir × turret range (fire from range, not inside the cell). |
| 1682-1683 | `k = -2..2`, `140.f`, `48.f*k` | WEIGHT | on* | 5 teeth, offset and spacing | Same as 1621: footprint and range from the defs. |

## 3. THRESHOLD / WEIGHT in code that is off by default

| line | code (short) | kind | flag (on/off) | what it decides | live replacement |
|---|---|---|---|---|---|
| 379 | `AiMax(0.25f, trade)` | THRESHOLD | F_QUOTA off | raid size floor | As in 2903: guard the trade estimate itself. |
| 381 | `raidMin * 1.5f` | WEIGHT | F_QUOTA off | raid.avg cap | Let a raid grow while one more member raises its win probability over the expected defenders (Lanchester d²/(d²+c²)) more than it costs elsewhere. |
| 385 | `baseScout + 3` | THRESHOLD | F_QUOTA off | scout quota under jammers | Scout::Update `worthy`. |
| 425 / 428 | `3 * MINUTE` order lock / task | CADENCE (commits) | F_STORAGE off | one storage order outstanding | Track the task handle. |
| 827 | `>= 2`, `15 * SECOND` | THRESHOLD | F_STORAGE off | salvage rate | See 829 (on). |
| 968 | `AfusCount() >= 2 && AfusMake() >= 0.7f*income && fill > 0.6f` | THRESHOLD | F_FUSREC off | fusion recycling | Value test as in 949. |
| 972 | `AiMax(0.1f*income, 200.f)` | THRESHOLD | F_FUSREC off | margin | trend × lead time, as in 959. |
| 1464 | `air < 300.f`, `20 * SECOND` | THRESHOLD | F_AA off | AA counter starts | AA when seen air metal × P(it reaches infra) > tower cost. |
| 1466 | `AiMin(14.f, air/350.f)` | THRESHOLD + WEIGHT | F_AA off | AA count | Towers until summed AA power ≥ seen air threat ÷ trade (Lanchester), per infra cluster. |
| 1470-1471 | `m >= 60.f`, `%4 == 3`, `m >= 25.f` | THRESHOLD | F_AA off | AA tier | Best AA power per metal among the available defs (as BestTurret). |
| 1481 | `< 600.f` | THRESHOLD | F_AA off | tower near infra | The tower's range from the def. |
| 1728 | `CORE_BUILDER_SHARE = 30` | WEIGHT ("config fact") | F_PROD off | constructor share | Marginal value of a constructor: the income it adds (free-spot rate, Director::Expand formula) over the horizon vs its cost. |
| 1743 / 1746 | `AiMax(2, players)` | THRESHOLD | F_MAPECO off | min players | Use the real team count (with 1v1 = 2 already). |
| 1811 | `diagonal * 0.5f` | WEIGHT | F_PROD off | assumed front distance | `mapInfo.basePath × 0.5`, or the distance to the enemy position (`aiEnemyMgr.GetEnemyPos`). |
| 1843 | `0.5f * (lostNear+lostFar+killed)` | WEIGHT | F_PROD off (non-F_REZ branch) | wreck pool | The F_REZ formula (WRECK_SHARE × HoldShare), or the bridge's `AiGetWrecks` total metal: measured. |
| 1962 | `ai.frame < 6 * MINUTE` | THRESHOLD | F_PROD off | opener protection | End the opener when its build queue is exhausted (an event), not by the clock. |
| 1988 | `AiMax(300.f, surf)` | THRESHOLD | F_PROD off | prior on enemy surface metal | Prior = our own army metal (parity assumption, as EnemyThreat does when blind). |
| 1990 | `STATIC * 0.5f` | WEIGHT | F_PROD off | static weight in the surface mix | Statics' threat share (GetEnemyThreat(STATIC) / total) instead of half their cost. |
| 2068 | `MOHO_UPKEEP = 22.f` (20 + margin) | WEIGHT | F_ECOGATE off | energy per moho | MEX_T2_UPKEEP_E − MEX_T1_UPKEEP_E (= 17), with the margin from trend × lead time. |
| 2083 | `fill > 0.5f ? 0.02f*current` | THRESHOLD + WEIGHT | F_ECOGATE off | storage credit | Credit = current ÷ horizon (the storage spread over the time it must last). |
| 2130 / 2131 | `0.95f*storage`, `0.92f*storage` | THRESHOLD | F_WASTE off (but feeds live readers, see S2) | "overflowing" | Overflow = current + (income − pull) × update interval > storage: it actually spills this tick. |
| 2133 / 2134 | `metalSec >= 8`, `energySec >= 15` | THRESHOLD | F_WASTE off | debounce | Spilled metal accumulated > the cost of the remedy (nano / converter). |
| 2142 | `45 * SECOND` | THRESHOLD | F_WASTE off | nano cadence | The next nano when spill rate × horizon > its cost and the previous one is built. |
| 2148 / 2150 / 2151 | `30 * SECOND`, `income >= 35.f`, `spare > 70.f` | THRESHOLD | F_WASTE off | maker cadence / tier / minimum | Convert::Update (payback vs horizon), already written. |
| 2153 | `AiMin(4, spare/(600 or 70)+1)` | THRESHOLD + FACT | F_WASTE off | makers per order | n = spare ÷ capE from Facts::Converter, capped by idle builders (as Convert does). |
| 2329 | `0.95f/0.05f` EMA | WEIGHT | F_ENERGY off | pull trend smoothing | Window = the lead time of the quickest plant (the trend matters over that span). |
| 2344 / 2351 | `workers * 0.5f` | WEIGHT | F_ENERGY off | build power on a plant | The free build power (see 1306). |
| 2388-2391 | build times by name (320000, 56000, 8000, 2700) | FACT (hard-coded) | F_ENERGY off | lead time | `d.buildTime` (already used at l.1928 for the moho). Read it from the def. |
| 2324 | `MM_LEVEL = 0.75f` | FACT (but player-settable) | F_ENERGY off | converter threshold | Read TeamRulesParam `mmLevel` (bridge getter). |
| 2496 | `+ 0.5f` | CADENCE (rounding) | F_REDIRECT off | rounding | Fine. |
| 2482 | `GUARD_SPAN = 45 * SECOND` | CADENCE (commits) | F_REDIRECT off | assist commitment | Re-evaluate and release when the deficit closes (ratio ≥ 1). |
| 2686 | `lostFar > 300.f && > 2.f*lostNear && frontDist > 1800.f` | THRESHOLD | `pushing` is only logged (Status): no effect | — | Remove, or define it symmetrically to pushedBack. |
| 2661 | `0.9f/0.1f` EMA of frontDist | WEIGHT | on, but frontDist only feeds `pushing` (log), the F_PROD score and the old commander path (off) | — | A loss-cost-weighted mean over the Assess window. |
| 2692 | 3-sample (3 min) growth window | CADENCE | log only | — | — |
| 2719 | `waveFrac = 0.30f` | WEIGHT (initial) | overwritten every update; only logged | — | — |
| 2750 | `if (speed < 10.f) speed *= SECOND` | THRESHOLD (units heuristic) | F_EXPAND off | elmos/frame or /s guess | Know the unit: CCircuitDef.speed is elmos/frame in the core. Always × SECOND (or always not). Don't guess from the magnitude. |
| 2752 | `BUILD_SPEED_PER_WORKER * 20.f` | WEIGHT/FACT (unclear) | F_EXPAND off | extractor build time | `MEX_BUILDTIME ÷ con.buildSpeed` (from the def). |
| 2753 | `AiMax(0.5f, income/ours)` | THRESHOLD | F_EXPAND off | income per spot floor | Spot income from the bridge (`si[k]` × the extractor's extraction), as CommForward does. |
| 2915-2937 (F_BOOM) | `income * 60.f`, `AiMin(2.f, ...)` | WEIGHT + THRESHOLD | F_BOOM off | boom pressure and cap | Pressure window = the Assess window. No cap: see 2933. |
| 2930-2931 (F_JIT) | `0.25f`, `AiMin(2.f, AiMax(1.f, jit))` | THRESHOLD | F_JIT off | JIT scale caps | As 2933. |
| 2937 | `1 + metalSec/60.f`, cap 2 | WEIGHT + THRESHOLD | dead (S2) | overflow build power | Build power such that spend ≥ income (spill = 0): bp = income ÷ per-worker spend rate. |
| 2945 | `blind ? 4 : 3` | THRESHOLD | F_SCOUT off | scout quota | Scout::Update `worthy`. |
| 3096 / 3099 | `basePath*0.5f`, `0.5f*front` | WEIGHT | old commander path (dead while F_COMMGUARD is on) | commander work radius | CommExposure (already live). |
| 3276 / 3294 / 3303 / 3344 | `20.f` job span, `/20.f` | WEIGHT | F_COMMRISK / F_COMMFWD off | value of assist, cost of walking | Span = the actual job's remaining build time (buildDef.buildTime ÷ buildSpeed), or the guard timeout made live (see 3439). |
| 3299 | `R = 300.f` reclaim radius | WEIGHT | F_COMMRISK off | wreck field size | The builder's build distance + MoveTime-reachable wrecks within the job span. |
| 3141 | `q < 64` explosion chain cap | CADENCE (loop guard) | F_COMMSPOT off | — | Fine (n units bounds it). |
| 3365 | Spot task `2 * MINUTE` | CADENCE | F_COMMFWD off | — | `fwdDue` estimate (already computed). Use it as the timeout. |

## 4. Code added after the snapshot (live file at 19:35; flags off)

| line (live) | code (short) | kind | flag (on/off) | what it decides | live replacement |
|---|---|---|---|---|---|
| ~3330 | `income * 20.f` "job span (Guard timeout)" | WEIGHT | F_BUILDERSAFE off | value of the safe alternative for a builder | The remaining time of the builder's current job, or the time until the threat leaves (enemy MoveTime past the site). |
| ~3333 | Guard `20 * SECOND` | CADENCE (commits) | F_BUILDERSAFE off | how long a builder stays evacuated | Release when UnitPDeath at its job site = 0. |
| F_HOLDALL block | (no literals) | — | F_HOLDALL off | — | — |

## 5. FACT and CADENCE/LOG (counts only)

**FACT (acceptable): about 40 occurrences**
- Unit conversions and math:
  - `30.f` frames per second (l.609; should use `SECOND`)
  - pi (532-533)
  - `0.5f` cell centre (1088)
  - kinematics `0.5f`/`2.f` (80-81)
  - the expected turn of 90° (72)
  - `2.f*P/(P+T)` normalisation (2442)
  - Lanchester square law (3247)
  - the 2C(C+1) series (1929)
  - bit flags `&1 &2 &4` (483, 2852, 3218, 3385)
  - the percent `100` (1746, 1972)
  - `SECOND`/`MINUTE` multiplications
- Unit-file facts:
  - CELL size 512 (grid resolution, 1005)
  - `AMD_BUILDTIME 60000`, `AMD_STOCKPILE_S 90`, `SILO_STOCKPILE_S 180`, `SILO_MISSILE_M 1000` (1320)
  - `CON_WORK 85` (2188)
  - `BUILD_SPEED_PER_WORKER 4.25` (1727)
  - `MEX_T1/T2_EXTRACT 1/4`, `UPKEEP 3/20` (2409)
  - `MEX_BUILDTIME 1800` (2762)
  - `energyPerMetal` fallback 70 (2426)
  - `WRECK_SHARE 0.6` (1832)
  - `SHIELD_RADIUS 550` (1259)
  - the tier numbers 2/3 (2528-2546)
  - spot match `64.f` (2787)
- Caveat: several of these (the AMD/silo numbers, shield radius, build times, wreck share) are hard-coded copies of unit facts. They should be read from the defs at init, because a balance patch silently breaks them.

**CADENCE/LOG: about 55 occurrences**
- Update dispatch intervals (3488-3502: 2/3/5/10 s)
- `ai.frame % (5*SECOND)` (1172, 2215, 2331)
- Log throttles (2025, 2285, 2566, 2957)
- Array sizes (`ftHist(13)` 257/270, `lastOrder(5)` 1256)
- Sentinels (`-10*MINUTE`, `-10000`, `-2`, `1e9f`, `1e30f`, `1<<20`, `1<<30`)
- Epsilon guards (`1e-3f`, `1e-6f`, `AiMax(1.f, ·)`)
- Recruit radius `64.f`
- Placement shake radii (`SQUARE_SIZE * 6/8/12/16/20/24/32/40/48`)
- Task timeouts (2 min / 3 min / 5 min on build orders)
- Behaviour-changing cadences have been moved into the tables above: 20 s squad grace, 90 s reclaim timeout, 4-min strategic Ready, 30 s fortify, 3-min eyes cooldown, 90 s scout interval, and the 20 s commander guard.

## 6. Tally

| kind | count (snapshot) |
|---|---|
| RANDOM | 0 live. 5 `AiRandom` + 1 `AiDice` were removed while the audit ran (all now systematic; S3 is a bug in one replacement) |
| THRESHOLD, on by default (incl. 6 on*) | 63 |
| WEIGHT, on by default (incl. 2 on*) | 17 |
| CADENCE that commits behaviour, on (702/883, 1601, 2957, 3076, 3439, and 352 counted as THRESHOLD) | 6 |
| THRESHOLD, off / dead | 37 |
| WEIGHT, off / dead (incl. 1 added after the snapshot) | 19 |
| FACT | ~40 |
| CADENCE/LOG | ~55 |

(A line holding several cutoffs is counted once per cutoff. For example, 1428 counts as 3 and 1418 counts as 2 thresholds + 1 weight. Counts are by hand, ±2.)

### Other scripts

# Anarva script audit: literals and randomness (everything except anarva/misc/brain.as)

Scope: `Anarva/stable/script/**` minus `anarva/misc/brain.as`. Paths below are relative to `Anarva/stable/script/`.
The four variant folders (`anarva_b`, `anarva_cs`, `anarva_e`, `anarva_fg`) only `#include` the anarva scripts and contain no literals.
`init.as` has only `"1"` modoption strings, and `unit.as` has no numeric literals, so neither has a row. Both pull in the JSON config profiles (`behaviour`, `economy`, `factory`, ...) that hold most of the inherited BARb tuning. Those profiles are outside this audit and need one of their own.
The generated tables were checked against their generators: `tools/gen_facts.py` is clean, but `tools/analyze_maps.py` contains analysis tunings that shape the `mapfacts.as` data, so they are listed.

Live quantities available to the script (used in the replacements below): `aiEconomyMgr.metal/energy.{current,storage,pull,income}`, def facts (`costM`, `costE`, `buildTime`, `GetEnergyMake`, speed, range, dps, HP), `aiEnemyMgr` threat/cost per role, build power, `ai.frame`, and Brain's own valuations (`Brain::Production`, `Brain::Tech`, `Brain::Waste`, `Director`).
"Horizon H" means the planning horizon Brain already uses for metal-equivalent value.

## 1. RANDOM

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/manager/factory.as:154 (rolled at :54, re-rolled at :134) | `AiRandom(8000, 12000) * SECOND` | RANDOM | Random switch budget (8000-12000 s x 30 = 240k-360k frame units) that `value` must exceed before the factory is allowed to switch | Drop the budget. Switch when NPV(new factory over H: value of its best units against the measured enemy composition, minus factory cost and build-power time) > NPV(keep current factory over H). `Brain::Tech::Allowed` already has the tech-value comparison, so let `AiIsSwitchTime` return that comparison. |
| anarva/misc/commander.as:232 | `int choice = AiDice(weights)` | RANDOM | Weighted dice roll picking which opener queue a new factory gets | Remove the dice. Choose the queue (or better, each next unit; see the opener rows) by argmax of value over H from the scouted state: free reachable mex spots, enemy raider and builder counts, distance to the enemy base. |
| anarva/misc/commander.as:59-60 | `SQueue(0.4f,...)`, `SQueue(0.6f,...)` armavp | RANDOM (dice weights) | 40/60 odds between two armavp T2 openers (live path, F_OPENER=true) | Same as :232: pick deterministically by comparing value, not odds. |
| anarva/misc/commander.as:126,128,130 | FG armlab `0.4/0.3/0.3` | RANDOM (dice weights) | Raider / builder / standard opener odds (FG path, used only when `F_OPENER=false`) | As :232. |
| anarva/misc/commander.as:134,136,137 | FG armvp `0.4/0.3/0.3` | RANDOM (dice weights) | armvp opener odds (FG) | As :232. |
| anarva/misc/commander.as:143,144 | FG armavp `0.4/0.6` | RANDOM (dice weights) | armavp opener odds (FG) | As :232. |
| anarva/misc/commander.as:156,157,158 | FG corlab `0.3/0.3/0.4` | RANDOM (dice weights) | corlab opener odds (FG) | As :232. |
| anarva/misc/commander.as:162,164,168 | FG corvp `0.4/0.3/0.3` | RANDOM (dice weights) | corvp opener odds (FG) | As :232. |
| anarva/misc/commander.as:186,187,188 | FG leglab `0.3/0.3/0.4` | RANDOM (dice weights) | leglab opener odds (FG) | As :232. |
| anarva/misc/commander.as:192,194,198 | FG legvp `0.4/0.3/0.3` | RANDOM (dice weights) | legvp opener odds (FG) | As :232. |
| task.as:67 | `float shake = SQUARE_SIZE * 32` | RANDOM (engine jitter, 256 elmo) | Default for `TaskB::Common`: the C++ core randomizes the build position by up to 256 elmos ("Alter/randomize position by offset") | shake = 0. Choose the site deterministically by value: build-power travel time from assigned builders, threat at the site, and adjacency or blocking. Spacing comes from the footprint fact (`xsize*SQUARE_SIZE`). |
| task.as:102 | `float shake = SQUARE_SIZE * 32` | RANDOM (engine jitter, 256 elmo) | Same for `TaskB::Factory` (factory placement) | As above; for factories also weigh path distance to the front and exposure. |

## 2. THRESHOLD / WEIGHT

### main.as / builder.as

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/main.as:17 | `cdef.costM >= 200.f` | THRESHOLD | Which energy buildings get the BASE attribute (built only at base) | Tag per placement, not per def: build at base when expected loss at the frontier site (P(destroyed before payback) from the threat map x costM) > the extra travel and protection cost of building at base. Payback = cost / (energy make x E-to-M rate). |
| anarva/main.as:17 | `GetEnergyMake(cdef) > 1.f` | THRESHOLD | Excludes defs that make less than 1 E/s from that tag | Fold into the same expected-loss comparison; a def with no energy make has no payback term. |
| anarva/manager/builder.as:37 | `cdef.costM < 200.f` | THRESHOLD | Splits constructors into the "T1 energizer" and "T2 energizer" slots | Use the tech-level fact (which factory builds it, from `Facts::buildOptions`) or skip the split; see next row. |
| anarva/manager/builder.as:38-49 | `energizer1`, `energizer2` (exactly one base builder per tier) | THRESHOLD (hard count of 1 + 1) | How many constructors are locked to base tasks | Base-locked BP = BP needed to finish the base-only queue (sum of buildTime) within its value window. Assign builders to base while the marginal value of a builder at base > at the frontier (expansion value per BP from `Director`). |
| anarva/manager/builder.as:39 | `cdef.count > aiMilitaryMgr.GetGuardTaskNum() \|\| IsAbleToFly()` | THRESHOLD (compares unrelated quantities) | Whether the first T1 constructor becomes energizer | Same marginal base-vs-frontier BP comparison. |

### economy.as (these flags gate brain.as at :799, :904, :918, :937, :1831, :1929, :2043, :2180, :2233, :2452)

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/manager/economy.as:26 | `metal.current < metal.storage * 0.2f` | THRESHOLD | `isMetalEmpty`, which blocks production (brain:2452) | Time to empty: `current / max(pull - income, eps)` < time to bring corrective income online (cheapest mex or reclaim buildTime / available BP). A storage fraction depends on storage size, not on the stall. |
| anarva/manager/economy.as:27 | `metal.current > metal.storage * 0.99f` | THRESHOLD | `isMetalFull` (spill), which gates salvage, energy and conversion in brain | Spill imminent: `current + (income - pull) * updateInterval > storage`. That is a fact-based projection; the interval is CADENCE. |
| anarva/manager/economy.as:28 | `ai.frame < 3 * MINUTE` | THRESHOLD | Early-game regime switch for the energy flags | Delete. The time-to-stall projection handles small early storage without a clock. |
| anarva/manager/economy.as:29 | `isEnergyEmpty = false` (forced, before 3 min) | THRESHOLD | Never report E empty early | Delete; use the projection. |
| anarva/manager/economy.as:30 | `energy.current < energy.storage * 0.3f` (early) | THRESHOLD | Early `isEnergyStalling`, which stops expansion and production (brain:1831, 1929, 2043) | Stalling when `current / max(pull - income, eps)` < cheapest-energy-structure buildTime / BP available, i.e. we would run dry before we could fix it. |
| anarva/manager/economy.as:32 | `energy.current < energy.storage * 0.2f` | THRESHOLD | `isEnergyEmpty` | `current < (pull - income) * updateInterval` (dry before the next decision). |
| anarva/manager/economy.as:33 | `energy.current < energy.storage * 0.6f` | THRESHOLD | Later `isEnergyStalling` (60 percent of storage counts as a stall) | Same projection as :30. |
| anarva/manager/economy.as:36 | `energy.current > energy.storage * 0.88f` | THRESHOLD (BARb proxy for mmLevel 0.75) | `isEnergyFull`, which gates converters and energy (brain:2180, 2233) | Read the live `mmLevel` TeamRulesParam (the converter turn-on level) instead of a copy. Better: E is "full" when the metal-eq value of the excess (`(income - pull)` x converter eff from `Facts::converters`) > the value of that E spent on build power. |
| anarva/manager/economy.as:38 | `metal.current > metal.storage * 0.2f && !isEnergyStalling` | THRESHOLD | `isAssistRequired`: send builders to assist factories | Assist when marginal value per BP-second on the factory (unit value / unit buildTime) > the best open build task's value per BP-second. Metal sitting in storage is waste of opportunity cost x time, not a 20 percent fraction. |

### factory.as

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/manager/factory.as:132 | `pow(ai.frame - lastSwitchFrame, 0.9)` | WEIGHT | Sub-linear time term in the switch score | Delete with the score; use the NPV comparison (factory.as:154 row). |
| anarva/manager/factory.as:132 | `metal.current * 7` | WEIGHT | Weight of banked metal in the switch score | Banked metal enters NPV as idle capital: cost of waiting = current x (value rate of spending). No coefficient. |
| anarva/manager/factory.as:133 | `value > switchLimit` | THRESHOLD | Switch trigger (against a random budget) | NPV(new) - NPV(keep) > 0. |
| anarva/manager/factory.as:83 | `spam = {"armpw","corak","armflea","armfav","corfav","leggob","legscout"}` + `SetIgnore(true)` once any T3 factory exists | THRESHOLD (hand-picked list and trigger) | Stop targeting light T1 units after T3 | Per enemy type: ignore while (its dps x expected time alive near our assets, the damage it does) < (our dps-seconds spent killing it x their value elsewhere). All of it is computed from def facts and the threat map, and recomputed as the composition changes. |
| anarva/manager/factory.as:103-108 | builder `NORMAL` + `BUILDPOWER`, combat `HIGH` + `FIREPOWER` | WEIGHT (fixed priority order) | Opener combat units outrank opener builders in the queue | Priority from value: rank queued items by value over H / buildTime (see opener rows). |
| anarva/manager/factory.as:110-111 | `jcount = opener[i].count`, enqueue all at factory creation | THRESHOLD | Commits the whole opener queue up front, before Brain::Production sees it | Enqueue one item at a time via `Brain::Production::MakeTask` so each slot is a live decision. |
| anarva/manager/factory.as:111 | `Recruit(..., pos, 64.f)` | THRESHOLD (low impact) | Recruit task radius around the factory | Use the factory footprint fact (`xsize * SQUARE_SIZE / 2`) or the factory's build range. |

### military.as

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/manager/military.as:47 | `ai.frame > 5 * MINUTE` | THRESHOLD | Clock gate before any cluster defence is built | Build defence at a cluster when expected prevented loss (enemy threat that can reach it within the defence's buildTime x value of the cluster's mexes and builders x P(raid) from observed enemy raider positions) > defence cost + BP opportunity cost. |
| anarva/manager/military.as:48 | `metal.income > 10.f` | THRESHOLD | Income gate for defence | Same comparison; income enters only as the opportunity cost of the metal. |
| anarva/manager/military.as:49 | `aiEnemyMgr.mobileThreat > 0.f` | THRESHOLD (any threat at all) | Builds defence as soon as any enemy mobile threat exists | Same comparison, weighted by the threat's reachability to that cluster. |
| anarva/manager/military.as:62 | `GetEnemyThreat(AA) <= 80.f` | THRESHOLD | `AiIsAirValid`: whether air factories keep producing (marked deprecated, but the C++ core may still call it) | Air is valid when expected value an air unit delivers before dying (its dps x survival time under the measured enemy AA dps vs its HP, times target value) > its cost, and > the best ground alternative. Or return true and let Brain::Production decide. |

### commander.as openers (live path, F_OPENER=true)

Each order is a hand-picked build order. Shared live replacement (R-OPEN): pick each next unit in Brain::Production, not from a list. For a builder, value = (reachable free mex spots per builder x mex income x remaining H) + BP for energy, minus cost. For a raider or scout, value = expected enemy builder and mex value killed or denied (scouted enemy builders, unprotected mexes, path length) + map-control value, minus cost. Build whichever is higher. Constructors stop when their marginal value falls below a combat unit's.

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/misc/commander.as:49 | armlab: B,R,B,R,B,R2,B,R2,B,R (5 B, 7 R) | WEIGHT (fixed build order) | First 12 units of armlab | R-OPEN |
| anarva/misc/commander.as:53 | armvp: B,S,R,B,R,B,R2,B,R2,B | WEIGHT | First 12 units of armvp | R-OPEN |
| anarva/misc/commander.as:56 | armalab: B2,RIOT,ASS2,B2,ASS,SKIRM,B2,AHA2,B2,HEAVY,B2 | WEIGHT | armalab T2 opener | R-OPEN; for combat roles, counter value against the measured enemy composition (`aiEnemyMgr` cost per role) |
| anarva/misc/commander.as:59 | armavp q1: B2,SK2,B2,SK,B2,AHA,B2,SK,AHA,B2 | WEIGHT | armavp opener A | R-OPEN |
| anarva/misc/commander.as:60 | armavp q2: B2,SK,B2,SK,B2,SK2 | WEIGHT | armavp opener B | R-OPEN |
| anarva/misc/commander.as:63 | armshltx: R,RIOT2,ARTY2,SUPER | WEIGHT | T3 gantry opener | R-OPEN (counter value) |
| anarva/misc/commander.as:66 | armsy: S,B,S,B,R,S,B,SUB,SK | WEIGHT | Shipyard opener | R-OPEN; naval value scales with the measured water share and the enemy fleet |
| anarva/misc/commander.as:69 | armasy: B2,SK,B2,SK,B2x2 | WEIGHT | Adv shipyard opener | R-OPEN |
| anarva/misc/commander.as:73 | corlab: same as armlab | WEIGHT | corlab opener | R-OPEN |
| anarva/misc/commander.as:77 | corvp: same as armvp | WEIGHT | corvp opener | R-OPEN |
| anarva/misc/commander.as:80 | coralab: B2,R3,B2,R3,B2,SK,HEAVY,B2,ASS2,B2 | WEIGHT | coralab opener | R-OPEN |
| anarva/misc/commander.as:83 | coravp: B2,SK2,B2,ASS,B2,HEAVY,B2x2 | WEIGHT | coravp opener | R-OPEN |
| anarva/misc/commander.as:86 | corgant: R,ASS,ARTY2 | WEIGHT | corgant opener | R-OPEN |
| anarva/misc/commander.as:89 | corsy: as armsy | WEIGHT | corsy opener | R-OPEN |
| anarva/misc/commander.as:92 | corasy: as armasy | WEIGHT | corasy opener | R-OPEN |
| anarva/misc/commander.as:96 | leglab: as armlab | WEIGHT | leglab opener | R-OPEN |
| anarva/misc/commander.as:100 | legvp: as armvp | WEIGHT | legvp opener | R-OPEN |
| anarva/misc/commander.as:103 | legalab: as coralab | WEIGHT | legalab opener | R-OPEN |
| anarva/misc/commander.as:106 | legavp: as coravp | WEIGHT | legavp opener | R-OPEN |
| anarva/misc/commander.as:109 | leggant: R,ASS,ARTY2 | WEIGHT | leggant opener | R-OPEN |
| anarva/misc/commander.as:112 | legsy: B, **SCOUT x15**, B | WEIGHT (extreme) | 15 naval scouts in a row | R-OPEN; scout value saturates once the enemy is located (marginal info value tends to 0) |
| anarva/misc/commander.as:115 | legadvshipyard: B2, **RIOT x10**, B2 | WEIGHT (extreme) | 10 riot ships in a row | R-OPEN (counter value against the scouted fleet) |
| anarva/misc/commander.as:117 | default: B, R3, B, R | WEIGHT | Opener for any factory not listed (air plants, hover, amph) | R-OPEN |

### commander.as openers (FG path, `GetOpenInfoFG`, used only when `F_OPENER=false`; inherited verbatim from BARb hard)

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| anarva/misc/commander.as:126-130 | armlab 3 queues (incl. RAIDER x5, BUILDER x3, SUPPORT) | WEIGHT | armlab FG opener | R-OPEN |
| anarva/misc/commander.as:134-137 | armvp 3 queues (SCOUT x2, RAIDER x3) | WEIGHT | armvp FG opener | R-OPEN |
| anarva/misc/commander.as:140 | armalab | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:143-144 | armavp 2 queues | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:147 | armshltx | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:150 | armsy | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:153 | armasy | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:156-158 | corlab 3 queues (RAIDER x4) | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:162-168 | corvp 3 queues (RAIDER x5) + commented 0.2 queue | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:171 | coralab | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:174 | coravp | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:177 | corgant | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:180 | corsy | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:183 | corasy | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:186-188 | leglab 3 queues | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:192-198 | legvp 3 queues | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:201 | legalab | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:204 | legavp | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:207 | leggant | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:210 | legsy SCOUT x15 | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:213 | legadvshipyard RIOT x10 | WEIGHT | FG | R-OPEN |
| anarva/misc/commander.as:215 | default B,R3,B,R | WEIGHT | FG | R-OPEN |

### common.as / define.as / task.as

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| common.as:14 (used at :203) | `WALL_THREAT_KERNEL = 0.01f` | WEIGHT | Threat-map weight of walls (walls are not ignored but are near-zero threat) | Walls have 0 dps by fact, so their threat is 0. Their real cost is path blocking: the detour length x our army's value-rate. Feed that to the pathing or targeting cost, not the threat kernel. |
| common.as:128 | `def.SetFireState(3)` + `ANTI_STAT` for all static defs in the listed roles | THRESHOLD (blanket policy) | Every static turret fires at everything, including walls and features | Per unit: attack a wall or static only when value of the target (path unblocked x army value-rate, or its cost if hostile) > shot opportunity cost (dps-seconds not spent on mobile threats in range). Default to the engine fire state otherwise. |
| common.as:159 | `def.SetFireState(3)` + `ANTI_STAT` for all mobile ground combat | THRESHOLD (blanket policy) | Every mobile combat unit shoots walls and neutrals | Same as :128. |
| common.as:187-203 | wall list `SetIgnore(false)` | THRESHOLD (policy) | Walls become targets (the list itself is a fact) | Target a wall only when it lies on our planned path and the path-cost delta x value-rate > time to kill it. |
| common.as:220-236 | 60-unit hand-picked "wall breaking" list, fire state 3 | THRESHOLD (hand-picked list) | Which units are set to break walls | Derive from facts: units whose weapon can damage the wall armor class (`walls` armordef) with time-to-kill under the detour time. |
| common.as:251-271 | 60 static defence names, fire state 3 + ANTI_STAT | THRESHOLD (hand-picked list) | Turrets targeting statics | Derive from defs (static and armed) and apply the :128 comparison. |
| define.as:4 (default in task.as:69, 88, 103, 119, 134, 161, 187, 211) | `ASSIGN_TIMEOUT = 5 * MINUTE` | THRESHOLD | Build/repair/reclaim/guard tasks are abandoned after 5 min | Timeout = expected completion (remaining cost / assigned BP) plus travel time. Abandon when remaining value / remaining time < the best alternative task's value per time. |

### tools/analyze_maps.py (generator of anarva/misc/mapfacts.as; the data itself is fact, these shape it)

| file:line | code (short) | kind | what it decides | live replacement |
|---|---|---|---|---|
| tools/analyze_maps.py:21 | `CELL = 4` (32-elmo cells) | WEIGHT (resolution) | Grain of choke widths in mapfacts (`m.choke` comes in multiples of 32) | Use the movement footprint fact (smallest movedef footprint x SQUARE). |
| tools/analyze_maps.py:168-169 | 5-sample moving median | WEIGHT | What counts as a choke (a narrow stretch, not a bump) | Window = path length an army needs to be stuck in, e.g. army frontage / speed fact; or keep the raw minimum. |
| tools/analyze_maps.py:177 | `(0.15, 0.5), (0.5, 0.85)` | THRESHOLD | Skips the outer 15 percent of the path as "base" when choosing our choke | Use a measured base extent (start-box edge, or distance to our farthest near-side mex). |
| tools/analyze_maps.py:192,198 | `R = 500 elmos` high-ground search radius | THRESHOLD | How far from the choke high ground is accepted (`hx/hz/gain`) | Use the weapon range of the defence that would sit there (for example the T1 LLT range fact). |
| tools/analyze_maps.py:161 | `k > 200` width probe cap | CADENCE/guard | Max width probe (6400 elmo) | Keep (loop guard). |
| tools/analyze_maps.py:231,244 | `starts[:16]`, `starts[:8]` | CADENCE/guard | How many starts are analysed | Keep or raise to all starts. |

## 3. FACT / CADENCE counts

**FACT (code): 13**
- define.as:1 `SECOND = 30`, :2 `60*SECOND`, :6 `SQUARE_SIZE = 8`
- factory.as:10 `T1..T4` bit flags (0x1, 0x2, 0x4, 0x8)
- task.as:7 `HIGH = 2`, `NOW = 99` (enum codes)
- mapfacts.as:466 version-strip char set; mapfacts.as:469 ASCII 65/90/32 (lower-casing)
- economy.as:35 comment `mmLevel 0.75` (doc only)
- analyze_maps.py:22-23 `MAX_SLOPE 0.41`, `MAX_WADE 22` (movedef facts)

**FACT (generated tables, all genuine unit and map facts):**
- facts.as: 38 converter rows x 5 values = 190 numbers, plus 7 extractor comment lines
- mapfacts.as: 231 map rows (basePath, straight, choke, mex, water, and per-start coordinates and gains), plus 218 alias rows

Nothing in `facts.as` or `mapfacts.as` is a tuning number. The only caveat is that `choke`, `cx/cz`, `hx/hz` and `gain` inherit the generator tunings listed above.

**CADENCE/LOG/guard: 9**
- define.as:10 `NEAR_ZERO = 1e-3`
- builder.as:62, :74, :75 `-1` null-id sentinels
- task.as:82 `pointId = -1`
- task.as:187 terraform `cost = 1.0f` placeholder
- mapfacts.as `-1.0` "not analysed" sentinels (one class, many rows)
- analyze_maps.py:161 `k > 200` probe cap
- analyze_maps.py:231/244 start caps

## Summary counts

| kind | rows |
|---|---|
| RANDOM | 12 (1 AiRandom, 1 AiDice, 8 dice-weight groups, 2 engine position-jitter defaults) |
| THRESHOLD | 30 |
| WEIGHT | 51 (45 opener build orders: 23 live, 22 FG; plus 6 formula and resolution weights: factory pow 0.9, factory x7, factory priority order, WALL_THREAT_KERNEL, analyze_maps CELL, 5-sample median) |
| FACT | 13 in code, plus generated tables (190 converter numbers, 231 + 218 map rows) |
| CADENCE/LOG/guard | 9 |

### JSON configs

# Anarva config audit: hand-picked numbers in `config/anarva/*.json`

Scope: `C:\Users\cyphernormie\bar\Anarva\stable\config\anarva\*.json` (14 files, about 5,400 lines), checked against how the core
(`ref/circuitai/src/circuit`, CircuitAI 1.6.29 plus `core/circuitai.patch`) parses them. The patch does not change config parsing.
Script context: `script/anarva/misc/brain.as` flags as installed: `F_PROD=false`, `F_SCALE=true`, `F_ENERGY=false`.
So the core's config-driven factory dice and energy curve **are live** in the shipped profile.

Kinds: **RANDOM** (dice or random draws), **THRESHOLD** (income, clock, count or size cutoffs), **WEIGHT** (coefficients), **FACT** (unit or game facts),
**SPACING** (fixed distances), **LABEL** (hand classification that drives logic).

Paths below are relative to `ref/circuitai/src/circuit/`.

---

## 0. Findings that matter regardless of the refactor

1. **`economy.energy.factor` has 4 points, but the core reads only 2.**
   - `CEconomyManager::ReadConfig` (EconomyManager.cpp L430-438) reads `factor[0]` and `factor[1]`.
   - So the factor is 6 at 1 s, ramps to 20 by 300 s, then **stays at 20 forever**. `[30,420]` and `[60,3600]` are silently ignored.
2. **Both `retreat.fighter` [0.50, 1.0] and `retreat.builder` [0.85, 1.0] are random draws, not "[default, modifier]" as the comment claims.**
   - The core draws `rand()` in [min, max] once per game and applies it to every def without a per-unit `retreat`.
   - See `CMilitaryManager` ctor, MilitaryManager.cpp L247-251, and `CBuilderManager::InitHandlers`, BuilderManager.cpp L265-268.
   - Element [2] would be the modifier; it is absent, so it defaults to 1.0.
3. **`eps_step` does nothing in 1vN.**
   - `ecoFactor = (allySize-1)*eps_step+1` (EconomyManager.cpp L410, L671) and the response `factor = (teamSize-1)*step+1` (MilitaryManager.cpp L333) are both 1.0 when Anarva is alone on its team.
   - Every `eps_step` in economy.json and response.json is dead for the 1v6 goal.
4. **`quota.anti_cap: 2.0` is a "probability" of 2.**
   - `IsAntiCap()` returns `antiCapProb > rand()/RAND_MAX` (SetupManager.h L84), so it is always true.
   - The value is a dice in form but a constant in effect.
5. **`commander.unit.*.importance` is dead.** The weighted commander dice is commented out (SetupManager.cpp L410ff), and the commander is chosen by side.
6. **Typos in `threat.vs` keys are silently ignored, so those modifiers never apply.**
   - `"raiders"` (3x), `"vy"` (2x) and `"anti-heavy"` (2x) appear in behaviour.json and behaviour_leg.json.
   - `CFactoryManager::ReadConfig` (FactoryManager.cpp L478-486) only looks up known role names.
   - Keys `"buildpeed"` and `"buildspeed"` in behaviour.json and behaviour_leg.json are also never read.
7. **`behaviour.*.build_speed` is not the unit's build power.**
   - The values are hand-scaled numbers that replace the real one (`SetBuildSpeed`, FactoryManager.cpp L516-519).
   - They are inconsistent: most use a /20 scale ("bp 100" = 5.0), but `armshltx`/`corgant` (real BP 600) are 1.0.
   - They feed `buildpower` (constructor count) and nano assist speed. They are WEIGHTS that only look like FACTS.
8. **The `economy.energy.<side>` efficiency column (index 4) overrides a score the core would compute from facts.**
   - Example: `armckfus` is set to 0.23, while the computed value noted in the file's own comment is 2.40.
   - The m-income and e-income columns override computed defaults the same way. See `InitEconomyScores` L539-558.
9. **`quota.aa_threat` is live in C++ and also hard-coded in script.**
   - `CEnemyManager::IsAirValid` (EnemyManager.h L91) uses the config value of 500.
   - `script/anarva/manager/military.as AiIsAirValid` hard-codes 80. Two different hand thresholds govern the same question.

---

## 1. Key families ranked by how much behaviour depends on them

### 1. `factory.json` / `factory_leg.json` → `factory.<fac>.{land,air,water}.tierN` + `income_tier` (HIGH)

- **Example values:**
  - armlab `income_tier [2,25,35,50,100]`.
  - `land.tier2 = [0.35 armck, 0.30 armpw, 0.30 armrectr, 0.15 armrock, 0.45 armham, ...]`.
  - Each factory has 3-6 tiers × 5-17 units × 3 surfaces. Roughly 1,500 numbers.
- **Kind:** RANDOM (the tier vectors are dice weights) plus THRESHOLD (`income_tier` is a metal-income cutoff).
- **What the core does:**
  - `CFactoryManager::GetFacTierProbs` (FactoryManager.cpp L1745) picks the tier with `min(avgM, avgE)*ecoFactor < income_tier[N]`.
    - The surface set is `air` if enemy air cost > our AA cost, else water or land by map type.
  - `RequiredFireDef` (L1608-1735) multiplies each weight by `RoleProbability` + `_weight_` and then rolls `rand()*magnitude` (L1723).
  - `GetFacRoleDef` (L1772-1820) rolls the same dice for **which constructor** to build.
  - `GetLastRequiredDef` repeats the last pick `num_batch` times.
- **Dependence:** HIGH.
  - With `F_PROD=false` this decides the whole army and constructor mix.
  - With `F_PROD=true` it still decides the first 6 minutes and every constructor-share decision (brain.as `Production::MakeTask`).
- **Live replacement:**
  - Use the deterministic chooser that already exists in `Brain::Production`.
    - Score each buildable unit (from `Facts::BuildOptions`) against the scouted enemy cost by domain (air, sub, surface, static, heavy).
    - Pick the largest gap between target share and metal-built share.
  - Replace tier gating with affordability: a unit is eligible when `costM / (income − committed pull) ≤ time until the threat it counters arrives`.
  - Use the enemy-army ETA from the threat map rather than an income ladder.
  - Delete the probability tables. Keep only the `unit` lists, which are build-option facts and could also come from UnitDefs.

### 2. `response.json` → `<role>.{vs, ratio, importance, max_percent, eps_step}`, `_weight_`, `_importance_mod_` (HIGH)

- **Example values:** `anti_air: vs [air], ratio 1.0, importance 100, max_percent 0.2`; `raider: ratio [2.0,1.0,0.1], importance [20,10,5]`; `_weight_ 0.1`.
- **Kind:** WEIGHT (`importance`, `_weight_`) plus THRESHOLD (`ratio`, `max_percent`). `eps_step` is inert in 1vN.
- **What the core does:**
  - `CMilitaryManager::RoleProbability` (MilitaryManager.cpp L1296-1310) returns `enemyMetal/(ourRoleCost+1)*importance`.
  - It applies only if `enemyMetal*ratio ≥ ourRoleCost*factor` and our role's share of the army stays `≤ max_percent`.
  - The result multiplies the factory dice weight in `RequiredFireDef`. `vs` lists, written by hand, decide which role counters which.
- **Dependence:** HIGH. It decides what counters get built and when. Together with family 1 it is the whole composition logic.
- **Live replacement:** use a counter matrix computed from weapon facts.
  - For each of our roles and each enemy role: our DPS against their armour class and target category, × hit chance (projectile speed vs target speed), × AoE vs footprint.
  - Divide by metal cost to get value-per-metal.
  - Required metal = `enemyMetal × (their effectiveness on us / ours on them)`, which is Lanchester.
  - Build the counter with the largest unmet requirement per metal. `max_percent` becomes "until the marginal counter is worth less than the marginal mainline unit".

### 3. `economy.json` → `buildpower` + `behaviour.*.build_speed` (HIGH)

- **Example values:** `buildpower 1.2` (anarva_b uses 1.4). `build_speed`: armck 4.0, armack 9.0, armcom 10, armlab 5, armshltx 1.0, nanotc 10.
- **Kind:** WEIGHT, with `build_speed` disguised as a FACT.
- **What the core does:**
  - `CFactoryManager::UpdateBuildPower` (FactoryManager.cpp L1038-1070) builds a constructor while `ΣbuildSpeed < min(avgM, avgE) × buildpower`.
  - When the factory is active it also flips a coin (`rand() ≥ RAND_MAX/2`, L1046).
  - The script's Director (`F_SCALE`, brain.as L2900-2951) multiplies the config's `buildpower` by a live scale but keeps it as the base.
- **Dependence:** HIGH. This sets the constructor-vs-army split and the economy growth rate.
- **Live replacement:** use the real `UnitDef.buildSpeed` (FACT).
  - Metal spent per second by build power B on a def is `B·costM/buildTime`, which is a fact.
  - Needed BP = `Σ over wanted builds (buildTime/costM) × income share`.
  - Add a constructor while `income − metalPull > 0` (unspent income) or while metal storage overflows.
  - Compare against the army deficit the Director already measures (`needPower` vs `ours`).
  - Drop the coin flip.

### 4. `economy.json` → `energy.{land,water}.<def>` table, `energy.factor`, `cost_ratio`, `min_income`, `em_ratio` (HIGH)

- **Example values:**
  - `armwin [30,60]`, `armsolar [12,14,0,0,0.030]`, `armfus [3,4,50,900,1.9]`, `armafus [50,100,70,4000,6.44]`.
  - `factor [[6,1],[20,300],(ignored)...]`, `cost_ratio 0.04`, `min_income 5`, `em_ratio 0.08`.
- **Kind:**
  - Columns [0..1] (count limit drawn as `min + rand()%(max-min+1)`): RANDOM.
  - Columns [2..3] (metal and energy income needed to unlock) and `cost_ratio`: THRESHOLD.
  - Column [4] (efficiency override): WEIGHT.
  - `factor`: THRESHOLD (a clock curve).
  - `em_ratio`: WEIGHT (an energy→metal exchange rate).
- **What the core does:**
  - `CEconomyManager::ReadConfig` (L446-463) draws the random limits.
  - `InitEconomyScores` (L527-563) uses the overrides instead of computed values.
  - `UpdateEnergyTasks` (L1283-1370) inflates income by `energyFactor`, walks defs best score first, and builds the first one whose income conditions pass and whose count < limit.
  - `em_ratio` also prices energy in factory and super conditions (L1528-1531, BuilderManager L1172, L1423).
- **Dependence:** HIGH. It decides every energy building (solar vs wind vs fusion timing) and, through `energyFactor`, the energy tier unlock.
- **Live replacement:** the anarva_e profile plus `Brain::Energy` (`F_ENERGY`) is already the template.
  - Build energy when `projected E pull (queue + converters + cloak) − E income > 0`.
  - Choose the def that maximises `E/s gained ÷ (costM + costE·p_E + buildTime × BP opportunity)`.
  - `p_E` is the live metal value of energy: the converter fact `energyconv_efficiency`, or the measured shadow price.
  - Use the def's own `make` (wind uses the map's min/max wind, tidal uses tidal strength). Those are FACTS.
  - Unlock a tier when its payback time at current income is shorter than the cheaper tier's.
  - `min_income` becomes "make > 0 on this map".

### 5. `behaviour*.json` → per-unit `threat{air,surf,water,default,vs{}}` and `power`; `behaviour.json quota.thr_mod` (HIGH)

- **Example values:**
  - `armcom threat {air 0.3, surf 1.0, water 0.1, vs {artillery 0.5, assault 0.8}}, power 0.8`.
  - `armvader power 10`. Jammers have power 0.01.
  - `thr_mod.attack [0.85,1.05]`, `defence [0.3,0.5]`, `mobile 1.0`, `static 1.0`, `comm 0.003`.
- **Kind:** WEIGHT. The `thr_mod.attack` and `defence` pairs are **RANDOM**: `CMilitaryManager::Enqueue` (L610-650) draws `rand()` in [min, max] for every new scout, raid, attack, bomb, AA, AH or defend task.
- **What the core does:**
  - `CFactoryManager::ReadConfig` L460-488 multiplies the def's computed DPS×HP threat and power.
  - `CMilitaryManager` ctor L253-266 multiplies commander threat and power by `comm`.
  - The results feed the threat map, influence map, target selection and every "can we win here" test.
- **Dependence:** HIGH. Every engage, retreat or path-safety decision reads these.
- **Live replacement:**
  - The core already computes air, surface and water threat from weapon target categories, so the 0.0 entries restate FACTS and can go.
  - Corrections for accuracy, AoE or paralyzer damage should come from weapon facts: hit probability from projectile speed, turn rate and target speed; AoE × expected target density; paralyze damage as time disabled × target DPS.
  - Calibrate the remainder online from measured exchange: damage dealt vs received per def pair (`Brain::Assess` already tracks trade).
  - `thr_mod` becomes 1/measured trade ratio instead of a dice range.

### 6. `behaviour.json` → `quota.{scout, raid, attack, num_batch}` (HIGH/MEDIUM)

- **Example values:** `scout 2`, `raid [6,150]`, `attack 60`, `num_batch 3`.
- **Kind:** THRESHOLD.
- **What the core does:**
  - `CMilitaryManager::DefaultMakeTask` (L1675-1750) limits scout tasks to `scout`.
  - Raid squads gather to `raid.min` and `raid.avg` power.
  - Attack groups need `max(attack, enemy pre-max group threat)`.
  - `GetLastRequiredDef` repeats a pick `num_batch` times.
- **Dependence:** HIGH for attack timing, MEDIUM for raid and scout.
- **Live replacement:**
  - Attack when our gathered power ÷ the target's defending power (target threat plus what can reinforce before we arrive) > 1/trade.
  - Raid size = smallest group that beats the strongest defender reachable before the raid leaves.
  - Scout count = how many points have vision value above a scout's cost (`F_SCOUTMAP` logic).
  - Batch size = until the role deficit is filled.
  - `F_QUOTA` already starts down this path.

### 7. `behaviour.json` → `retreat.{builder,fighter,shield}` + per-unit `retreat` (MEDIUM/HIGH)

- **Example values:** builder `[0.85,1.0]`, fighter `[0.50,1.0]`, shield `[0.25,0.275]`. Per-unit values: armcom 0.6, armbanth 0.3, armvader 0, cormort 0.85.
- **Kind:** RANDOM (the global pairs) plus THRESHOLD (per-unit HP fractions).
- **What the core does:** see finding 0.2. A unit retreats to repair when HP < retreat × maxHP. Shield units use the empty/full shield fractions (SetupManager.cpp L339-341).
- **Dependence:** MEDIUM-HIGH. It sets how long units fight and how much repair traffic there is.
- **Live replacement:**
  - Retreat when the expected value of staying is lower than the value of leaving.
    - Staying: DPS × time-to-death under local threat. Time-to-death = HP / incoming DPS.
    - Leaving: unit value × P(survive the trip home), where trip = distance to repair ÷ speed vs time-to-death.
  - Shield: drop when the remaining shield < incoming DPS × time to break contact.

### 8. `behaviour*.json` → per-unit `limit`, `since`, `cooldown` (MEDIUM/HIGH)

- **Example values:**
  - `limit 1` on **every factory**. `limit 3` on armguard and armamd. `limit 1` on silos and storage.
  - `since`: armllt 70 s, armrad 120 s, armaap 420 s.
  - `since` on T2 constructors armfark, corfast and armconsul is **1500 s**.
  - `cooldown 3` on fusions.
- **Kind:** THRESHOLD (count caps and clock gates).
- **What the core does:** `SetMaxThisUnit` / `SetSinceFrame` / `SetCooldown` (FactoryManager.cpp L429-442) and `CCircuitDef::IsAvailable(frame)`. Every chooser skips unavailable defs.
- **Dependence:** MEDIUM-HIGH.
  - The factory cap of 1 forbids a second identical lab even when income cannot be spent.
  - The 25-minute gate on T2 support constructors and the clock gates on radar and LLT are pure timers.
- **Live replacement:**
  - A count cap becomes "build another while its marginal value > cost".
    - For a second factory: unspent income ≥ the factory's spend rate (BP·costM/buildTime of its mix).
    - For anti-nuke: enemy nuke count. For radar: uncovered area value.
  - A `since` gate becomes the event it stands for: enemy air seen, enemy reached radar range, T2 income can sustain it.
  - Keep `limit` only where the game rules impose one; that is a FACT (`maxThisUnit` from the UnitDef, which the core already takes as the min).

### 9. `economy.json` → `ms_pull`, `production`, `goal_exec`, `build_mod` (global + per-unit), `mex_up`, `excess`; `factory.*.caretaker` (MEDIUM)

- **Example values:**
  - `ms_pull [[0.57,0],[0.66,0.34]]`; `production [0.8,0.8,1.0,0.8]`; `goal_exec 50`; `build_mod 1000`.
  - Per-unit `build_mod`: armfus 2000, armafus 4000, armmex 300.
  - `mex_up 4`; `excess -1`.
  - `caretaker`: armlab 8, armalab 12, armshltx 30.
- **Kind:** THRESHOLD and WEIGHT.
- **What the core does:**
  - `ms_pull`: mobile-to-static metal pull ratio interpolated over the mex share (`UpdateEconomy` L2098-2108). It gates new builder tasks against factory tasks (`MakeBuilderTask` L1298, `CreateFactoryTask` L1482).
  - `production`: income multipliers for building a new factory or nano (`UpdateFactoryTasks` L1523-1531, L1981-1992).
  - `goal_exec` and `build_mod`: builders are assigned until `cost < BP × build_mod/income` (BuilderTask.cpp L114, EnergyTask.cpp L49, MexTask.cpp L58, RepairTask.cpp L49). They also cap geo cost (L1450).
  - `mex_up`: concurrent mex upgrades, and only when income > 10 (L1067).
  - `caretaker`: nano cap per factory (`EnableFactory` L1305).
- **Dependence:** MEDIUM. Together they set how many builders crowd one job and the eco/army spend split.
- **Live replacement:**
  - `ms_pull` becomes the Director's comparison: marginal payback of eco metal vs the army deficit.
  - `production` and `caretaker`: add a factory or nano while unspent income ≥ its spend rate (BP·costM/buildTime of the queue). Nano count is also bounded by how many nanos fit within build range of the factory (geometry FACT).
  - `goal_exec` and `build_mod`: send another builder while `travel time < remaining build time` and the structure's value-rate × time saved > the builder's alternative job value.
  - `mex_up`: upgrade while upgrade payback < horizon and BP is free (`F_MOHO` already does this).

### 10. `build_chain.json` / `_leg` → `porcupine.{land,water,amount,base,prevent,superweapon}` (MEDIUM)

- **Example values:**
  - `land [0,3,5,6,4,8,10,12]` (indices into the unit list = build order).
  - `amount.factor [48,32]`, `amount.offset [-2,2]`, `amount.map [10,20]`.
  - `base [[3,420],[2,520],...,[22,1800]]` (def index, second).
  - `prevent 1`; `superweapon.weight [0.5,0.1]`, `condition [40,600]`.
- **Kind:**
  - `amount.offset`: RANDOM (`rand()` once per game, MilitaryManager.cpp L382).
  - `amount.factor` and `map`: THRESHOLD (maxCost = factor × income).
  - `base`: THRESHOLD (clock).
  - `land`/`water` order: LABEL (hand priority).
  - `superweapon.weight`: RANDOM (`DiceBigGun` L1338-1365).
  - `superweapon.condition`: THRESHOLD (`CreateBuilderTask` L1423-1425).
- **What the core does:** `CMilitaryManager::DefaultMakeDefence` (L717-845) builds up to `amountFactor×income` metal of porc per cluster, from the ordered list. Base defences fire at fixed seconds.
- **Dependence:** MEDIUM.
  - The script gates this (`AiMakeDefence`: frame > 5 min or income > 10 or mobile threat > 0, which are also script constants).
  - `F_HOLD` and `F_TERRAIN` add live defence on top.
- **Live replacement:**
  - Defend a cluster while `expected loss = cluster income × time-to-rebuild × P(raided)` exceeds the turret cost, with P from the threat map along enemy paths.
  - Pick the turret that maximises the threat it removes per metal against the enemy roles seen (same matrix as family 2).
  - Base defence is triggered by enemy ETA, not by the clock.
  - Superweapon: choose by expected damage per metal on known enemy structures.

### 11. `build_chain.json` → `build_chain.<cat>.<def>.hub[].{condition.chance, offset, priority}` (MEDIUM)

- **Example values:**
  - armadvsol → armbeamer `chance 0.25`. armfus → armsilo `chance 0.2`.
  - armrad → armanni `chance 0.5`, armbrtha `chance 0.3`.
  - corfrad has many `chance 1.0`. Offsets `{front:80}`, `[-200,50]`.
  - Priorities `now/high/normal/low`.
- **Kind:**
  - `chance`: RANDOM (`rand() < value*RAND_MAX`, BuilderTask.cpp L831).
  - Offsets: SPACING.
  - Chain contents and priorities: LABEL.
  - `air: true` is already live: turret cost < enemy air cost (L782).
  - `energy` and `wind` conditions are live state tests.
- **What the core does:** when a structure finishes, it enqueues the follow-up builds in the chain.
- **Dependence:** MEDIUM.
  - Radar chains place fortress clusters (armanni, armbrtha).
  - Factory chains put an LLT behind every T1 lab at priority `now`.
  - corsy chains queue fusions and four converters.
- **Live replacement:**
  - Replace `chance` with the same porc value test as family 10, at that position.
  - Replace the fixed follow-ups with: protect this new asset if its value × P(attacked) > guard cost.
  - Offsets come from the footprint (FACT) plus the enemy direction, which the core already uses.

### 12. `commander*.json` → `hide.{time, threat, air, task_rad}`, `assist_fac` (MEDIUM)

- **Example values:** `time 180`, `threat 5`, `air true`, `task_rad [2000,1200]`, `assist_fac 3`. anarva_b and anarva_fg use 420 / 8 / 800.
- **Kind:** THRESHOLD (clock, threat level, count) plus SPACING (radii).
- **What the core does:**
  - `CSetupManager::ReadConfig` L382-400. The commander hides after `time` when threat > `threat` or the enemy has air.
  - Its task search radius is `peace`/`danger`.
  - It assists the factory until there are `assist_fac` constructors.
- **Dependence:** MEDIUM (commander survival). `F_COMMGUARD` overrides part of this live.
- **Live replacement:**
  - Hide when an enemy force that out-DPSes the commander's HP can reach it before it reaches cover. Compare time-to-reach for both sides (`F_COMMGUARD`/`F_COMMRISK` logic).
  - Task radius = distance the commander can travel and return before the nearest threat arrives.
  - `assist_fac` = assist while factory BP is the binding constraint, i.e. the marginal value of assist exceeds the commander's next build job.

### 13. `behaviour.json` → `defence.{base_rad, comm_rad, escort, infl_rad}` (MEDIUM)

- **Example values:** `base_rad [800,1400]` (clamp of map diagonal × 0.3), `comm_rad [800,400]`, `escort [3,1,540]`, `infl_rad 5`.
- **Kind:** SPACING plus THRESHOLD (escort count and clock).
- **What the core does:**
  - `CDefenceData::ReadConfig` L40-58 and InfluenceMap.cpp L84.
  - Base radius decides when units defend the base. The comm radius decides whether the commander engages.
  - Escort: the first 3 builders get 1 guard each, and until 540 s mex and reclaim tasks are allowed only for escorted builders (MexTask.cpp L76, ReclaimTask.cpp L78).
- **Dependence:** MEDIUM.
- **Live replacement:**
  - Base radius = hull of our structures + the longest enemy weapon range seen.
  - Comm radius = distance at which the commander wins the trade, from DPS/HP versus the intruder.
  - Escort = guard a builder while threat on its path × its value > the guard's opportunity cost (`F_HOLD`/`F_BUILDERSAFE` direction).

### 14. `factory.json` → `select.{offset, speed, map, air_map, no_air, min_land}` + `factory.*.importance` (MEDIUM)

- **Example values:**
  - `offset [-20,20]`, `speed [0,40]`, `map [8,24]`, `air_map 100`, `no_air 1`, `min_land 75`.
  - `importance`: armlab [1,0], armap [0.1,0], armshltx [0,3].
- **Kind:**
  - `offset`: RANDOM (`rand()` per candidate, FactoryData.cpp L102).
  - `speed`, `map`, `air_map`: WEIGHT and THRESHOLD.
  - `importance`: WEIGHT. `no_air`: THRESHOLD.
  - `min_land`: THRESHOLD; it also sets land/water for energy and tiers (TerrainManager.cpp L121).
- **What the core does:**
  - `CFactoryData::GetFactoryToBuild` L40-145 scores `offset + importance×(largest-area % + speed %)` and sorts.
  - It refuses air for the first `no_air` picks.
  - `importance` ≤ 0 also marks a factory as T1 (`isT1` hack, FactoryManager.cpp L553-556).
  - The script's `AiIsSwitchTime` and `Tech` gates override when to switch.
- **Dependence:** MEDIUM. It decides the opening factory.
- **Live replacement:**
  - Opening lab = the one whose builder reaches the most metal-spot income per minute: reachable spots × speed on this map's movetype areas, which are FACTS from the terrain manager.
  - Later labs come from the payback-based tech gate (`F_TECH`).
  - Water/land comes from whether the spots and enemy are reachable by each movetype, not from a 75 % land cutoff.

### 15. `behaviour.json` → `quota.aa_threat`, `adaptive_threat_range`, `quota.slack_mod` (MEDIUM/LOW)

- **Example values:**
  - `aa_threat [[8,500],[24,500]]`.
  - `adaptive_threat_range` start 90, end 350, scale 0.5.
  - `slack_mod all 0.5, static 1.0, speed [0.75,4]`.
- **Kind:** THRESHOLD plus WEIGHT/SPACING.
- **What the core does:**
  - `CEnemyManager::ReadConfig` L456-464: air factories are invalid above that AA threat.
  - `GetRangeUnitCountCompensatorScale` L1659-1672 shrinks threat ranges as enemy count grows.
  - `CThreatMap::ReadConfig` L63-70 pads threat ranges by 64-elmo cells.
- **Dependence:** MEDIUM for air choice; LOW-MEDIUM otherwise.
- **Live replacement:**
  - Air is viable when the expected life of an air unit under enemy AA (AA DPS along its path vs its HP) × its damage > its cost.
  - Threat range = weapon range + target speed × reaction time (FACT-derived), with no enemy-count fudge.

### 16. `behaviour*.json` → per-unit `role`, `attribute` (MEDIUM, LABEL)

- **Example values:** about 300 + 190 role arrays such as `["anti_air","air"]` or `["assault","heavy"]`; attributes `siege`, `support`, `melee`, `rare`, `solo`.
- **Kind:** LABEL. These are not numbers, but they are hand judgements that route units into task types and the response system.
- **What the core does:** `CFactoryManager::ReadConfig` L352-405 sets main role, enemy roles and attributes. They drive which fight task a unit joins and which response bucket it fills.
- **Dependence:** MEDIUM.
- **Live replacement:** derive roles from weapon facts.
  - AA = can only target air. Artillery = range > enemy LOS and ballistic. Riot = AoE / reload profile. Raider = speed above the army median. Heavy = HP/cost top quantile, etc.
  - Quantile cuts are relative comparisons, not constants.

### 17. `economy.json` → `cluster_range`, `mex_max`, `build_delay`, `excess`; `build_chain porcupine.point_range` (LOW)

- **Example values:** `cluster_range 1500`, `mex_max [1.0,false]` (no cap), `build_delay -1` (off), `excess -1`, `point_range 600`.
- **Kind:** SPACING / THRESHOLD (mostly disabled).
- **What the core does:**
  - `cluster_range` is the max distance in mex clustering (MetalManager.cpp L214); it defines "cluster" for porc and expansion.
  - `mex_max` and `build_delay` are inert at these values.
  - `excess -1` makes `metalMod = 2` in `metalProduced` bookkeeping.
- **Dependence:** LOW (`cluster_range` is LOW-MEDIUM).
- **Live replacement:** cluster by builder travel time: spots one constructor can chain without leaving turret cover, i.e. the max defended range. Delete the inert keys.

### 18. `block_map.json` → `class_land.*.{yard, offset, size, radius, ignore/not_ignore}` (LOW, SPACING)

- **Example values:** `fac_land_t1 yard [8,30] offset [0,5] size [8,8]`; `solar yard [6,6]`; `fusion yard [5,5]`; `def_low radius 6`; `_default_ yard [4,4]`.
- **Kind:** SPACING (fixed distances in 16-elmo units). `ignore` lists are LABEL.
- **What the core does:** `CTerrainManager` (TerrainManager.cpp L118-215) builds blocker shapes used by `FindBuildSite`.
- **Dependence:** LOW for decisions, MEDIUM for base layout and pathing; e.g. the factory exit lane of 30 yards is why labs get space.
- **Live replacement:**
  - Factory yard = footprint of the largest unit the factory builds + its turn radius (FACTS).
  - Energy and fusion spacing = the structure's **death-explosion AoE**. The core already supports `"radius": "explosion"`, which reads it from the UnitDef; use it instead of 5/6 yards wherever chain loss matters.
  - Defence radius = the turret's own footprint + min spacing so one artillery AoE (enemy max seen) cannot hit two.

### 19. `behaviour*.json` → per-unit `midposoffset`, `on`, `ignore`, `slow_target` (LOW)

- **Example values:** `corlab midposoffset [-3.24,0,-2]`; `armguard on false`; `armdrag ignore true`.
- **Kind:**
  - `midposoffset`: FACT (a model geometry correction).
  - `ignore` on walls: roughly a FACT (not a combat unit).
  - `on false` on long-range plasma: a behaviour flag; it saves energy until needed.
- **Dependence:** LOW.
- **Live replacement:**
  - `on` should become "turn on when an enemy is inside range or energy is in surplus".
  - The others can stay as facts.

### Dead or inert (remove; zero behaviour)

- `economy.eps_step` and every `response.*.eps_step` in 1vN.
- `energy.factor` entries 3 and 4.
- `commander.*.importance`, `upgrade.module []`.
- `mex_max`, `build_delay`.
- `warn_probability`.
- The `threat.vs` typo keys (`raiders`, `vy`, `anti-heavy`) and the `buildpeed`/`buildspeed` keys.
- `anti_cap` is effectively boolean true.

---

## 2. What must remain (genuine facts or pure catalogue)

- **Def-name catalogues** are game facts that could also be read from UnitDefs: `economy.{mex,geo,assist,default}`, `porcupine.unit` / `default`, `superweapon.unit`, `factory.*.unit`, `block_map.instance`.
- `midposoffset`, `on`/`ignore` flags for walls, and `require_energy` (boolean).
- `limit` only where it mirrors the game's own `maxThisUnit`.
- `block_map` shape **types** (rectangle/circle) and the struct-type taxonomy. Distances should come from footprint and explosion facts.
- **Numeric guards, not tuning knobs:** e.g. `DIV0_SLACK`. Those live in C++, not in the configs.

## 3. Verdict

The decision content of the configs can be made number-free. All RANDOM keys and nearly all THRESHOLD and WEIGHT keys have a measured replacement. Several replacements already exist behind script flags (`F_PROD`, `F_ENERGY`/anarva_e, `F_SCALE`, `F_MOHO`, `F_COMMGUARD`, `F_HOLD`, `F_QUOTA`).

What must stay are facts and catalogues: unit-name lists per side, model offsets, booleans, and the blocker taxonomy. `build_speed`, the `threat`/`power` mods and the energy efficiency column only look like facts: they are hand weights and should be replaced by real UnitDef values.

### C++ core

# Anarva core audit: random numbers and hand-picked constants in decisions

Scope: `ref/circuitai/src/circuit` at `anarva129` (BARb f4a6ca3 + Anarva patch). Read-only audit, 2026-11-24.
Kinds: **RANDOM** (rand/dice/shuffle), **THRESHOLD** (fixed cutoff in an if), **WEIGHT** (fixed multiplier/exponent in a score or power comparison), **TIMEOUT** (fixed time that commits/abandons a unit or task).
Override column: **CFG** = Anarva config JSON can change the number today (still a constant, but random part can be neutralised); **SCRIPT** = AngelScript API can set/preempt it today; **C++** = needs a core change behind a new `anarva::switches` flag (util/AnarvaSwitches.h, off by default).
Freq: how often the decision fires and how much it moves outcomes (H/M/L).

Excluded as instructed: engine facts (FRAMES_PER_SEC, SQUARE_SIZE, 0.7071 = 1/sqrt2, cannon `smooth=100` engine constant), numeric guards (DIV0_SLACK, 1e-3 velocity epsilons), container sizes, debug-draw scales, terraform command params.

## A. Anarva's own patch (git diff f4a6ca3..anarva129)

The patch is mostly clean: ToFiringSpot ranks spots by trip length, GetRangeAt reproduces the engine's ballistic/sphere range rule from weapon facts, scout targets come ranked from the script, and engageSeen uses the leader's own LOS. Remaining items:

| # | Kind | file:line | code | decides | freq | live replacement | override today |
|---|---|---|---|---|---|---|---|
| A1 | THRESHOLD | task/fighter/ArtilleryTask.cpp:334 (new ToFiringSpot) | `if (threatMap->GetThreatAt(c) > THREAT_MIN) continue;` | firing spot counts as "safe" only below THREAT_MIN = 1.0 (Defines.h:55) | H when switch highGroundArty on | Compare the expected damage at the spot with what the unit can take there: threat-at-spot (DPS-like) × (reload time + time until it can leave the spot), measured against the unit's current HP. Take the spot if the unit lives through its volley and the volley is worth more than the expected loss: target value × P(kill) > unit cost × damage taken / max HP. | C++ (inside switch highGroundArty) |
| A2 | THRESHOLD | task/fighter/ArtilleryTask.cpp:174 (unchanged, now on the Anarva path) and :359 | `isPosSafe = GetThreatAt(pos) <= THREAT_MIN` / `GetThreatAt(posPath.back()) > THREAT_MIN` | arty retreats/falls back vs. holds | H for arty | Same as A1: time-to-die at that position vs. time to finish the shot | C++ |
| A3 | WEIGHT | task/fighter/SquadTask.cpp:462-484 (heightSquads) | scales BARb's `range0/range` standoff; the base standoff still uses `RANGE_MOD 0.8` / `3.0f*(radius+aoe)` spread (see B16) | where each squad member stands | M | Inherits B16. The height correction itself is exact (2 passes is a fixed-point iteration, not a decision) | C++ |
| A4 | TIMEOUT | task/fighter/SquadTask.cpp:484, CMilitaryManager::EnqueueDefendAt (MilitaryManager.cpp:668) | `frame + FRAMES_PER_SEC * 60`; hold task inherits `DEFAULT_SLACK*4` path range, `updCount % 16` execution | command expiry / re-path cadence | L | The order should expire when its premise changes (target died or moved more than the weapon's reach, threat changed), not after 60 s | C++ |
| A5 | WEIGHT | unit/CircuitDef.cpp:486-506 | longest land weapon wins `rangeModel` (`range > rangeModel.range`) | which weapon's ballistic rule GetRangeAt reports | L | Fine as a fact. For mixed-weapon units, report per-weapon reach and let callers ask for the DPS-weighted reach at a given height | none needed |

## B. Inherited core, ordered by impact

| # | Kind | file:line | code | decides | freq | live replacement | override today |
|---|---|---|---|---|---|---|---|
| 1 | WEIGHT | unit/CircuitDef.cpp:658-662, :33, Defines.h:57 | `pwrDmg = sqrtf(dps) * pow(dmg,0.25f) * THREAT_MOD(1/128)`; `power = pwrDmg * sqrtf(health + maxShield*SHIELD_MOD(1.5))` | every unit's power/threat: the input to every engage, retreat, merge, promote and porc comparison, and to the threat map | H (everything) | Lanchester-consistent strength from unit facts: kill rate = DPS vs. the target's armour class (the def's damage-type table), endurance = HP + shield (shield valued at its real regen and capacity, not ×1.5). Fight value = dps × hp. A group's strength is (Σ√(dps·hp))², not a sum of arbitrarily scaled roots. Drop THREAT_MOD so THREAT_MIN-type cutoffs lose their meaning and must be replaced too | SCRIPT partly: `SetThreatKernel(float)` per def; formula is C++ |
| 2 | RANDOM | module/FactoryManager.cpp:1720-1730 (RequiredFireDef) | `dice = rand()/RAND_MAX*magnitude; ... dice -= candy.weight` (and `rand() % candidates.size()` at :1720) | which combat unit a factory builds | H | Pick deterministically: argmax over candidates of (marginal value / cost), value = response to the measured enemy composition (RoleProbability already measures it) plus a deficit term: target share − current share of army cost (largest-remainder apportionment). No dice | SCRIPT: runs only when `Brain::Production::MakeTask` returns null, so fallbacks still roll the dice. C++ to remove |
| 3 | RANDOM | module/FactoryManager.cpp:1805-1815 (GetFacRoleDef) | `buildDef = candidates[rand() % size]` / weighted dice | which def is built for a role. Used by UpdateBuildPower (constructor choice) **and by script `aiFactoryMgr.GetRoleDef()` (opener queue in factory.as)** | H | Argmax of role-specific value per metal: constructor = buildpower/cost (adjusted for speed, since travel is part of build time); fighter = same as #2 | C++ (script can avoid GetRoleDef and pick the def itself) |
| 4 | RANDOM | module/FactoryManager.cpp:1046-1048 (UpdateBuildPower) | `r = rand(); ... || (isActive && (r >= RAND_MAX/2))` | 50% coin flip whether an active factory makes a constructor at all; also `BP >= metalIncome * bpRatio` cutoff | H (each idle factory cycle) | Constructor vs. army: compare marginal value. Constructor if unspent income (metal stored/overflowing, measured build-power-limited pull < income) × constructor lifetime > army value of the same metal (shadow price from the force ratio). bpRatio becomes the measured ratio pull/income | SCRIPT: `buildpowerRatio` writable; script preempts via MakeTask. Coin flip is C++ |
| 5 | THRESHOLD+RANDOM | module/MilitaryManager.cpp:249-252,285; module/FactoryManager.cpp:446-452; task/fighter/FighterTask.cpp:118,125 | fighter `retreat = rand in [0.5,0.55]` (behaviour.json `retreat.fighter`), per-def `retreat` 0.4-0.6, `if (healthPerc > cdef->GetRetreat())` stay | when a damaged fighter leaves the fight | H | Retreat when value saved > value still to be gained: remaining HP fraction × unit cost (what a repair saves) vs. expected damage it can still deal before dying = own DPS × time-to-death, where time-to-death = HP / incoming DPS (threat at pos). Also require that a repair/safe point is reachable before death (distance/speed < time-to-death) | CFG: set min=max to drop the dice and set per-def values; the cutoff stays. C++ for live |
| 6 | THRESHOLD+RANDOM | module/BuilderManager.cpp:265-268,297; task/builder/BuilderTask.cpp:331 | builder `retreat = rand in [0.8,0.89]` (behaviour.json `retreat.builder`) | when a damaged constructor (incl. commander) stops building and runs | H | Same as #5, but the value-to-gain term is buildpower × remaining build time of the current task; the commander's death value includes its death explosion on our own eco (deathAoe/deathDamage already read by Anarva) | CFG (min=max), C++ for live |
| 7 | WEIGHT | task/fighter/DefendTask.cpp:268 | `checkPower *= 4.0f - 3.0f / baseRange * dist  // 400% near base` | how much threat a defend squad accepts near base (up to 4×) | H | Accept the fight when expected trade × stake favours it: stake = metal value of our structures/units inside the enemy's reach from ePos, loss = our expected losses (Lanchester with #1). Fight if stake_saved > expected_loss | C++ |
| 8 | WEIGHT | task/fighter/RaidTask.cpp:296-299 | `checkPower *= 2.0f - 1.0f / baseRange * dist  // 200% near base`; `checkSpeed *= 2.f` | raid squads defending near base | H | Same as #7 | C++ |
| 9 | WEIGHT | module/MilitaryManager.cpp:618-649 | `powerMod`: defend `1/mod`, scout `0.75/mod`, raid `0.75/mod`, attack `0.8/mod`, bomb `2.0/mod`, AA `1.0/mod`, AH `2.0/mod`; `mod = rand()*len+min` | how much enemy threat each task type is willing to attack into (maxPower = attackPower × powerMod vs. threat) | H | Use the predicted fight outcome instead of a per-type margin: engage if our strength² − their strength² > 0 (Lanchester square law on #1 values), corrected by the measured trade efficiency so far (metal killed / metal lost, per role). Bomb/AH get their margin from damage per pass vs. AA threat on the path | CFG: `quota.thr_mod.attack/defence` = [1,1] already removes the random part; the 0.75/0.8/2.0 stay. C++ |
| 10 | THRESHOLD | task/fighter/AttackTask.cpp:264,267-270 | `isOverpowered = maxPower * 0.125f > group.influence`; `scale = min(distBE / sqOBDist, 1)` (**bug: distance divided by squared distance**); `GetInfluenceAt(group.pos) < INFL_SAFE(2.0)` | which enemy group the attack squad targets; skipping weak groups | H | Rank groups by value/time: (enemy group metal value × P(win)) / travel time; drop the 1/8 "overpowered" filter. Fix the unit mismatch (`distBE / sqrt(sqOBDist)`) | C++ |
| 11 | THRESHOLD | module/MilitaryManager.cpp:360,1436,1698,1715; task/fighter/DefendTask.cpp:108 | `minAttackers = quota.attack` (behaviour.json 60), `raid=[9,420]`; promote when `attackPower >= maxPower` with `maxPower = max(minAttackers, PreMaxGroupThreat)` | when a gathering group turns into an attack/raid group | H | Promote when the group beats the strongest enemy force that can reach its chosen target in time (threat along the path plus enemy groups within travel time), with no fixed floor. Raid size from enemy unescorted eco targets: the smallest group that kills a target before reinforcement arrives | SCRIPT: `quota.attack`, `quota.raid.min/avg` writable; script can create its own tasks. Concept is C++ |
| 12 | RANDOM+THRESHOLD | module/EconomyManager.cpp:455-459 | `cond.limit = min + rand() % (max-min+1)` from economy.json `energy.land/water` (e.g. armwin [10,20], armsolar [8,12], armfus [3,4]) | how many of each energy building may exist (count cap) | H | No cap. Build energy while the measured E deficit (pull − income, plus planned converter/factory upkeep) is positive; pick the type by payback = cost / (E per s), using measured wind average for wind and real tidal strength | CFG: min=max removes the random part; caps remain static. C++ |
| 13 | THRESHOLD | module/EconomyManager.cpp:431-433, 2061-2067 | economy.json `energy.factor [[1.0,300],[30.0,7200]]`: `energyFactor` ramps linearly with **game time** and multiplies metal income in UpdateEnergyTasks | how much energy the core thinks it needs | H | E target = measured E use: pull + converters at full capacity + upcoming factory/tech E cost rate. No clock | CFG (flatten to constant), C++ for live |
| 14 | THRESHOLD | module/FactoryManager.cpp:1735-1765 (GetFacTierProbs) + factory.json `income`/`tierN` | `if (metalIncome >= facDef.incomes[tier])` picks a hand-written probability row; `isAir = enemyAirCost > allyAACost` | factory's whole unit mix flips at fixed income steps | H | Replace tiers with live per-candidate value (#2): the counter value against the measured enemy mix plus cost-efficiency at the current income. Income limits only through build time vs. income | SCRIPT: `SetTierWeights` / `SetImportance`; the income ladder itself is C++ |
| 15 | WEIGHT | module/MilitaryManager.cpp:1296-1311; response.json | `prob = enemyMetal / (info.cost + 1.f) * vs.importance`; `enemyMetal * vs.ratio >= info.cost * info.factor`; `maxPerc` | response (counter-unit) production | H | Counter value = enemy metal of class X × measured kill efficiency of our role vs. X (damage-type tables, or kills/losses tracked in-game) ÷ our metal already countering it; no hand ratios | SCRIPT: `GetResponseInfo(role)` exposes maxPercent/factor/ratio/importance as writable; `responseWeight` |
| 16 | WEIGHT | task/fighter/FighterTask.cpp:16 (RANGE_MOD 0.8), :206; task/fighter/SquadTask.cpp:434-437 | standoff `min(minRange, LOS) * 0.8`; spread `maxDelta = PI*0.9/n`, `delta = 3.0*(radius+aoe)/range` | how far from the target units stand, and the formation arc | H (every attack order) | Standoff = own reach at that height (GetRangeAt) minus the target's closing distance during our reaction time (enemy speed × (our reload + turn time)); kite only when own reach > enemy reach. Spacing = enemy AoE radius (from its weapon def) + own footprint | C++ |
| 17 | THRESHOLD | task/fighter/FighterTask.cpp:133,147-148 | `healthPerc < 0.2f` → force retreat; `GetThreatAt(unit,pos) * 2 > GetUnitPower(unit)` → retreat instead of fighting on | damaged unit below retreat line: flee or keep shooting | H | Same as #5: time-to-death vs. time to kill current target. Keep shooting if the target dies first and is worth more than the expected HP lost | C++ |
| 18 | THRESHOLD | Defines.h:55 THREAT_MIN=1.0 at SquadTask.cpp:258,302; MilitaryManager.cpp:815 (`>THREAT_MIN*4`),1040,1072; BuilderManager.cpp:945,1347 | "no threat here" cutoff | regroup allowed, scout spot safe, porc trigger, builder-combat eligibility, build-site safety | H | Threat at a point vs. the specific unit: expected damage during the task (threat × dwell time) vs. its HP; for "is a fighter" use `isAttacker` | C++ |
| 19 | WEIGHT | map/ThreatMap.cpp:405,497-514,548; :619,644; :344-349; :585 | heat falloff `threat*(1 - 0.5*d/r)` (cloak 0.75); unknown enemy threat `0.1`; velocity lead `vel*1s` capped `DEFAULT_SLACK*2`; range `+DEFAULT_SLACK*2` | shape of the threat map that all safety checks read | H | Full threat inside weapon reach (GetRangeAt with the height difference), zero outside, plus a margin = enemy speed × our threat update interval. Unknown radar dots: expected threat from the scouted enemy mix (mean threat per enemy unit seen) | C++ |
| 20 | THRESHOLD | setup/DefenceData.cpp:44-47; behaviour.json `defence.base_rad [600,1200]` | `baseRange = clamp(diag*0.3, 600, 1200)` | what counts as "near base" for defend/raid weighting (#7/#8), comm defence, isDefender | H | Base = our structures' hull; "near" = enemy travel time to our nearest valuable structure < our defenders' travel time | CFG (min/max), C++ |
| 21 | WEIGHT | module/BuilderManager.cpp:1093-1104, 1237-1248, 1367-1379; Defines.h:51 | `weight = 1/(priority+1)^2`; repair valid if `(maxHP-hp)*0.6*speed > healthSpeed*distCost`; `-maxHealth*0.005`; `distCost < MAX_TRAVEL_SEC(60)*speed` | which build task a constructor takes | H | Value per second: task payback value / (travel time + build time at this builder's BP). Priority enum becomes the value; repair value = metal restored / time | C++ (script can make its own tasks/AssignTask) |
| 22 | WEIGHT | module/BuilderManager.cpp:1176-1180 | `ENERGY = baseDivEnemy*energyDivMetal*8`; `DEFENCE = ... baseDivEnemy*2`; RADAR/SONAR/MEX ratios | task weighting by position | H | Same as #21; position enters through travel time and threat, not through fixed ×8/×2 | C++ |
| 23 | RANDOM | unit/FactoryData.cpp:102; factory.json `select.offset [-20,20]` | `offset = rand()*lenOffset + minOffset; percents = offset + importance*(mapPercent+speedPercent)` | which factory to build first / switch to | H (game-deciding opener) | Factory value = reachable map share × value of its units vs. the expected enemy mix, divided by its cost and time to first unit. No offset | CFG: set `select.offset` to [0,0]. SCRIPT: AiGetFactoryToBuild can return its own pick |
| 24 | THRESHOLD | unit/FactoryData.cpp:89-90; factory.json `select.no_air`, `air_map 100`, `speed [0,40]`, `map [8,24]` | importance ×0.1 if no builder available; first `noAirNum` factories never air; map-size → speed% linear ramp | factory selection | M | Fold into the factory value in #23 (air: enemy AA measured; speed: map travel distances) | CFG, SCRIPT (AiGetFactoryToBuild) |
| 25 | RANDOM | setup/SetupManager.cpp:183,187-189,205 | cluster income jitter `+ rand()/RAND_MAX - 0.5`; `std::random_device` + `std::mt19937` shuffle (**not reproducible even with random_seed**); random spot `indices[rand()%n]` | start position when choosing it | M (only when the AI picks its start position) | Sort by count, then distance/income, deterministic tie-break by cluster id; spot = the one that minimises commander walk to the cluster's other spots | C++ |
| 26 | RANDOM | setup/SetupManager.cpp:238-241 | `normal * ((rand() < RAND_MAX/2) ? -1 : 1)`; `backPos = refPos - enemyDir*400`, `±normal*200`, `energyBase2 = backPos - enemyDir*400` | base layout: which side metal vs. energy base goes, distances | M | Side: the one with more buildable flat area / further from enemy approach paths; distances from building footprints + death-explosion radius of fusions (deathAoe) | C++ |
| 27 | RANDOM | setup/SetupManager.cpp:300 | `comms[rand() % comms.size()]` | commander def when no choice made | L | Deterministic best (already done when commChoice != null) | C++ |
| 28 | RANDOM | terrain/TerrainManager.cpp:770-773; used by AttackTask.cpp:39-41,230; RaidTask.cpp:38-40,238,417; AntiAirTask.cpp:36,210; AntiHeavyTask.cpp:37,257; BombTask.cpp:203; ScoutTask.cpp:306 | `x = rand() % width; z = rand() % height` | initial task position and fallback destination when no target found | M | Highest-value unseen location: the script's age × stake scout list (scoutMap), or the enemy's last-known/expected base and expansions | C++ (scoutMap switch covers scouts only) |
| 29 | RANDOM | module/MilitaryManager.cpp:376-388; build_chain.json `porcupine.amount.offset [-2,2]`, `factor [48,32]`, `map` | `offset = rand in [min,max]`; `amountFactor` = map-size ramp + offset | how many static defences per income | M | Defence value = stake protected (metal in range) × probability of raid (enemy raider metal / our mobile defence response time) vs. its cost | CFG: offset [0,0]; ramp stays. C++ |
| 30 | THRESHOLD | module/MilitaryManager.cpp:795-826, 871, 881 | `isPorc = stddev > 0.3*avg`; `income > (avg+max)*0.5`; `> SQUARE(1000.f)` from base; `GetBuilderThreatAt > THREAT_MIN*4`; `threatCount >= 2`; AA only if `enemyAirCost >= 1`; `range < 500` → slot 0 | whether a cluster gets defences and which slot | M | Same value comparison as #29 per cluster | C++ (SCRIPT: AiMakeDefence can skip/gate, currently uses its own constants) |
| 31 | RANDOM | task/builder/BuilderTask.cpp:831; build_chain.json `"condition": {"chance": 0.25/0.5}` | `isValid = rand() < bi.value * RAND_MAX` | whether a chained building (armpb, armamd, armbeamer...) is added after a build | M | Condition on value: e.g. anti-nuke when the enemy has a nuke silo or its metal income can afford one before our anti finishes; PB when threat at the site > 0 | CFG: remove `chance` conditions or replace with `air`/`energy` conditions |
| 32 | RANDOM | module/MilitaryManager.cpp:1339-1370 (DiceBigGun) | weighted dice over super weapons | which superweapon to build | L-M | Argmax of expected metal destroyed per metal cost (range covers enemy base? AoE × enemy structure density) | C++ |
| 33 | THRESHOLD | task/fighter/AttackTask.cpp:57,62 | `speedLeader * 1.5f < speedUnit` → no join; `> SQUARE(1000.f)` → no join | which units can join an attack squad | M | Join if the joiner reaches the squad before the squad reaches its target (distance/speed vs. squad ETA); speed mismatch costs the speed lost × time | C++ |
| 34 | THRESHOLD | task/fighter/SquadTask.cpp:278,311 | regroup radius `max(SQUARE_SIZE*8*n, highestRange)` | when the squad stops to regroup | M | Regroup when the spread makes the first arrivals fight alone: (arrival-time spread) × enemy DPS at target > acceptable loss computed from #1 | C++ |
| 35 | TIMEOUT | task/fighter/SquadTask.cpp:276-293 | `frame >= groupFrame + FRAMES_PER_SEC*60` → far units declared stuck, `circuit->Garbage(unit,"stuck")` | removes units from the AI after 60 s of regroup | M | Stuck = no path progress: measured distance-to-group not decreasing over the path's expected travel time (distance/speed) | C++ |
| 36 | THRESHOLD | Defines.h:51 MAX_TRAVEL_SEC=60 at SquadTask.cpp:182 (merge); BuilderManager.cpp:1106 | `sqMaxDistCost = SQUARE(60 * lowestSpeed)` | merge squads only within 60 s travel | M | Merge if combined power raises P(win) at the target by more than the delay costs (travel time × enemy eco growth / damage) | C++ |
| 37 | THRESHOLD | task/fighter/RaidTask.cpp:258-263,282; DefendTask.cpp:251; ScoutTask.cpp:184; MilitaryManager.cpp:1578 | raid ignores enemies faster than `0.8*highestSpeed`; target hysteresis `1/0.75`; search radius `max(range,LOS)+200`; `GetTasks().size() > 1` (raid) / `> 2` (defend, scout) | raid/defend target choice, max tasks per enemy | M | Chase if we reach it before it reaches safety (closing speed × distance to its nearest defence); tasks per enemy limited by overkill: sum of assigned DPS × time-to-reach ≥ enemy HP | C++ |
| 38 | THRESHOLD | task/fighter/DefendTask.cpp:234,296; AttackTask.cpp:251; RaidTask.cpp:260; ScoutTask.cpp:167; MilitaryManager.cpp:1565 | `weaponRange = GetMaxRange() * 0.9f`; skip if `ePos.y - elevation > weaponRange` | air/height target filter | L-M | `GetRangeAt(ePos.y - pos.y) > 0` (Anarva already has it) | C++ |
| 39 | THRESHOLD | task/fighter/SquadTask.cpp:349-350,403; FighterTask.cpp:197 | `aimLift = height*0.5`, `maxHeight = range*0.4`; direct-attack if `|dy| > range*0.5` | high-ground handling in squad attack | M | GetRangeAt with the real height difference; LOS check with actual aim heights | C++ |
| 40 | THRESHOLD | task/RetreatTask.cpp:174-175 | `isRepaired = healthPerc > 0.98f` (+ full shield, behaviour.json `retreat.shield`) | when a retreating unit rejoins | M | Rejoin when the marginal repair (repair rate × time) is worth less than the unit's fight value per second at the front | CFG (shield), C++ |
| 41 | THRESHOLD | task/RetreatTask.cpp:151,413 | haven range `GetAssistRange()*0.6 + square` | where retreaters wait | L | Inside nano assist range (fact) minus own radius | C++ |
| 42 | THRESHOLD | task/RetreatTask.cpp:244; BuilderManager.cpp:973 | `GetWorkerCount() <= 2` → builder skips retreat / commander not hidden | low-worker emergency | M | Retreat value (#6) already accounts for it when the shadow price of buildpower is measured | C++ |
| 43 | THRESHOLD | task/fighter/FighterTask.cpp:120,126 | heavy `healthPerc < 0.9f` → enqueue NOW repair | repair requests | L-M | Repair when repair metal/time < value of HP restored (cost × missing fraction) and a builder is within travel time | C++ |
| 44 | WEIGHT | module/BuilderManager.cpp:944 | `POWER_MOD = 1.5f` for builder combat | whether a constructor (commander) fights | M | #9 Lanchester outcome; commander additionally weighs its death explosion on own eco | C++ |
| 45 | THRESHOLD | task/builder/BuilderTask.cpp:452-457; RepairTask.cpp:85-87 | abort build if `cost.metal > 1000` and income `< savedIncome*0.6` and pull `> 2×income` | cancels big projects after eco loss | M | Abort if time-to-finish at current income exceeds the projected survival horizon, or a cheaper option has higher value/time | C++ |
| 46 | THRESHOLD | task/builder/BuilderTask.cpp:118; MexTask.cpp:63 | `IsEnoughEnergy(this, cdef, 0.8f)` | builder waits while E is short | M | Exact: projected E stock over the build time ≥ 0 (mod 1.0) | C++ |
| 47 | THRESHOLD | module/EconomyManager.cpp:1341,1367 | `defCounts < buildPower / cost * 4 + 1` | max concurrent energy tasks per type | M | Concurrency = BP available / BP needed to finish in the time the deficit must be fixed | C++ |
| 48 | THRESHOLD | module/EconomyManager.cpp:1304 | `energyIncome *= isEnergyStalling ? 0.5f : 1.f` | energy urgency | M | Use measured deficit (pull − income) directly | C++ |
| 49 | THRESHOLD | module/EconomyManager.cpp:1067; economy.json `mex_up` | MexUp only if `< numMexUp(2)` tasks and `AvgMetalIncome > 10` | T2 mex upgrades | M | Upgrade when payback (cost / extra metal per s) < survival horizon at that spot (threat) and beats army at the shadow price | CFG (mex_up), C++ |
| 50 | THRESHOLD | module/EconomyManager.cpp:1130-1131 | `mexTaskSize < mexMax` and `(income < 100 \|\| !IsMetalFull())` | when new mex tasks are created | M | Payback per mex (extract × time-to-live from threat) vs. cost + travel | C++ |
| 51 | THRESHOLD | module/EconomyManager.cpp:1171-1173; task/builder/ConvertTask.cpp:42 | converter if `CONVERT tasks < 2`; abort converter if `E < storage*0.55` | metal makers | M | Converter while E surplus × conversion rate > value of using that E elsewhere; abort when the projected surplus disappears | C++ (script Brain::Convert substitutes some) |
| 52 | THRESHOLD | module/EconomyManager.cpp:1204,1213,1248 | reclaim if `RECLAIM tasks < workers/2`; search radius `speed * (pull*0.8 > income ? 60 : 20)` s; value `< 1.0` skip | reclaim tasks | M | Reclaim value/time = metal / (travel + reclaim time) vs. builder's alternative task value | C++ |
| 53 | THRESHOLD | module/EconomyManager.cpp:1519 | start factory needs `costM / startBuildTime * 0.25f` metal income | first factory timing | M | Start when stored metal + income × build time ≥ cost (already the right shape, 0.25 is the constant) | C++ (SCRIPT AiGetFactoryToBuild) |
| 54 | THRESHOLD | module/FactoryManager.cpp:1480-1485 | `isStalling = metalEmpty && income*1.2 < pull && ...` | factory waits | M | Projected metal stock over the next unit's build time ≥ 0 | C++ |
| 55 | TIMEOUT | module/FactoryManager.cpp:1468,1485,1493,1561 | `Wait(FRAMES_PER_SEC*3 / *10)` | factory/assist idle time before reconsidering | M | Event-driven: re-evaluate on income/state change; or wait = time until the stock covers the next unit | C++ |
| 56 | THRESHOLD | module/FactoryManager.cpp:1628 | `frame < FRAMES_PER_SEC*60*10` → assume enemy in every area (comment: "TODO: Change to minimum required army power") | unit availability by map area in first 10 min | M | Area check from scouting info only; unknown area = expected enemy presence from map reachability | C++ |
| 57 | THRESHOLD | module/FactoryManager.cpp:1596-1603; factory.json batch | `++buildCount < numBatch` repeats last def | batches of same unit | L-M | Repeat while the def is still the argmax of #2 (no fixed count) | CFG |
| 58 | THRESHOLD | module/FactoryManager.cpp:330-333 product `[0.8,0.8,0.8,0.8]` | new-factory / factory resource modifiers | when another factory or nano is affordable | M | Measured fraction of income the factories actually consume | CFG |
| 59 | THRESHOLD | module/EconomyManager.cpp:1665-1668 | E storage only if `storage <= 5 * income`; M storage only if metal full | storage buildings | L | Storage when overflow lost per s × lifetime > cost | C++ |
| 60 | THRESHOLD | module/EconomyManager.cpp:1857,1865; :710 | morph if `income >= 10`, `pull*0.8 <= income`, health `>= 0.8`; cancel morph at health `< 0.5` | unit/commander morph | L | Morph when upgrade value per metal beats army at shadow price; cancel when time-to-death < remaining morph time | C++ |
| 61 | THRESHOLD | module/EconomyManager.cpp:1387,1392,1397 | energy base 2 if `cost >= 1000`; small energy near if `< 600` elmos; `radius + SQUARE_SIZE*6` | where energy goes | L-M | Place high-death-damage buildings (deathAoe/deathDamage) so their blast does not reach other eco; others near the builder | C++ |
| 62 | THRESHOLD | module/EconomyManager.cpp:1899 | airpad when air units `> ((airpads + factories + 1) * 3)^2` | airpads | L | Airpad when queued rearm time × air value > airpad cost | C++ |
| 63 | THRESHOLD | module/EconomyManager.cpp:409-410; economy.json `eps_step` | `ecoFactor = (allies-1)*step + 1` | scales income estimates and big-gun need (MilitaryManager.cpp:1316) | M | Use own measured income; ally income from team resources | CFG |
| 64 | THRESHOLD | unit/CircuitDef.cpp:235; used at unit/action/TravelAction.cpp:36 | `isTurnLarge = speed / turnRate > 0.09f // empirical magic number` → path waypoint increment ×2 | path following granularity | L-M | Turn radius = speed / (turnRate in rad/s) (Anarva already stores `turnRate` deg/s, `turnInPlace`); waypoint spacing ≥ turn radius | C++ |
| 65 | WEIGHT | unit/CircuitDef.cpp:371-403,415,435,516,266,555,610 | paralyzer dps ×0.1; slow/disarm ×0.5; capture ×2; impulse ×0.02; `extraDmg > 0.1`; isAirWeapon `range > 150`; gunship cannon range ×1.25 ("height hax"); drone `costM *= 0.1`; AoE `> 64` | threat values of special weapons; air range | L-M (most are ZK paths) | Gunship: GetRangeAt with flight altitude; drones: real cost; paralyze: time disabled × victim's DPS | C++ |
| 66 | THRESHOLD | map/InfluenceMap.h:27 INFL_SAFE=2.0 at AttackTask.cpp:270, RetreatTask.cpp:146 | "our influence high enough" | attack target filter; retreat end pos | M | Compare our influence to enemy influence at the point (ratio = predicted win) | C++ |
| 67 | THRESHOLD | task/fighter/DefendTask.cpp:160; AttackTask.cpp:181 | arrival slack `500/300` and `300/100` elmos | when a squad counts as arrived | L | Own weapon reach (arrived when the target area is in range) | C++ |
| 68 | THRESHOLD | task/fighter/BombTask.cpp:235,238,243,248 | `minRange > 300 → scale 4`; `speed/1.75`; search `2000`; `allyAoe ≤ DEFAULT_SLACK*2` | bomber targeting | L | Bomber value per run = metal under AoE × P(survive AA on path) | C++ |
| 69 | THRESHOLD | task/fighter/AntiHeavyTask.cpp:126,182,363; MilitaryManager.cpp:1723 | enemy heavy cost `< 1.f` → AH acts as attacker; `reload >= 5s` | anti-heavy usage | L | Use AH while enemy heavy metal × AH efficiency > alternative | C++ |
| 70 | THRESHOLD | task/RetreatTask.cpp:357 | uncloak if `cloakCost > 0.1 * E income` | cloak upkeep | L | Cloak while E surplus covers it and the value of being unseen > its E cost | C++ |
| 71 | THRESHOLD | task/builder/EnergyTask.cpp:60,106,111; GuardTask.cpp:106-107; MexTask.cpp:194,203,282,304; ReclaimTask.cpp:112,131 | comm moves small energy if `cost < 200` and `buildTime < 10 s`; guard `> 80`/`48`/`64`; mex block `> 2`, `range + 200`; enemy/feature scan `500` | small builder details | L | Distances from build distance and footprint facts; time cutoffs from travel vs. build time | C++ |
| 72 | RANDOM | setup/SetupManager.h:84 | `IsAntiCap = antiCapProb > rand()/RAND_MAX` (behaviour.json `anti_cap 2.0` → always true) | anti-capture action | L | Already deterministic with 2.0; make it a bool | CFG |
| 73 | RANDOM | resource/MetalManager.cpp:156 | `offset = rand()*50 - 25` on spot count | only when the game gives no `mex_count` (metal-map fallback) | L | Use spot detection only | C++ |
| 74 | THRESHOLD | module/EconomyManager.cpp:76-77 | initial income samples `1.0` / `2.0` | first 5 income samples | L | Seed with actual start income | C++ |
| 75 | TIMEOUT | many: `frame + FRAMES_PER_SEC*60` on Attack/Fight/Move/Build commands (DefendTask.cpp:96,201,414; RaidTask.cpp:127,172,183; ArtilleryTask.cpp:118,120; ScoutTask.cpp:335; BuilderTask.cpp:298,410...) ; cadences `updCount % 32/16/4/2` | command expiry and re-evaluation rhythm | L | Expire on premise change (see A4); cadences are scheduling, not decisions | C++ |

## C. Process-level note

- `CircuitAI.cpp:1716`: `seed = random_seed option ? value : time(nullptr)`, then `srand(seed)` (util/GameAttribute.cpp:28). Every RANDOM row above changes between otherwise identical games unless the AI option `random_seed` is set, so A/B batch results carry this noise. Row 25 also uses `std::random_device`, which ignores the seed. Until the RANDOM rows are removed, set a fixed `random_seed` for measurement.
- Script side (Anarva/stable/script, re-checked during this audit): no `AiRandom`/`AiDice` calls remain.

## Counts

| Kind | Patch (A) | Inherited (B) | Total |
|---|---|---|---|
| RANDOM (incl. RANDOM+THRESHOLD) | 0 | 16 (rows 2,3,4,5,6,12,23,25,26,27,28,29,31,32,72,73) | 16 |
| THRESHOLD | 2 | 45 | 47 |
| WEIGHT | 2 | 11 (rows 1,7,8,9,15,16,19,21,22,44,65) | 13 |
| TIMEOUT | 1 | 3 (rows 35,55,75) | 4 |
| Total | 5 | 75 | 80 |

(Mixed rows 5, 6, 12 are counted once under RANDOM. Of the RANDOM rows, the random part can be switched off from config today in 5, 6, 12, 23, 29, 31, 72 (and #9's thr_mod already is). The rest need C++.)

## Closed: owner ruling, 2026-11-25

"those hardcoded numbers have nothing to do with the ai decision making". The remaining digits stay: frame rate, pi/e/1/2 inside formulas, tier and flag identifiers, and numeric guards. They are facts or notation, not decisions (CLAUDE.md section 2). #71 and #42 are closed.
