# What is in Anarvā (2026-11-25)

The feature flags (`F_*`) were folded into the code, so this file is now written by hand. The old
generator, `tools/gen_features.py`, describes the flag system and is retired. Each line says what the
module decides and from what. The reasoning is in [STRATEGY.md](STRATEGY.md) and [TACTICS.md](TACTICS.md);
replaced constants are listed in [AUDIT.md](AUDIT.md).

Status: none of this has a measured win against BARb yet. Since the rework no full 1v1 has been won; the
first games after it found and fixed a series of economy and strength bugs (issues #81–#88).

## Shared valuation (Economist, Director, Assess)

| What | Computed from |
|---|---|
| **Planning horizon** | the time the enemy needs to build a force worth everything we own (our metal / their income; unseen, each enemy earns as fast as we do) plus the map crossing time |
| **Metal value of a thing** | metal + energy at the converter rate; converters' own draw counts as surplus |
| **Strength** | Lanchester: each unit adds sqrt(dps × health), summed over our armed mobile units including the commander, against each *known* enemy unit counted once. The D-gun adds nothing (it fires only on order). |
| **Trade** | metal killed vs lost, weighted by everything we own |
| **Front** | where our losses happen, weighted by metal lost |
| **Ratio** | our strength / what we must beat (known enemy / trade); 1 when there's nothing to beat |
| **Faction** | from the commander that spawned (with a random side, side-specific init is redone once the faction is known) |

## Economy (core + Economist, EcoPos, Storage, Recycler, Tech)

| What | Computed from |
|---|---|
| **Builder job choice** | seconds until the job pays back at shadow prices (metal 0 while it overflows past what our build power can spend; energy at our spending ratio while it binds or a factory waits for it); jobs without a yield are paid from stock, then income. No priority bands except defence (open, see AUDIT.md). Every pick is logged with the alternatives (`[ANV-PICK]`). |
| **Energy** | queued whenever the need test asks: today's deficit (pull without converters) or the energy needed to spend our metal income at the E/M ratio of what our factories build |
| **Constructors** | enough to claim the unclaimed extractor spots within the horizon (walk + build per spot), only while we are not weaker than the known enemy army |
| **Storage** | metal: only when income exceeds what our build power can spend; energy: when the energy it keeps over the horizon outvalues its cost |
| **Plant reclaim** | only when a plant we can build now (not vent-bound) makes more energy per metal, and energy stays in surplus without it |
| **Unit salvage** | a unit is obsolete when a higher-tier factory we own builds something with more strength per metal |
| **T2/T3** | the upgrade's payback must beat the horizon and the next T1 extractor, unless the lab's cost is already banked; forced when the enemy has teched and we are weaker |
| **Rez lab / rez bots** | a bot lab when no factory of ours can make rez bots and the wreck metal beats lab + one bot |

## Intelligence (Intel, Scout)

| What | Computed from |
|---|---|
| **Grid** | cells one camera's sight across (no camera: the commander's sight) |
| **Scouting** | value of looking at a cell = our metal within reach of what could be hidden there (dark time × enemy speed); scouts go to the best cells |
| **Cameras** | where the loss heatmap shows unseen losses, while a camera costs less than the heat |
| **Jammers** | a seen jammer stands for hidden strength (its metal share of the visible enemy army) |

## Military (Director, Army, Hold, MexPorc, Strategic, core tasks)

| What | Computed from |
|---|---|
| **Attack quota** | the power needed to beat what we know of, at our trade rate |
| **Extractor hold** | each armed enemy is assigned to the extractor it is closing on soonest; units that can get there first are committed only if they can beat it in time |
| **Outer extractor turret** | when the metal lost near it beats the turret's cost and the turret would survive |
| **Terrain defence** | turrets on the high ground over our choke (map analysis) when outnumbered or weaker |
| **Strategic** | anti-nuke when an enemy could have a missile before ours is ready; Juno, tactical/EMP, nuke, shields by value vs cost |
| **Builder safety** | a builder leaves its job when the job's expected gain is less than the risk to the builder and its future work |
| **Commander** | the core picks its jobs like any builder's; the script only decides risk (leave when P(death) × everything we own exceeds the job's gain) |
| **Self-destruct** | crawling bombs and units with a self-destruct blast go off when the blast is worth more than the unit (untested, #79) |
| **Core switches** (all on) | artillery fires from height-aware spots; height-aware squads; scout map; engage seen enemies; focus fire; strafing |

## Facts generated from unit files

`tools/gen_facts.py` → `misc/facts.as`: factory build options and tiers (build depth from the commanders),
paralyzer, crawling-bomb and rez units, extraction, upkeep, converters, stockpile times, shot metal, shield
radius, geothermal-vent units, metal make.

## Open

Every open item is a GitHub issue. The big ones:
- expansion to the winners' pace (one constructor per extractor, second factory by minutes 6–8)
- per-unit counters from the replay damage matrix (#70)
- the army used as an expansion opportunity cost (#84)
- scouting driving the expand / army / attack choice (#85)
- the bomber fake-landing trick (#80)
