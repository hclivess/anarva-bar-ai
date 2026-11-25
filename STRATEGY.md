# Anarvā — strategy and tactics: principles to mechanisms

Anarvā doesn't copy moves. It encodes the **reasoning** behind them. Each principle below is tied to
the code that implements it. Sources (public domain, kept locally under `ref/strategy/`): Sun Tzu, *The
Art of War* (Giles translation); Clausewitz, *On War*; Napoleon's *Military Maxims*.


> **Status (2026-11-25):** there are no feature flags any more; the `F_*` flags were folded into the code
> (commit 5e66eba). Each mechanism below says where it lives now: the script brain
> (`Anarva/stable/script/anarva/misc/brain.as`, namespaces such as `Brain::Director`, `Brain::Production`) or the
> C++ core patch (`core/circuitai.patch`, branch `anarva129`). Anything not in the code is marked planned or limit.
> Since the rework Anarvā has not yet won a full-length 1v1 against BARb hard; results quoted below from earlier
> builds are history (see the [README](README.md) status).

## 1. Know the enemy: scouting decides everything

> "If you know the enemy and know yourself, you need not fear the result of a hundred battles."
> — Sun Tzu III.18
>
> "…foreknowledge cannot be elicited from spirits…" — XIII.5 (it must come from scouts)

- **Army vs. scaling.** Each update `Brain::Director` compares our army with the enemy army we know of,
  summed per known enemy unit, at our trade rate (`ratio`). `Brain::EcoPos` sets the core's
  constructor-vs-army knob (`aiFactoryMgr.buildpowerRatio`) from it:
  - more constructors only while open extractor spots need claiming (claim walking time over the planning
    horizon, see §17) and we are not weaker (`ratio >= 1`)
  - weaker than what we know of → army first
  - **blind** → the enemy is assumed to be at least as strong as we are, or as strong as last seen
    (`Economist::EnemyThreat`), so not seeing the enemy never reads as being ahead
- Scouting is by the value of vision (`Brain::Scout`, §10): the scout quota is the number of dark cells
  worth more than a scout (at least 1). There is no fixed quota and no air-scout timer.
- **What we can't see** (`Brain::Intel`):
  - A seen jammer is treated as a hidden army, a phantom threat on its cluster.
  - Places where we keep dying get Dragon's Eyes (when the metal lost there beats a camera), because
    sight is the only thing a jammer can't stop.
  - Junos clear jammers and radar (`Brain::Strategic`, when the known jammer metal beats a Juno).

## 2. Measure strength, then choose the fight (Sun Tzu III.9-10)

> "If ten to the enemy's one, surround him; if five to one, attack him; if twice as numerous, divide
> our army into two. If equally matched, we can offer battle; if slightly inferior in numbers, we can
> avoid the enemy; if quite unequal in every way, we can flee from him."

An earlier build mapped our power ÷ the enemy's seen mobile threat onto named postures (below). Those ratio
bands were hand-picked and are gone from the code. The current `Brain::Director` keeps only the ratio
(ours ÷ needed) and the needed power: the attack quota is the needed power (§3), and `ratio < 1` ("can't win
an open fight") is what holds back constructors, shields, launchers and silos and starts terrain
fortification (§25). The table is kept as the reasoning the ratio stands for:

| ratio | posture (earlier build) | behaviour |
|------:|---------|-----------|
| ≥ 4 | ALLIN | small waves, constant pressure, close the game |
| ≥ 1.6 | PRESSURE | frequent waves; raiders split off to hit the weak points |
| ~1 | BALANCED | offer battle with a large wave |
| < 0.75 | HOLD | avoid open battle, fight under our own defences, strike only with a big wave |
| < 0.4 | TURTLE | everything into army; defend the base (planned: static defence at chokes) |

## 3. Concentration of force (Napoleon, Clausewitz)

> "The first and most important rule… to concentrate as much as possible." — Clausewitz

- **Wave control** (`Brain::Director` update). The core's attack quota is set to the needed power (known
  enemy army plus the army guessed under jammers, ÷ our trade rate), and the raid quota to the enemy
  raider threat ÷ our trade rate. A squad gathers until it reaches that and then launches together. This
  replaces the core's config floors and its habit of either never launching or trickling.
- **Broken-squad recall** (`Brain::Army::CheckSquads`). A squad that has bled and is now weaker than what
  we'd send fresh is pulled back to regroup. Feeding units in one by one is the opposite of concentration.

## 4. Avoid strength, strike weakness (Sun Tzu VI.30-31)

> "The way is to avoid what is strong and to strike at what is weak… Water shapes its course according
> to the nature of the ground." — VI.30-31
>
> "Attack him where he is unprepared." — I.24

- Raiding packs (`raid` quota) go after eco and builders. The core's threat map steers them away from
  defences. Scouts also look for unwatched enemy extractors to raid (`Brain::Scout`, #74).
- **A greedy enemy** (lots of buildings, little army) should be punished rather than out-boomed. The
  earlier build did this through the PRESSURE posture; the current code has no separate rule for it
  (planned).
- Attack target choice compares our wave with each enemy group's strength. The config `thr_mod` ranges
  are no longer read; the core's target choice is by value per distance and per health
  ([AUDIT.md](AUDIT.md)).

## 5. The culminating point (Clausewitz)

An attack loses strength as it advances; past its culminating point it should stop. That's the recall
rule (`Brain::Army::CheckSquads`): once a squad is below its peak power and what is left, at our trade
rate, no longer beats the quota a fresh squad is sized against, it turns back. (The 40%-of-peak line this
section used to describe is not in the code.)

## 6. Economy is the base of war: efficiency, not imitation

- **Extractors:** a T1 extractor (50 metal, 3 E/s upkeep) pays for itself in about 25 s, so take every
  safe spot early. Moho/exploiter upgrades add about 6 m/s for 17-20 E/s, so their upkeep is priced in.
  In the code: the core ranks every builder job by seconds until payback at shadow prices (§16), and
  `Brain::Production::MohoConTask` builds an upgrade constructor only when the upgrade pays its upkeep at
  the converter price and the time it saves beats the constructor's cost (priced up while we're short of
  army). An energy stall slows everything.
- **Recycling** (`Brain::Recycler`). Obsolete eco and units get turned back into metal, by value, not by
  fixed gates:
  - any energy plant worse per metal than the best plant we can build now, when its metal now beats its
    energy over the planning horizon and energy stays in surplus without it (`EcoReclaimUpdate`); this
    covers solars and winds once fusion carries the base, and fusions once advanced fusions do
  - T1 makers once T2 makers exist and energy still overflows
  - combat units at home that a higher tier we own outclasses per metal (`Salvage`)
  - idle caretakers whose metal beats the build power they actually apply (`NanoUpdate`)
  - a reclaim starts only when its metal fits in storage; otherwise it asks for storage (`Brain::Storage`)

## 7. Do not repeat yourself (Sun Tzu VI.28)

> "Do not repeat the tactics which have gained you one victory, but let your methods be regulated by
> the infinite variety of circumstances."

Decisions are re-evaluated every update from the live state, never on a script timeline. (The named
postures and their hysteresis are gone, §2.) The old plan of randomized wave timing and attack axes is
dropped: CLAUDE.md §2 forbids dice, so variety has to come from the changing situation.

## 8. Preparation against what can't be seen

- Anti-nuke before the first missile could exist (`Brain::Strategic::NukeRisk`): its build and stockpile
  time against the metal the enemy could have put into a silo since T2, times what a nuke would erase in
  our base, against the anti-nuke's cost. A seen silo makes it certain.
- Shields over the most valuable uncovered infrastructure, while what one covers is worth more than the
  shield and our army covers what we need (`ratio >= 1`).
- Static anti-air over infrastructure, scaled to the air metal we've seen (status unverified: not in
  `brain.as`; whatever the core's defence planner does is not checked here).

## 9. Rapidity (Sun Tzu XI.19) and closing the game

> "Rapidity is the essence of war."

At 40 minutes BARb-style play is often far ahead and still hasn't won. An advantage must turn into a
decision before the enemy recovers. The earlier build had an ALLIN posture for this. The current code has
no posture: because the attack quota is the needed power, a dominant army fills it at once and keeps
launching.

## 10. Line of sight over radar dots

A radar blip has no type, so it has no real threat, no counter and no good target. Only sight gives those.

- **In the code** (`Brain::Scout`, issue #48):
  - Each cell remembers when we last saw it. Seeing a cell is worth our metal that something hidden there
    could reach before our army can respond, plus unidentified radar dots there and open enemy-side
    extractor spots that may have been taken since. Picks are spread by direction.
  - Scouts take the best cells (core switch `scoutMap`), and the scout quota is the number of cells worth
    more than a scout (at least 1). No timers, no fixed quota.
  - Dragon's Eyes go where we die (`Brain::Intel`).
  - When blind, the enemy is assumed at least as strong as we are (see §1).
- **Core behaviour:** the core keeps radar-only contacts as unknown types; their threat is the mean
  identified threat ([AUDIT.md](AUDIT.md)).

## 11. Inferring the army behind a jammer from its projectiles

You usually judge what's behind a jammer by what is shooting at you from there.

- **Core (BARb, already active):** when a unit is hit by something unseen, the core takes the weapon
  that hit it (its range and the unit types that carry it), projects back along the shot direction,
  and places a **phantom enemy** of that type at the estimated firing position. They feed the threat map,
  pathing and attack decisions. BARb's fixed lifetimes (1 minute mobile, 20 static) are replaced in the
  core patch: a phantom is remembered while it could still be there ([AUDIT.md](AUDIT.md)).
- **Anarvā adds:**
  - Seen jammers make their whole cluster count as defended before the first shot.
  - The loss heatmap (decaying over the planning horizon) outlasts the phantoms, and drives Dragon's
    Eyes, Fortify and extractor turrets (`Brain::MexPorc`).
  - Junos and scouts turn the guess back into sight.
- **Limit:** the script API has no per-hit damage event, so the projection itself can't be tuned from
  script.

## 12. Spam and screening

Cheap units do two jobs: scouting, and soaking enemy firepower (spam).

- **In the code** (`Brain::Production::Score`):
  - Units with more health per metal than our army's average get a screening bonus scaled by the heavy
    and artillery share of the seen enemy army. Big, slow shots spent on fodder are wasted. (No fixed
    150-metal cutoff.)
  - It's computed from stats, never from unit names.
- **Inherited behaviour:** once we field T3, the factory script (`manager/factory.as`, BARb's list) marks
  enemy T1 spam (Pawns, Grunts, Fleas…) as ignored for target choice, so expensive units don't chase
  fodder. Decoy commanders are detected by the core (status unverified).

## 13. Target priority against a mixed army

Some units exist only to distract: decoys, spam, scouts.

- **What we steer:**
  - which enemy *group* a wave commits to (strength vs our wave, value per distance)
  - ignore flags for fodder and decoys
  - (the per-unit threat weighting from `behaviour.json` is no longer read by the core patch)
- **Per-shot targeting** (core patch, switch `focusFire`, set on by `brain.as`): each unit in a squad
  focuses the visible enemy in its range whose removal cuts the enemy's firepower most per point of
  damage spent (threat ÷ remaining health), counting what its death blast takes with it (#44). This is
  the "artillery before the Pawns" order; the earlier limit (script API can't set targets) no longer
  holds.

## 14. Projectile and AoE evasion (micro)

Sidestepping slow projectiles, and spreading out against splash, are per-unit micro.

- **In the core patch** (switch `strafe`, set on by `brain.as`): a shot is dodgeable when its flight time
  (distance ÷ shot speed) times our speed exceeds its blast radius plus our size. Against the most
  threatening dodgeable shooter, a squad unit's spot moves sideways by what it covers in one flight time,
  switching side every flight time. Beams are not dodged. This uses the shooters' weapon facts, not the
  projectiles in flight.
- Squad spacing against splash comes from the splash geometry in the core patch ([AUDIT.md](AUDIT.md)).
- **Still a limit:** seeing actual projectiles in flight needs a game-side widget or gadget.

## 15. Data, not imitation

- **Reference curves from top players** come from `tools/fetch_replays.py`, `run_replay.py` and
  `analyze_replays.py`, separately per format (1v1, ≤4v4, >4v4), because formats differ. Top duel
  findings (12 player-games, rated 38-55):
  - winners keep army value close to eco value by minute 10
  - losers over-build static defence
  - energy:metal runs 11 → 13-16 → 22-25 as the spend mix shifts
- **Lesson (b2):** copying that E:M ratio was a mistake. In this engine energy income also *unlocks
  tech*: fusion needs about 840 E/s of income before the core may build it. A lower energy target left
  b2 with zero fusions and 750 E/s at 30 minutes, and it lost every open map. Pros can run 11-16 E:M
  because their metal income is huge. (b2 was an early build.) BARb's energy table is no longer read:
  the core patch builds energy by need and payback, and plans ahead the energy needed to spend our metal
  income at the energy-per-metal of what our factories make (#86), so the E:M ratio follows from what we
  build rather than from a copied curve.
- **Evidence source:** per-minute stats of top-player replays are now in a SQLite database
  (`runs/replays.db`, built by `tools/replay_db.py`).
- **Team games are different.** Top team players (≤4v4, 25 player-games rated 35+) boom harder: about 34 m/s at minute 5 and 58 at 10 (duels: 25 and 48). They go T2 about **5-6 minutes earlier** (10.6 vs ~16 min), with eco value near 2× army at minute 10 (duels: ~1.5×). Allies share the front, so the planning horizon is longer, and the horizon formula is what has to capture that, not a copied timing. In 1vN, Anarvā has no allies covering it, which points the other way.
- **Unit choices** come from capabilities read at runtime (damage against air, surface and underwater,
  health, range, speed, cost), so a balance patch changes the choice automatically.

## 16. Doctrine: no static thresholds

No hand-picked cutoffs like "if minute ≥ 9 and income ≥ 30". Every decision compares the live marginal
value of its alternatives. Only **game facts** (unit costs, upkeep, extraction, converter rates,
build power per constructor) and plain unit conversions may be constants. The shared model lives in
`Brain::Economist`:

- **Planning horizon H** (`Economist::Horizon`). How long what we own keeps paying before the enemy can
  take it: the time the enemy needs to build a force worth everything we own (our metal ÷ their income;
  unseen, each enemy earns as fast as we do), plus the time to cross the map. (The earlier "about the time
  already played" (Lindy) horizon was 0 s at the start, so every future value read 0.)
- **Energy priced in metal** at the converter exchange rate (`Economist::MetalValue`). The core's builder
  ranking uses shadow prices on top of that: metal is worth nothing while it overflows, and energy is
  priced at our spending ratio (metal pull ÷ energy pull) while it binds, or at the metal per energy of
  what we build when the planned spending will need more energy than we make.
- **Builder jobs** (core patch, `BuilderManager`) are ranked by seconds until the job pays back at those
  prices: travel + build + cost ÷ yield for extractors and plants, travel + build + the time our stock and
  income need to cover the cost for everything else. BARb's 2000/10000-elmo job radii and the "NOW"
  factory bands are gone.
- **Investments** are made when their payback is shorter than H. T2 example (`Tech::Allowed`): (lab +
  moho upgrades of our *actual* extractor count) ÷ (extra metal − upkeep priced in metal), and it must also
  beat the next T1 extractor we could still claim, unless the lab's cost is already banked. If the enemy
  has teched while we're behind, our T1 army is losing value, which forces the move.
- **Needed power** = known enemy army (summed per known enemy unit, the same threat measure as ours; the
  commander's D-gun adds no sustained damage, so a commander reads about 4.6 Pawns, not 113) + the army
  guessed under seen jammers, divided by our measured trade efficiency. Waves gather to it, and
  constructors wait while our power ÷ needed is below 1.

The tunables this section used to list (opener window, Fortify heat floor and distance band, Recycler
surplus margins, Strategic income conditions, Intel eyes heat floor, the 0.5 wreck fraction) are gone:
each is now a comparison with a cost or a measured value, e.g. Fortify and Dragon's Eyes fire when the
metal lost in a cell beats the turret or camera, and the wreck pool is the wreck metal actually on the map.

### Judgment numbers still in the code (debt, to remove)

The full inventory and what replaced each item is [AUDIT.md](AUDIT.md) (the owner closed the constants
rework on 2026-11-25, #71 and #42). The items this list used to hold are gone: `workers * 0.5`, the silo
clock, the Juno and tactical-launcher gates (now value tests), the 250-metal `infra` cut (every structure
counts), the commander `hide` config values (no longer read by the core), `CORE_BUILDER_SHARE` and the
posture bands.

Verified leftovers in the code (2026-11-25):

- Turret, camera and wall jobs are queued in the NORMAL band, below income jobs (HIGH): a fixed ordering,
  not a value (open in [AUDIT.md](AUDIT.md)).
- A second anti-nuke when an enemy silo is seen waits until our infrastructure is worth more than twice
  the anti-nukes' cost (`Strategic::Update`).
- The T1 spam list ignored once we field T3 is BARb's name list (`manager/factory.as`).

Game facts read from unit files (converter rate, 75% conversion level, constructor build rate, build
times, mine and silo costs) are not on this list: they are what the game *is*, and they get regenerated
after a balance patch.

## 17. Starvation is fatal

An energy stall slows every constructor and factory at once, and a metal shortfall stalls production.
Build power must follow metal income.

- Constructor need (`Brain::EcoPos`): a constructor pays only through work the ones we have can't do,
  i.e. open extractor spots to claim. Claiming is limited by walking: one constructor takes a spot per
  (walk from base + build) seconds, so the count needed is the sum of that over the unclaimed spots ÷ the
  planning horizon. While we have fewer and are not weaker than the enemy army we know of
  (`ratio >= 1`), the factories make constructors; otherwise the knob holds constructors where they are
  and the factories make army. A T1 constructor is about 4.25 build-speed units (85 workertime).
- **Lesson (b3, early build):** cutting constructors whenever we were behind produced a death spiral:
  income fell from 20 to 8 m/s while BARb grew to 50. The later "cut only while pushed back at home" rule
  is no longer in the code: `Assess::pushedBack` is only logged.
- During an energy stall:
  - Production defers to the core (`Production::MakeTask` returns nothing), and energy wins the builder
    ranking because binding energy is priced at our spending ratio.
  - Builders stop assisting factories (`isAssistRequired` is false while energy stalls or metal runs dry,
    `manager/economy.as`).
  - The Recycler gives cheap plants back to the core if the big plants no longer cover our pull.
  - Converters switch off below the game's converter level (mmLevel, a game rule).

## 18. Wrecks are the fastest metal

Rez bots (Lazarus, Necro, Legion rez bot) reclaim wrecks, resurrect them into free units, and reclaim
trees and plants for energy. They cost 130 metal, move at speed 78 and have 200 build power.

- **BARb's flaw:** its factory weights almost never build them, and Cortex sends its Necros scouting.
- **Anarvā** (`Brain::Production::RezToBuild`, `Brain::RezLab`, `Brain::ReclaimUpdate`): the pool is
  the wreck metal actually on the map (C++ bridge `AiGetWrecks`). A rez bot is built while that pool is
  worth more than the rez fleet plus one more bot. When none of our factories can make rez bots (a
  vehicle opening), a bot lab is ordered once the pool beats the lab plus one bot. Each wreck field is
  reclaimed (or resurrected, by a rez bot) by the constructor that reaches it soonest, when its metal
  minus the walk and the risk beats that constructor's current job. `RezLab` reads build options from unit
  facts (`facts.as`); `RezToBuild` still maps lab to rez bot by name.

## 19. Redirecting build power, and priority toggles

- **Redirect:** the share of constructor build power that should serve the army equals the army
  deficit. The script's Redirect rule is no longer in the code. In the core patch, assisting a factory
  competes with every other builder job on the same payback-time ranking (§16), with BARb's assist caps
  removed. Threatened builders fall back to assisting the factory they reach soonest
  (`Brain::BuilderSafeUpdate`).
- **Limit:** BAR's build-priority toggles are unit commands handled by a game gadget. They are not
  implemented, neither in the scripts nor in the core patch. The nearest lever is task priority.

## 19b. Geothermal (gap)

A T1 geo (~560 M) gives about 300 E/s, worth about 4.3 m/s at the converter rate, so it pays back in
about 2 minutes, far better than solars or wind. Advanced geos are better still but explode violently,
so nearby infrastructure counts against them as risk.

- **Core behaviour:** geos are a **last resort**. A geo spot is tried only when no other energy build
  is wanted, and BARb's config comments geos out of the energy list. Regular energy tasks can't place
  onto geo spots, and the script can't see geo-spot positions.
- **Why it's weak:** the core's energy planner ranks only energy buildings that can be placed
  anywhere. Geos, which need a vent, sit outside the comparison and appear only when no energy is
  wanted at all. That's backwards: a safe vent is often the *best* energy choice.
- **Disadvantages to weigh:**
  - fixed vent location, often contested and outside our cover, so a prime raid target
  - they explode when destroyed, advanced geos massively, so one loss can wipe the cluster around it
  - concentration risk: one big source dies at once and can stall the whole economy
  - energy only, with a big up-front cost locked to one spot
- **Decision to implement:** payback against the horizon, weighed against **exposure** (threat and
  loss heat at the vent) and **blast cost** (the value of our infrastructure inside the explosion
  radius). Advanced geos get spacing from that blast cost, not a fixed distance.
- **Planned:** drive the core's geo-spot task through its fallback path, by making "no other energy
  wanted" true while an open safe geo spot exists, or by adding script access to geo spots.

## 20. Travel distance and front labs (planned)

Production far from the fight wastes army-time on the walk. A forward lab saves (travel time ×
production rate) of army presence, against the risk of losing it, which is measured from threat and
loss heat near the site. The same trade decides where rally points and the next lab go.

## 21. The script API ceiling, and the path past it

History (early builds from before the 2026-11-24 rework, which still mostly ran BARb's own logic; not
re-measured since):
- 1v1 vs BARb-hard was met at ≥2:1 on every map type ("M1 met").
- 1v2 was 0–11 across every variant tried: Fortify, commander zone, the economy gates.

Current state: since the rework no full-length 1v1 against BARb hard has been won yet; that is the
current work.

The early build out-ecoed each BARb individually but not both combined, got pushed back, and lost the
commander. Most of the levers it lacked were blocked by the **script API**:

- no unit commands: dodging, explicit commander positioning, focusing one opponent's base or commander
- no feature or vent queries: wreck fields, geothermal
- no per-enemy lists: target priority, snipe targets

CircuitAI is open source (GPL-2.0). The **fork of the C++ core** now exists (`core/circuitai.patch`,
applied to `ref/circuitai` branch `anarva129`). Its bridge gives the scripts the enemy list (position,
velocity, type, cost, ids, LOS/radar flags), enemy groups, wrecks, metal spots, line of sight,
elevation and threat, and lets them assign, abort and enqueue tasks for our units. In the core itself it
adds focus fire (§13), dodging (§14), height-aware artillery and squad spots, and the payback ranking of
builder jobs (§16). Still missing: geothermal vent queries, projectiles in flight and burn zones; a
game-side companion gadget would cover what the AI interface can't see.

## 22. How humans beat several hard BARbs (solo replays)

Six public replays of **one human alone, no allied bots, against 3–14 hard or hard-aggressive
BARbs**. **Correction:** three of the six were free-for-all, with each bot on its own team, so the bots also
fought each other (MR_Okay and BRICS_PLUS on Greenest Fields, the Oort Cloud game). The truly allied
1vN games are Knizek (vs 4 hard-aggressive, Ancient Bastion, a walled base map), NoviceKing99 (vs 3 hard,
Shore to Shore) and FloBoo (vs 8, Full Metal Plate, a flat all-metal map). Edict (vs 2 on Comet Catcher),
Gundlach (vs 4, Ring Atoll) and Refrog (vs 2) are queued for playback. The table mixes both kinds; the
boom pattern holds in the allied games too, but the army ratio is lower in FFA, played back headless and measured every minute (`tools/fetch_vsbots.py`,
`tools/analyze_vsbots.py`):

| minute | human income vs ONE bot | human army vs ALL bots combined |
|---|---|---|
| 8 | 2.0× | 0.55× |
| 10 | 1.8× | 0.38× |
| 15 | 2.6× | 0.47× |
| 20 | 3.1× | 0.61× |
| 25 | 3.3× | 0.71× |

- **Boom first, and keep booming.** Knizek vs 4 hard-aggressive had zero army and zero defence for 8
  minutes and reached 134 m/s against 49 per bot. The Oort Cloud player (vs 14) built *no army at all*
  and won from a 640 m/s economy behind static defence and long-range weapons.
- **A smaller army, used at home.** About 0.4–0.7× of all bots together is enough when it fights next
  to its own turrets and the bots arrive one at a time.
- **Static defence late, not early.** Human defence is near zero until minute 15–20, then jumps once the
  economy can afford it (Oort Cloud: 85k at 20 min, 265k at 25 min).
- **The reasoning:** BARb armies gather at home and don't punish early greed, so an enemy army sitting
  in its own base is no threat. What matters is force **projected at us**.
- **Anarvā then** (early build, before the 2026-11-24 rework; not re-measured since): about 1.3× one bot's
  income, 1–3 points short of what the humans reach. That gap, not the army, is what to close first.
- **`F_BOOM`** (early build, a flag that no longer exists: constructors vs army scaled on *pressure*,
  home losses relative to a minute of income, not on enemy presence) went 0–6 in 1v2. Booming alone
  wasn't enough: the AI boomed but its economy didn't grow like the humans' does. Next: find *what* the
  humans build to get 2–3× (constructor count, converter and advanced-extractor timing, rez bots) and
  compare it minute by minute with Anarvā's `[ANV] eco` log and the replay database (`runs/replays.db`).

## 23. Space, efficiency and the cheapest energy that fits

Energy choices aren't only cost per energy. They are cost per energy **per unit of space and build time**:

- **Wind.** On a large map with strong wind, wind turbines beat solars on cost per energy (especially for
  Armada). They need space, and wind is variable, so storage or a mix covers the dips. The decision
  inputs are the map's wind range (min/max wind in mapinfo, now readable by the map analysis), free
  space near the base and its risk.
- **Assistant drones** (the commander-built assist drones / build drones) can put down cheap eco like
  wind fields without tying up real constructors. Use them whenever free build power is the bottleneck.
- **Converters.** T1 converters are cheaper per unit but convert less and take more space; T2 converters
  are dearer but denser and more efficient. With space to spare, T1 has the better cost per metal; when
  space or build time is the limit, or energy is abundant, T2 wins. Compare per metal produced, per
  square, per second of build time.
- **Nano reach.** Construction turrets only reach a fixed radius. Eco, factories and their nanos must
  be placed so the turrets cover what they're meant to assist. Every building plan accounts for it.

## 24. Nothing is ready until it's finished (build lead time)

An investment pays nothing until it completes. A fusion started now gives energy only after its build
time at our real build power; until then it *costs* drain. The same goes for factories, and above all
the T2→T3 transition (an experimental gantry plus its first unit is minutes of drain with zero
output). So every investment's value is `return × (horizon − time to finish)`, with time to finish =
cost ÷ the build power actually assigned to it. Storage must bridge the drain while it builds, or the
investment starves everything else (§17). In the code: the core's builder ranking (travel + build +
payback, §16) and its energy chooser (build time at our build power + payback) include time to finish,
and so does the anti-nuke's readiness (`NukeRisk`). The T2 gate (`Tech::Allowed`, using
`Economist::MohoPayback`) compares payback with the horizon but has no build-time term yet.

## 25. High ground and chokepoints

High ground is a real advantage in BAR:

- **Range.** Ballistic weapons (plasma cannons, artillery) gain range when they fire downhill.
- **Sight.** Elevated units and turrets see further over ridges.
- **Cover.** Terrain blocks direct fire from below, while the defender shoots down over the crest.

The map analysis (`tools/analyze_maps.py`) finds, for every start position, the narrowest stretch on our
half of the route to the farthest enemy (our choke) and the highest passable ground within ~500 elmos of
it on our side. Glacier Pass: chokes 160–224 wide with high ground 150–190 elmos above them. Colorado: a
32-wide choke with high ground 275 above.

**In the code (`Brain::Strategic::TerrainFortify`):** while we can't win an open fight (`ratio < 1`), or
whenever we're outnumbered (1vN), Anarvā builds the turret with the most power per metal it can build on
that high ground (if it would survive there), dragon's teeth across the choke mouth, and mines beyond the
teeth once it has a minelayer. One more turret whenever something has come at us since the last order.
Attackers stall in the choke under fire from above (Sun Tzu X: "occupy the raised and sunny spots, and
wait for the enemy").

**Maps get updated.** Map facts are keyed by the full name, with a fallback to the same map's other
versions: the version suffix is stripped. A brand-new map has no facts, and Anarvā falls back to the
core's own behaviour until `tools/analyze_maps.py` is re-run.

## 26. Validation: the built-in scenarios

BAR's single-player scenarios ship BARb setups that are designed to be hard to beat:

- "One by One": 7 BARbs, free-for-all on TMA20X
- "World War XXV": 8 BARbs in alliances on Neurope
- "Catch those rare Comets": **1v3 BARb**, difficulty 10, on Comet Catcher Remake. It is the first target.
- "Outsmart the Barbarians": 3 aggressive BARbs
- "Supremacy": difficulty 10

Humans clear them with focused plans, such as rushing T2 bombers to kill commanders. They're the target
validation suite for Anarvā's adaptive strategy (issue tracker: "scenarios").

## 27. Command, not a library of tactics

From notes by a friend of the project ("The problem of command"). A bot with a perfect routine for every
maneuver still fails when several opportunities and threats arrive at once. Then the question is
**which concern comes first, and why**. Any fixed priority order loses to a situation that reverses it.
What wins is one continuous process of **interpretation → prioritization → anticipation → decision →
revision**.

How Anarvā takes this on:

- **One currency, one arbiter.** Every option (an extractor, a turret on high ground, a converter, a
  wave, a retreat, a raid) is valued as expected metal-equivalent gained over the planning horizon,
  minus risk. That is the aim. Today each module compares its own option with its cost in this currency
  (the Director only supplies the strength ratio and the needed power), and the core ranks builder jobs
  on one payback-time scale; there is no single arbiter across all modules yet. This is why there are no
  static thresholds: a threshold is a frozen priority.
- **Value depends on what comes next.** A target's worth includes what killing it enables. The radar
  that sights for a turret line, the anti-nuke that covers the base, the AA screen over the eco: each is
  worth the follow-up it opens, not its own cost. Sequenced attacks are an argument in several moves
  (issue: attack sequencing).
- **Refusing a fight can win it.** Giving up extractors to keep the army, when help or a better
  battlefield is coming, is a present loss for a later gain. The recall (§5) and `Brain::Hold` (which
  defends an asset only if enough units can be there before the enemy, and otherwise doesn't feed units
  in) are the start of that; the value of territory has to be weighed against the army that defends it.
- **Losing trades can be strategic.** Cheap raids that force the enemy to build counters and delay its
  economy succeed even at bad local trades. Raids are judged by the enemy's production response, not
  only by kills.
- **Probes are experiments.** A limited attack measures the type and size of the resistance and updates
  the enemy model. The enemy's behaviour is evidence of a plan: concentration means an attack is coming,
  weak response means weak defence, or bait.
- **Terrain is possibility, not a score.** The same hill is a refuge, a trap or a route. Walls can
  leave a corridor open on purpose and lead attackers into a kill zone. Map analysis gives the
  geometry; its meaning comes from the armies and the timing (§25).
- **Timing is judgment.** Slow heavy rockets must land together on a commander, or the first hit warns
  it. EMP is worth what is done during the stun: stopping a T3 push, opening a nuke window on an
  anti-nuke. A commander's D-gun charge is unacceptable risk normally and the best move in a
  catastrophic breakthrough.
- **Restraint.** Knowing when *not* to use a clever tactic. A kill zone may never be visited; a probe
  may reveal more about us than about them.

## 28. Scale: every count is sized to the game in front of it

How many of anything is never a fixed number. It's the scale of what that thing works on, divided by
what one more of it adds, as long as one more still repays its cost:

| What | Sized against | Rule (status) |
|---|---|---|
| Constructors for expansion | unclaimed extractor spots, walk from base, constructor speed and build time | Σ(walk + build) ÷ horizon, only while `ratio >= 1` (`Brain::EcoPos`). The earlier n* = F·√(s·t / 2c) (F_EXPAND) is gone |
| Rez bots | wreck metal actually on the map (bridge) | one more while pool > fleet cost + one bot (`Production::RezToBuild`); a bot lab when none of our factories can make one (`Brain::RezLab`) |
| Converters | spare energy that would be thrown away | status unverified: not decided in `brain.as`, so left to the core's economy manager (not checked). The F_CONVERT rule no longer exists |
| Turrets at the choke | enemy force projected at us | one per attack (`Strategic::TerrainFortify`); the metal-deficit variant (F_DEFSIZE) is gone |
| Nanos | build power they actually apply | idle ones are reclaimed when their metal beats their use (`Recycler::NanoUpdate`); building them: status unverified (core). F_WASTE is gone |
| Build power overall | open extractor spots and the army ratio | `EcoPos` sets the core's `buildpowerRatio` (§17) |

Scale changes during the game: map size, number of players, game time, how much has died. So the
counts are recomputed every update, never fixed at start.

## 29. Just in time: army only when the enemy will actually arrive

From the owner, describing top players: they build no units until they're needed. They expand and let
the enemy walk all the way to them, while their economy compounds. When the enemy arrives they produce
one tier above the enemy's units, push back, harvest the wrecks and end the game. It's one strategy
among several, and the reasoning is what transfers:

- **Every unit built early is metal not compounding.** Army (and defence) bought before the threat
  arrives costs the growth it would have bought.
- **The decision is lead time against arrival time.** Start producing when the time to produce the
  answer is at least the enemy's time to arrive. Producing the answer means one tier up, at our real
  production rate (factory and assist build power, banked metal plus income), plus tech time if we
  aren't there yet. Arrival is the distance of the enemy force seen on radar or LoS, divided by its
  speed. Scouting therefore decides when the switch happens, not just what to build.
- **A tier up wins the exchange.** T2 against T1 trades several times better per metal, so the lab must
  be ready *before* arrival. The T2 timing follows from the expected contact time.
- **Over-defending is the same mistake.** Turrets sized to an army that hasn't come yet were measured
  worse (F_DEFSIZE, early build; the flag no longer exists).
- **In the code:** the C++ bridge now lists enemy units with position and velocity (§21).
  `Brain::Hold` assigns each armed enemy to the asset of ours it is closing on soonest and defends that
  asset with the units that can be there before it, nearest first, or not at all. Lead time against
  arrival for *production* (start the one-tier-up answer when its build time reaches the enemy's arrival
  time) is not implemented yet.

## 30. The commander, from 60 replays

`tools/replay_harness` follows every commander in a replay every 5 s (position, command, armed metal of each
side within 600, nearest enemy), plus what it builds and where it dies; `tools/analyze_comm.py` aggregates.
60 replays, 2026-11-24:

| Source | Commanders | Leaves start (median min) | Median distance out at min 3 / 5 / 8 / 11 | In contact, min 3-14 | Far builds (median distance) | Deaths |
|---|---|---|---|---|---|---|
| Top 1v1 duels | 48 human | 3.2 | 300 / 410 / 725 / 1160 | 6-7% | mex 1400, LLT 2700 | 18 |
| Top team games | 72 human | 2.6 | 1400 / 2600 / 2600 / 2870 | 21-25% | LLT 3300, teeth 3100 | 24 |
| Humans vs bots | 26 human | 2-2.8 | 380-460 / 400-1300 (trips) | 2-5% | LLT 3200-3600, radar 3050, teeth 1500, mex up to 1600 | 12 |
| BARb in those games | 168 AI | 1.6-2.1 | ~400-780, then 350-450 all game | 5-7% | mex 500-900, LLT 600-900 | 76 |

What transfers (the reasoning, not the routes):
- First ~3 minutes: the commander builds the eco at the start (wind/solar/mex within ~300).
- Then it is the best front builder: it walks out to claim extractors (to ~1500) and to put up a forward
  post at the contested line (~3000: LLTs, radar, dragon's teeth). The post buys vision and area denial
  cheaply where the fighting will be; then it comes back. In team games, where one commander's death
  doesn't end the game, it stays out there.
- BARb keeps its commander home and loses it there anyway (many deaths at minutes 5-6, close to home):
  staying back is not safety.
- Implementation: the commander takes a job only when its gain beats P(death) there × everything we own
  (`Brain::CommanderTask`, `CommGuardUpdate`); unseen enemy strength counts as danger (`CommFog`, was
  F_COMMFOG). The script's forward extractor claims (`CommForward`, was F_COMMFWD) are no longer called:
  the core's builder ranking picks the commander's jobs, and the script keeps only the risk decision.
  Next: the forward post (value = the vision it gives, see issue #48, plus the spots it holds).

## Planned

- Walls and dragon's teeth at chokes, in front of defence lines (Sun Tzu's terrain chapters). Teeth
  across the analysed choke are in the code (§25); walls in front of other defence lines are not.
- Holding chokepoints with static defence in 1vN: in the code for the analysed choke (§25).
- Feints: a raid on one flank before the main wave hits another (I.20, "hold out baits"). Not built.
- Production that picks the next unit by cost-effectiveness against the scouted composition: in the code
  (`Brain::Production::Score`, TACTICS.md §1).
