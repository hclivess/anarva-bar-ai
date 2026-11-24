# Anarvā — strategy and tactics: principles to mechanisms

Anarvā doesn't copy moves. It encodes the **reasoning** behind them. Each principle below is tied to
the code that implements it. Sources (public domain, kept locally under `ref/strategy/`): Sun Tzu, *The
Art of War* (Giles translation); Clausewitz, *On War*; Napoleon's *Military Maxims*.


> **Status:** every mechanism below is implemented, but several are off by default until they win head-to-head tests. The README status table is the source of truth for what's on.

## 1. Know the enemy: scouting decides everything

> "If you know the enemy and know yourself, you need not fear the result of a hundred battles."
> — Sun Tzu III.18
>
> "…foreknowledge cannot be elicited from spirits…" — XIII.5 (it must come from scouts)

- **Army vs. scaling** (`Brain::Director`). Each update, the scouted enemy mobile threat is compared
  with our power and drives the core's constructor-vs-army knob (`aiFactoryMgr.buildpowerRatio`):
  - enemy weak → scale (more constructors, expand, tech)
  - enemy strong → army
  - **blind** → hedge and push scouts, because scaling on a guess is a gamble
- A permanent scout quota of at least 3 rises when we're blind or jammed. Air scouts are bought on
  jammer alert.
- **What we can't see** (`Brain::Intel`):
  - A seen jammer is treated as a hidden army, a phantom threat on its cluster.
  - Places where we keep dying get Dragon's Eyes, because sight is the only thing a jammer can't
    stop.
  - Junos clear jammers and radar.

## 2. Measure strength, then choose the fight (Sun Tzu III.9-10)

> "If ten to the enemy's one, surround him; if five to one, attack him; if twice as numerous, divide
> our army into two. If equally matched, we can offer battle; if slightly inferior in numbers, we can
> avoid the enemy; if quite unequal in every way, we can flee from him."

The Director's postures follow this ladder, using our power ÷ the enemy's seen mobile threat:

| ratio | posture | behaviour |
|------:|---------|-----------|
| ≥ 4 | ALLIN | small waves, constant pressure, close the game |
| ≥ 1.6 | PRESSURE | frequent waves; raiders split off to hit the weak points |
| ~1 | BALANCED | offer battle with a large wave |
| < 0.75 | HOLD | avoid open battle, fight under our own defences, strike only with a big wave |
| < 0.4 | TURTLE | everything into army; defend the base (planned: static defence at chokes) |

## 3. Concentration of force (Napoleon, Clausewitz)

> "The first and most important rule… to concentrate as much as possible." — Clausewitz

- **Wave control** (`Brain::Army::MakeTask`). Every new combat unit joins *one* gathering wave, sized
  by the Director. When it's full it launches together. This replaces the core's habit of either
  never launching or trickling.
- **Broken-squad recall.** A squad that has lost most of its power is pulled back to regroup. Feeding
  units in one by one is the opposite of concentration.

## 4. Avoid strength, strike weakness (Sun Tzu VI.30-31)

> "The way is to avoid what is strong and to strike at what is weak… Water shapes its course according
> to the nature of the ground." — VI.30-31
>
> "Attack him where he is unprepared." — I.24

- Raiding packs (`raid` quota) go after eco and builders. The core's threat map steers them away from
  defences.
- **A greedy enemy** (lots of buildings, little army) is punished: we switch to PRESSURE instead of
  trying to out-boom him.
- Attack target choice compares our wave with each enemy group's strength
  (`thr_mod.attack` 0.85-1.05 instead of BARb's suicidal 0.6-0.8).

## 5. The culminating point (Clausewitz)

An attack loses strength as it advances; past its culminating point it should stop. That's the recall
threshold: below 40% of peak power, and weaker than a fresh wave, a squad turns back.

## 6. Economy is the base of war: efficiency, not imitation

- **Extractors:** a T1 extractor (50 metal, 3 E/s upkeep) pays for itself in about 25 s, so take every
  safe spot early. Moho/exploiter upgrades add about 6 m/s for 17-20 E/s, so they're gated by energy
  headroom (`Brain::Eco`). An energy stall slows everything.
- **Recycling** (`Brain::Recycler`). Obsolete eco gets turned back into metal:
  - solars and winds once fusion carries the base
  - fusions once advanced fusions carry the grid
  - T1 makers once T2 makers carry conversion
  - idle T1 units late in the game

## 7. Do not repeat yourself (Sun Tzu VI.28)

> "Do not repeat the tactics which have gained you one victory, but let your methods be regulated by
> the infinite variety of circumstances."

Postures are re-evaluated every update with hysteresis, never on a script timeline. Planned:
randomized wave timing and attack axes.

## 8. Preparation against what can't be seen

- Anti-nuke the moment a silo is seen, and proactively once rich.
- Shields over the most valuable infrastructure cluster.
- Static anti-air over infrastructure, scaled to the air metal we've seen.

## 9. Rapidity (Sun Tzu XI.19) and closing the game

> "Rapidity is the essence of war."

At 40 minutes BARb-style play is often far ahead and still hasn't won. A dominant force ratio switches
to ALLIN, so advantage turns into a decision before the enemy recovers.

## 10. Line of sight over radar dots

A radar blip has no type, so it has no real threat, no counter and no good target. Only sight gives those.

- **Implemented:**
  - We keep sight continuously: air scouts on a timer whenever an air plant exists (every 3 min, every
    90 s when blind or jammed), and ground scouts from any factory when there's no air plant.
  - The scout quota is at least 3 (4 when blind).
  - Dragon's Eyes go where we die.
  - When blind, the Director hedges instead of scaling (see §1).
- **Core behaviour:** the core keeps radar-only contacts as unknown types with a generic threat range.

## 11. Inferring the army behind a jammer from its projectiles

You usually judge what's behind a jammer by what is shooting at you from there.

- **Core (BARb, already active):** when a unit is hit by something unseen, the core takes the weapon
  that hit it (its range and the unit types that carry it), projects back along the shot direction,
  and places a **phantom enemy** of that type at the estimated firing position. Mobile phantoms last 1
  minute, static ones 20, and they feed the threat map, pathing and attack decisions.
- **Anarvā adds:**
  - Seen jammers make their whole cluster count as defended before the first shot.
  - The loss heatmap persists after the phantoms expire, and drives Dragon's Eyes and Fortify.
  - Junos and scouts turn the guess back into sight.
- **Limit:** the script API has no per-hit damage event, so the projection itself can't be tuned from
  script.

## 12. Spam and screening

Cheap units do two jobs: scouting, and soaking enemy firepower (spam).

- **Implemented** (`Brain::Production::Score`):
  - Cheap units (under 150 metal) get a screening bonus scaled by the heavy and artillery share of the
    seen enemy army. Big, slow shots spent on fodder are wasted.
  - It's computed from stats, never from unit names.
- **Core behaviour:** once we field T3, BARb marks enemy T1 spam (Pawns, Grunts, Fleas…) as ignored
  for target choice, so expensive units don't chase fodder. Decoy commanders are detected by the core.

## 13. Target priority against a mixed army

Some units exist only to distract: decoys, spam, scouts.

- **What we steer:**
  - which enemy *group* a wave commits to (strength vs our wave, `thr_mod`, distance)
  - ignore flags for fodder and decoys
  - per-unit threat weighting in `behaviour.json`
- **Limit:** per-shot targeting inside a fight is done by the engine's unit AI; BARb's script API can't
  set it. True priority (shoot the artillery before the Pawns) needs a game-side gadget.

## 14. Projectile and AoE evasion (micro)

Sidestepping slow projectiles, and spreading out against splash, are per-unit micro.

- **Limit:** the script API gives no per-unit move orders, and the BARb core doesn't dodge.
- **Design for later:** a companion LuaUI widget or gadget that, for units we own, predicts slow
  projectiles (artillery shells, missiles) heading at them and issues a short perpendicular move. It
  would also keep a minimum spacing in squads that face enemy AoE (artillery, area weapons). This has
  to live on the game side and can't be done from the AI scripts.

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
  because their metal income is huge. We keep BARb's energy curve and recover metal efficiency
  elsewhere: the army share, the moho gate and recycling.
- **Team games are different.** Top team players (≤4v4, 25 player-games rated 35+) boom harder: about 34 m/s at minute 5 and 58 at 10 (duels: 25 and 48). They go T2 about **5-6 minutes earlier** (10.6 vs ~16 min), with eco value near 2× army at minute 10 (duels: ~1.5×). Allies share the front, so the planning horizon is longer, and the horizon formula is what has to capture that, not a copied timing. In 1vN, Anarvā has no allies covering it, which points the other way.
- **Unit choices** come from capabilities read at runtime (damage against air, surface and underwater,
  health, range, speed, cost), so a balance patch changes the choice automatically.

## 16. Doctrine: no static thresholds

No hand-picked cutoffs like "if minute ≥ 9 and income ≥ 30". Every decision compares the live marginal
value of its alternatives. Only **game facts** (unit costs, upkeep, extraction, converter rates,
build power per constructor) and plain unit conversions may be constants. The shared model lives in
`Brain::Economist`:

- **Planning horizon H.** The expected remaining game is about the time already played (Lindy),
  scaled by how safe we are (2P/(P+T)).
- **Energy priced in metal** at the converter exchange rate.
- **Investments** are made when their payback is shorter than H. T2 example: (lab + moho upgrades of
  our *actual* extractor count) ÷ (extra metal − upkeep priced in metal). If the enemy has teched while
  we're behind, our T1 army is losing value, which forces the move.
- **Needed power** = known enemy army + the army guessed under seen jammers, divided by our measured
  trade efficiency. Waves gather to it, and production splits between eco and army on our power ÷ needed.

**Tunables that remain** (debt, to be replaced by measured or derived values):
- the opener window (6 min)
- Fortify's heat floor and its distance band
- the Recycler's surplus margins
- Strategic's income conditions
- Intel's eyes heat floor
- the 0.5 wreck fraction
- the Production score shape (range, speed and screening factors)

### Judgment numbers still in the code (debt, to remove)

Removed so far: the turret tier is now the turret with the most power per metal; far wrecks are weighted
by our share of the exchange, trade / (1 + trade).

These are not game facts. They are numbers I chose, so they break the no-thresholds rule until replaced:

- Energy plant lead time assumes half our builders work on it (`workers * 0.5`).
- Our own nuke silo timing (minute 30, 90 metal/s), the Juno and tactical-launcher gates.
- The `infra` list counts buildings of ≥ 250 metal as infrastructure.
- Commander safety values in the configs (time 180, threat 5, radius 2000/1200).
- `CORE_BUILDER_SHARE = 30`, the posture labels' ratio bands (logging only).

Game facts read from unit files (converter rate, 75% conversion level, constructor build rate, build
times, mine and silo costs) are not on this list: they are what the game *is*, and they get regenerated
after a balance patch.

## 17. Starvation is fatal

An energy stall slows every constructor and factory at once, and a metal shortfall stalls production.
Build power must follow metal income.

- Constructor need follows the core's own rule: build power = income × buildpowerRatio. A T1
  constructor is about 4.25 build-speed units (85 workertime).
- **Lesson (b3):** cutting constructors whenever we were behind produced a death spiral: income fell
  from 20 to 8 m/s while BARb grew to 50. Now the economy is only cut while we're *pushed back at home*.
  A deficit far from home keeps the economy growing.
- During an energy stall:
  - Production defers to the core, whose first response is energy.
  - Redirect stops assisting.
  - The moho gate blocks new upkeep.
  - Converters switch off below their storage level.

## 18. Wrecks are the fastest metal

Rez bots (Lazarus, Necro, Legion rez bot) reclaim wrecks, resurrect them into free units, and reclaim
trees and plants for energy. They cost 130 metal, move at speed 78 and have 200 build power.

- **BARb's flaw:** its factory weights almost never build them, and Cortex sends its Necros scouting.
- **Anarvā:** fresh wrecks ≈ half the metal of recent losses and kills (decaying windows). A rez bot
  is built while that pool is worth more than the rez fleet already harvesting it. The lab-to-rez-bot
  map comes from unit facts, because the API can't list build options.

## 19. Redirecting build power, and priority toggles

- **Redirect:** the share of constructor build power that should serve the army equals the army
  deficit. Those constructors get guard (assist) tasks on factories. With a surplus they go back to
  eco work.
- **Limit:** BAR's build-priority toggles are unit commands handled by a game gadget, and the script
  API can't send unit commands. The nearest lever is task priority. Real toggles belong in the same
  game-side widget as dodging (§14).

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

Measured so far:
- **1v1 vs BARb-hard is met** at ≥2:1 on every map type.
- **1v2 is 0–11** across every variant tried: Fortify, commander zone, the economy gates.

Anarvā out-ecoes each BARb individually but not both combined, gets pushed back, and loses the
commander. Almost every remaining lever is blocked by the **script API**, not by the reasoning:

- no unit commands: dodging, explicit commander positioning, focusing one opponent's base or commander
- no feature or vent queries: wreck fields, geothermal
- no per-enemy lists: target priority, snipe targets

CircuitAI is open source (GPL-2.0). The next major lever is a **fork of the C++ core** that exposes
exactly these to the scripts: a unit move/attack command, feature and vent queries, and per-enemy
iteration with type, position and owner. That's a C++ build against the Recoil AI interface, heavier
than scripts and configs, but it's what 1v6 most likely needs. A game-side companion gadget covers
whatever the AI interface can't see (projectiles, burn zones).

## 22. How humans beat several hard BARbs (solo replays)

Six public replays of **one human alone, no allied bots, against 3–14 hard or hard-aggressive
BARbs**. **Correction:** three of the six were free-for-all, with each bot on its own team, so the bots also
fought each other (MR_Okay and BRICS_PLUS on Greenest Fields, the Oort Cloud game). The truly allied
1vN games are Knizek (vs 4 hard-aggressive, Ancient Bastion, a walled base map), NoviceKing99 (vs 3 hard,
Shore to Shore) and FloBoo (vs 8, Full Metal Plate, a flat all-metal map). Edict (vs 2 on Comet Catcher),
Gundlach (vs 4, Ring Atoll) and Refrog (vs 2) are queued for playback. The table mixes both kinds; the
boom pattern holds in the allied games too, but the army ratio is lower in FFA,, played back headless and measured every minute (`tools/fetch_vsbots.py`,
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
- **Anarvā today:** about 1.3× one bot's income, 1–3 points short of what the humans reach. That gap,
  not the army, is what to close first.
- **`F_BOOM`** (constructors vs army scale on *pressure*, home losses relative to a minute of income,
  not on enemy presence) went 0–6 in 1v2. Booming alone isn't enough: the AI booms but its economy
  doesn't grow like the humans' does. Next: find *what* the humans build to get 2–3× (constructor
  count, converter and advanced-extractor timing, rez bots) and compare it minute by minute with
  Anarvā's new `[ANV] eco` log.

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
investment starves everything else (§17). The payback-based tech gate (`F_TECH`) already uses
time-to-finish; the eco chooser must do the same for power plants.

## 25. High ground and chokepoints

High ground is a real advantage in BAR:

- **Range.** Ballistic weapons (plasma cannons, artillery) gain range when they fire downhill.
- **Sight.** Elevated units and turrets see further over ridges.
- **Cover.** Terrain blocks direct fire from below, while the defender shoots down over the crest.

The map analysis (`tools/analyze_maps.py`) finds, for every start position, the narrowest stretch on our
half of the route to the farthest enemy (our choke) and the highest passable ground within ~500 elmos of
it on our side. Glacier Pass: chokes 160–224 wide with high ground 150–190 elmos above them. Colorado: a
32-wide choke with high ground 275 above.

**`F_TERRAIN` (on):** while we can't win an open fight, or whenever we're outnumbered (1vN), Anarvā
builds the best turret its economy allows on that high ground and dragon's teeth across the choke mouth.
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
  minus risk. The Director compares the options; no module wins by being earlier in a rule list. This
  is why there are no static thresholds: a threshold is a frozen priority.
- **Value depends on what comes next.** A target's worth includes what killing it enables. The radar
  that sights for a turret line, the anti-nuke that covers the base, the AA screen over the eco: each is
  worth the follow-up it opens, not its own cost. Sequenced attacks are an argument in several moves
  (issue: attack sequencing).
- **Refusing a fight can win it.** Giving up extractors to keep the army, when help or a better
  battlefield is coming, is a present loss for a later gain. The recall and HOLD/TURTLE postures are
  the start of that; the value of territory has to be weighed against the army that defends it.
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
| Constructors for expansion | free extractor spots on our share of the map, spot spacing, constructor speed | n* = F·√(s·t / 2c) (F_EXPAND; worse in 1v3, off) |
| Rez bots | wreck metal on the map: everything that died × wreck share, far fights at half | one more while pool > fleet cost + one bot (F_REZ; testing) |
| Converters | spare energy that would be thrown away | as many as the spare runs, the type with the fastest payback incl. build time (F_CONVERT; off) |
| Turrets at the choke | enemy force projected at us; the army deficit | one per attack (on); metal deficit (F_DEFSIZE; worse, off) |
| Nanos | metal overflowing storage | (F_WASTE; off) |
| Build power overall | metal income × the Director's scale | core rule, scaled by surplus/deficit (on) |

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
  worse (F_DEFSIZE, off).
- **Limit:** the script can't list enemy units with positions, so arrival time can only be estimated
  (path length ÷ speed, radar contact via losses near home). Exact contact timing needs the C++ path
  (§21).

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
- Implementation: F_COMMFWD (extractor claims by gain - risk), F_COMMFOG (unseen strength counts as
  danger), next: the forward post (value = the vision it gives, see issue #48, plus the spots it holds).

## Planned

- Walls and dragon's teeth at chokes, in front of defence lines (Sun Tzu's terrain chapters; HOLD and
  TURTLE).
- Holding chokepoints with static defence in 1vN.
- Feints: a raid on one flank before the main wave hits another (I.20, "hold out baits").
- Production that picks the next unit by cost-effectiveness against the scouted composition.
