# Anarvā — tactics

[STRATEGY.md](STRATEGY.md) covers what to invest in and when. This file covers **how fights are won**:
what an army is made of, when it engages, how it moves and what it shoots. The same doctrine applies:
no static thresholds, every choice comes from live game facts and measurements.

Status labels give the feature flag and whether it's on by default (see the status table in the README).
**Partial** = what the script API allows; **limit** = needs a game-side widget or gadget; **planned** = not built yet.

## 1. Composition: Lanchester, sight and reach (implemented: F_PROD, testing, leading in round 7)

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
- **Projectile speed.** Not exposed to the script either, and BARb's threat model ignores it. As a
  proxy, slow shells miss moving targets: against an artillery-heavy enemy, unit speed gains value
  in proportion to the artillery share. Real dodging uses projectile speed and flight time in the
  widget (§7).

## 1b2. Tactical units: EMP, crawling bombs, utility (planned)

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
- **How:** the script can't read weapon flags (paralyzer, kamikaze) or a factory's build options, so a
  facts table generated from the unit files (kind, factory) feeds these units into the candidate list
  with their own value terms.

## 1d. Seeing what the player sees (planned: companion gadget)

Correct decisions need everything a player sees.

- **The core already sees:** wrecks and features (reclaim values; used by reclaim and resurrect
  tasks), enemy units in LOS and radar, and terrain. Engine pathfinding routes around blocking
  wreckage, and build placement avoids occupied ground.
- **The script layer does not:** no feature or wreck list, no per-unit enemy list, no projectiles, no
  burn zones, no geo vents. It only gets the core's summaries (threat, groups, costs per role).
- **Plan:** a companion game-side gadget that answers the AI's queries over the existing `CallRules`
  channel. It would report wreck fields (metal, energy, location, blocking), projectiles, napalm areas,
  geo vents, and per-unit enemy composition near a point. It's one piece of infrastructure that
  unlocks dodging, napalm avoidance, geo decisions, wreck-field routing and rez targeting.

## 1e. Map analysis before the match (in progress)

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

**Uses:** travel time (the composition time term), expansion potential (the constructor value),
whether fortifying chokes pays, and whether naval is needed.

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

## 2. Concentration and engagement (implemented: F_WAVES/F_QUOTA, off; net negative so far, being reworked)

- **Waves gather to the power needed to win:** known enemy army + the army guessed under jammers,
  divided by our trade efficiency. When we're much stronger, waves are small and frequent (constant
  pressure). When we're weaker, nothing launches into a losing fight; units defend at home under our
  turrets.
- **Target group choice** is the core's: our wave compares itself with each enemy group's influence.
  Jammer clusters look defended, so weak waves skip them.
- **Pick fights at home when outgunned:** Fortify puts turrets plus dragon's teeth at the hottest front
  cell, so attackers stall under fire (Sun Tzu: let the enemy come to ground you have prepared).

## 3. Disengage at the culminating point (on: first-gen recall rule; need-based variant F_NEWRECALL off)

A squad is recalled once it has bled and is weaker than what we'd send fresh, measured against the
needed power, which itself falls as we kill. A squad that's trading well keeps fighting. A losing
squad comes home and merges into the next wave instead of trickling in. Raids in particular used to
continue until their *leader* died.

## 4. Raids (raid sizing is part of F_QUOTA, off; greedy-enemy punishment off with it)

- A raid pack must beat the enemy raiders that will answer it: their raider threat ÷ our trade rate.
- Raiders go after eco and builders, steered by the core's threat map away from defences.
- A greedy enemy (lots of buildings, little army) gets punished.

## 5. Information in combat (on: jammer intel and eyes; timed scouting F_SCOUT off)

- **Continuous scouting** for real sight, with planes on a timer, plus Dragon's Eyes where we die unseen.
- **Fire from the fog.** When hit by something unseen, the core projects the shooter's type and
  position back along the shot (phantom enemies). We add jammer clusters treated as defended, a loss
  heatmap, and Junos to clear jammers and radar.

## 6. Target priority (partial / limit)

- **We steer:** which enemy *group* a wave commits to; ignore flags (T1 spam once we field T3; decoy
  commanders, handled by the core); per-unit threat weighting.
- **Limit:** per-shot targeting inside a fight is the engine's unit AI, and the script API can't set
  it. "Kill the artillery before the Pawns" needs a game-side gadget.

## 7. Projectile and AoE evasion (limit, design ready)

- Slow projectiles (artillery shells, missiles) can be sidestepped, and splash weapons punish clumps.
- **Limit:** the script API gives no per-unit move orders, and the core doesn't dodge.
- **Design:** a companion LuaUI widget or gadget for the AI's units:
  - predict incoming slow projectiles and issue a short perpendicular move
  - keep a minimum spacing in squads that face area weapons
  - expose build-priority toggles, which are also gadget commands

## 8. Time on the battlefield (partial / planned)

- **Done:** travel time discounts slow units in the composition (§1). Waves launch together, so no
  one walks alone.
- **Planned:** front labs and rally points. A forward lab saves (travel time × production rate) of
  army presence, against the risk measured from threat and loss heat at the site.

## 9. Spending under fire (implemented: F_PROD, F_REDIRECT, F_ECOGATE; testing)

- **Energy stall:** production defers to the core, which answers with energy first. Assists stop. The
  moho gate blocks new upkeep.
- **Build power follows metal income** by the core's own rule. The economy is cut only while we're
  pushed back at home (STRATEGY.md §17).
- **Redirect:** the share of constructor build power that assists factories equals the army deficit.
