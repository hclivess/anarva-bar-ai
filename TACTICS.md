# Anarvā — tactics

[STRATEGY.md](STRATEGY.md) covers what to invest in and when. This file covers **how fights are won**:
what an army is made of, when it engages, how it moves and what it shoots. The same doctrine applies:
no static thresholds, every choice comes from live game facts and measurements.

There are no feature flags any more (folded into the code, commit 5e66eba). Status labels say where a
behaviour lives: **script** = `Anarva/stable/script/anarva/misc/brain.as`; **core** = the C++ patch
(`core/circuitai.patch`, branch `anarva129`); **partial** = only part of it is built; **limit** = needs a
game-side widget or gadget; **planned** = not built yet. Since the rework Anarvā has not yet won a
full-length 1v1 against BARb hard (see the [README](README.md) status).

## 1. Composition: Lanchester, sight and reach (script: `Brain::Production`)

`Brain::Production::Score` / `MeasureArmy`.

- **Lanchester square law.** A force's fighting strength grows with its total damage × total health.
  The marginal value of adding a unit with (damage d, health h) to an army with (D, H) is
  `d·H + h·D + d·h`, per metal. So the chooser buys whatever the army lacks: damage for a tanky army,
  bodies for a glass cannon. Damage counts only where it can land, weighted by the scouted enemy mix of
  air, surface and underwater.
- **Reach.** A unit that extends our damage-weighted range fights on our terms. Against enemy
  defences (seen static threat) reach is worth more, since outranging turrets is how they die cheaply.
- **Sight.** If the army outranges its own sight, it can't use its range. Units with long sight close
  that gap and gain value in proportion to it. Radar isn't enough: blips carry no type, and range
  without sight is wasted (STRATEGY.md §10).
- **Screening.** Against heavy or artillery armies, health per metal (relative to our army's) soaks
  expensive shots, so cheap bodies gain value.
- **Air exposure.** Aircraft gain value by how much worse the enemy shoots air than ground (their surface
  damage ÷ their air damage, from the enemy units we know of).
- **Pick.** Among the candidates, the one furthest below its target share (its share of the scores) in
  metal built so far is built next: largest deficit, no dice.
- **Time.** A unit is worth the share of the planning horizon it actually spends fighting:
  `1 − travel time to the front ÷ horizon`. Slow units are discounted when the front is far or the
  horizon is short.
- **Abilities, not names.** Every input is read from the unit defs at runtime, so balance patches
  change the choice automatically.

## 1b. Armor classes and projectile speed (partial / limit)

- **Armor classes.** BAR weapons deal different damage per armor class (commanders, vtol, subs,
  shields, nanos, standard…). The core folds this into each unit's threat-damage **per domain** (air,
  surface, underwater), and the chooser weighs exactly that. Finer per-class tables are not exposed to
  the script. The companion widget can read them from the weapon defs.
- **Projectile speed.** Not exposed to the script, and BARb's threat model ignores it. As a proxy in
  the composition, slow shells miss moving targets: against an artillery-heavy enemy, unit speed gains
  value in proportion to the artillery share. The core patch's dodging uses the shooter's shot speed and
  flight time (§7).

## 1b2. Tactical units: EMP, crawling bombs, utility (partial: EMP and crawling bombs in `Production::Score`)

Their value isn't damage × health, so the Lanchester score undervalues them. BARb mostly hides them:
it gives crawling bombs a raider/scout role with limit 2, and cuts paralyzer units' threat to
0.05-0.2.

- **EMP** (`armspid` spider, `armstil` bomber, `corbw` drone; paralyzer weapons). A stun is worth the
  enemy firepower it switches off times our damage that lands freely meanwhile. Value ∝ the enemy's
  heavy/super/commander share × our army's damage.
- **Crawling bombs** (Tumbleweed `armvader` at 65 M, `corroach`, `corsktl`, Legion snapper). Cheap
  metal traded for area damage. Value ∝ the enemy's static and heavy share (clumped, slow, defensive
  lines), plus speed against artillery armies.
- **Utility** (radar bots, spies, decoys). Value comes from the information or deception they add,
  tied to the sight-gap term and jammer intel.
- **How:** the script can't read weapon flags (paralyzer, kamikaze), so a facts table generated from the
  unit files (`facts.as`: EMP and crawling-bomb unit lists, build options) feeds these units into the
  candidate list. In the code: EMP units add (enemy heavy share × their share of our army), crawling
  bombs add (enemy static + heavy share × their share). Utility units have no value term yet.

## 1d. Seeing what the player sees (partial: C++ bridge; companion gadget planned)

Correct decisions need everything a player sees.

- **The core already sees:** wrecks and features (reclaim values; used by reclaim and resurrect
  tasks), enemy units in LOS and radar, and terrain. Engine pathfinding routes around blocking
  wreckage, and build placement avoids occupied ground.
- **The script layer now gets, through the core patch's bridge:** the enemy list (position, velocity,
  type, cost, health, build progress, LOS/radar flags, ids), enemy groups, wrecks (position, metal,
  resurrectable), metal spots (income, open or taken), our line of sight, elevation, threat at a point,
  and what each energy plant really makes on this map.
- **Still missing:** projectiles in flight, burn zones, geo vents.
- **Plan:** a companion game-side gadget that answers the AI's queries over the existing `CallRules`
  channel for what the AI interface can't see: projectiles, napalm areas, geo vents.

## 1d2. Transports (limit: needs unit commands)

Air transports can carry **every unit, including defence towers, nano/construction turrets and the
commander**.

- relocate a defence line or nanos to a new front or choke
- rescue the commander from danger
- move the commander far faster to expand, escape, or reach a forward build site
- drop raiders behind enemy lines

The core has a transport role but barely uses it, and directing a transport needs unit commands. So
this belongs to the C++ fork (STRATEGY.md §21), with commander airlift as a top-priority use. The fork
exists, but transport use is not built in it yet (planned).

## 1e. Map analysis before the match (script: `mapfacts.as`, read by `Production::LookAtMap`)

A pro reads the map first. `tools/analyze_maps.py` reads each map archive offline (height map, metal
map, mapinfo) and computes:

- extractor spots, and how many lie on each side
- the base-to-base path distance, compared with the straight line (how winding it is)
- the narrowest sustained corridor on that path (choke width)
- the water share
- start positions

It writes `mapfacts.as`, which the AI looks up by map name at game start. Examples: Avalanche is open
(width 1.4k); Glacier Pass is a winding choke (path 2× straight, width 160); Comet Catcher sits in
between (736).

**Uses:** the choke and high ground for terrain fortification (STRATEGY.md §25). Intended further uses:
travel time (the composition time term now uses the measured front distance instead), expansion
potential, and whether naval is needed (planned: `brain.as` reads only the terrain fields and logs the
rest).

## 1c. Legion napalm (planned / limit)

Legion napalm leaves burning ground that keeps damaging everything standing in or walking through it.

- **Area denial over time:** clumped blobs and slow units suffer most. Waves shouldn't path through
  fire.
- **Composition (planned, stats only):** against napalm-heavy Legion armies, weight speed and health
  per metal (pass through fire quickly), and range that outreaches the fire.
- **Limit:** burn zones are gadget effects the script can't see. Routing around them belongs in the
  companion widget (§7).
- **Test gap:** the harness runs with Legion disabled (it's behind a modoption), so Legion matchups
  still need their own test pool.

## 2. Concentration and engagement (script: `Brain::Director` sets the core's attack quota)

- **Waves gather to the power needed to win:** known enemy army (summed per known enemy unit) + the army
  guessed under jammers, divided by our trade efficiency. The core's attack quota is set to that every
  update, with no config floor. When we're much stronger the quota fills quickly; when we're weaker,
  nothing launches into a losing fight and units stay home. (The earlier F_WAVES/F_QUOTA version was
  measured net negative; it no longer exists as a flag.)
- **Just-in-time defence** (`Brain::Hold`): each armed enemy is assigned to the asset it is closing on
  soonest; the asset gets a defend task sized to that threat, filled by the units that can be there
  first, or none if they can't win it in time.
- **Target group choice** is the core's: our wave compares itself with each enemy group's influence.
  Jammer clusters look defended, so weak waves skip them.
- **Pick fights at home when outgunned** (`Brain::Strategic::Fortify`): with map facts, turrets on the
  high ground plus dragon's teeth (and mines) across the choke (STRATEGY.md §25); without them, a turret
  covering the cell where we lost the most metal, when that loss beats the turret and it would survive
  there. Attackers stall under fire (Sun Tzu: let the enemy come to ground you have prepared).

## 3. Disengage at the culminating point (script: `Brain::Army::CheckSquads`)

A squad is recalled once it has bled (below its peak power) and what is left, at our trade rate, is
weaker than the quota a fresh squad is sized against, which is the needed power and falls as we kill. A
squad that's trading well keeps fighting. A losing squad comes home and merges into the next wave instead
of trickling in. Raids in particular used to continue until their *leader* died.

## 4. Raids (script: raid quota in `Brain::Director`; greedy-enemy punishment planned)

- A raid pack must beat the enemy raiders that will answer it: the raid quota is their raider threat ÷
  our trade rate.
- Raiders go after eco and builders, steered by the core's threat map away from defences. Scouts look
  for unwatched enemy extractors to raid (`Brain::Scout`, #74).
- A greedy enemy (lots of buildings, little army) should get punished; the current code has no rule for
  it.

## 5. Information in combat (script: `Brain::Scout`, `Brain::Intel`)

- **Scouting by the value of vision** for real sight (no timers): cells long dark near our assets or
  likely holding enemy extractors are worth looking at, and the scout quota is the number of cells worth
  more than a scout (STRATEGY.md §10). Dragon's Eyes go where we die unseen.
- **Fire from the fog.** When hit by something unseen, the core projects the shooter's type and
  position back along the shot (phantom enemies). We add jammer clusters treated as defended, a loss
  heatmap, and Junos to clear jammers and radar.

## 6. Target priority (core: switch `focusFire`)

- **We steer:** which enemy *group* a wave commits to; ignore flags (T1 spam once we field T3; decoy
  commanders, handled by the core: status unverified).
- **Per-shot targeting** (core patch, switch `focusFire`, set on by `brain.as`): each squad unit focuses
  the visible enemy in its own range whose removal cuts the enemy's firepower most per point of damage
  spent (threat ÷ remaining health), counting what its death blast takes with it (#44). This is "kill the
  artillery before the Pawns" by Lanchester; it no longer needs a gadget.

## 7. Projectile and AoE evasion (core: switch `strafe`; partial)

- Slow projectiles (artillery shells, missiles) can be sidestepped, and splash weapons punish clumps.
- **In the core patch:** a shot is dodgeable when its flight time (distance ÷ shot speed) × our speed
  exceeds its blast radius plus our size. A squad unit's spot moves sideways by what it covers in one
  flight time against the most threatening dodgeable shooter, switching side every flight time. Beams
  are not dodged. Squad spacing comes from splash geometry ([AUDIT.md](AUDIT.md)).
- **Still a limit:** seeing actual projectiles in flight, and the build-priority toggles (gadget
  commands), need a companion LuaUI widget or gadget.

## 8. Time on the battlefield (partial / planned)

- **Done:** travel time discounts slow units in the composition (§1). Waves launch together, so no
  one walks alone.
- **Planned:** front labs and rally points. A forward lab saves (travel time × production rate) of
  army presence, against the risk measured from threat and loss heat at the site.

## 9. Spending under fire (script and core)

- **Energy stall:** production defers to the core (`Production::MakeTask`), and the core's builder
  ranking prices binding energy at our spending ratio, so energy comes first. Assists stop
  (`isAssistRequired`, `manager/economy.as`). Extractor upgrades are bought only when they pay their
  upkeep at the converter price.
- **Constructors follow open extractor spots** (claim walking time over the horizon), and only while
  we're not weaker than the enemy army we know of; otherwise army comes first (`Brain::EcoPos`,
  STRATEGY.md §17). The older "cut only while pushed back at home" rule is not in the code.
- **Redirect:** the script's army-deficit Redirect is gone. Assisting a factory competes with every other
  builder job on the core's payback-time ranking, and threatened builders fall back to assisting the
  factory they reach soonest (`Brain::BuilderSafeUpdate`).
