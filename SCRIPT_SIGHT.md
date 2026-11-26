# What the script can see

Owner, 2026-11-26: "cover any gaps you may come in contact with - you already did 3 rounds, always finding more
script blindness". A decision is only as good as the facts it can read. When a decision needs a fact the script can't
see, expose it right then (bridge in `script/InitScript.cpp`, unit facts in `misc/facts.as` via `tools/gen_facts.py`)
and record it here. A blind spot is fixed when first met, not worked around.

## How to find gaps

- When tracing a bad decision (PROCESS.md step 4), ask what the player looked at that the script couldn't. If a value
  is estimated from a proxy (radius for footprint, a name list for an ability), the real fact is probably available.
- Compare the core's accessors with what is registered:
  `python tools/sight_audit.py` lists every `CCircuitDef` getter not exposed to the script.
- Log the inputs of every decision. An input that shows `0` or `-` in a log line is often a blind spot. Example: a
  reclaim job's value read 0 because the core never passes it.

## Exposed (date, the decision that needed it)

| Fact | Script name | Exposed | Needed by |
|---|---|---|---|
| weapon splash radius | `def.GetAoe()` | 2026-11-26 | unit strength vs massed small units (44 Pawns lost to Pounders) |
| projectile speed | `def.GetShotSpeed()` | 2026-11-26 | hit chance against moving targets (dodging) |
| shields | `def.GetShieldRadius()`, `def.GetMaxShield()` | 2026-11-26 | strength of shielded groups |
| what a weapon can target | `def.HasSurfToAir/Land/Water()` | 2026-11-26 | who can hit whom |
| stealth, cloak | `def.IsStealth()`, `def.IsAbleToCloak()` | 2026-11-26 | hidden enemy strength |
| amphibious, jump range | `def.IsAmphibious()`, `def.GetJumpRange()` | 2026-11-26 | who can cross water and cliffs |
| footprint | `def.GetMoveXSize()` | 2026-11-26 | squad spacing (splash) |
| builder abilities | `def.IsAbleToRepair/Reclaim/Resurrect()` | 2026-11-26 | rez bots and builders, without name lists |
| a job's decision value | `task.value` | 2026-11-26 | towers and evacuations competing on value |
| a job's metal and energy (a wreck's, for reclaim) | `task.GetCostM()`, `task.GetCostE()` | 2026-11-26 | rez bots' evacuation (their jobs counted 0) |
| game chat | `AiSay(text)` | 2026-11-26 | telling a watching player which side is Anarvā |
| wind as it blows | core `GetWindMean/Low/LullShare` | 2026-11-25 | turbine value, lulls |
| damage per enemy type: dealt us / we dealt it, and totals | `AiDamageFrom(type)`, `AiDamageTo(type)`, `AiDamageFromAll()`, `AiDamageToAll()` | 2026-11-26 | exposed; a live enemy threat from it (cmd_m122) made the army shy and was reverted - unused for now |
| damage taken / dealt per our unit type (live trade) | `AiDamageReceived(type)`, `AiDamageDealt(type)` | 2026-11-26 | unit choice: corrects the modelled trade by the live one (Pawns x0.13 vs Levelers) |
| smoothed metal spend | `AiSmoothMetalPull()` | 2026-11-26 | metal price in the script (constructor value, reclaim): the share of income + bank we spend |

## Still blind (open)

- **hits taken by our unit types from each enemy type** (damage events: attacker def, victim def, damage) - to replace the modelled dodge (HitChance) with what this game shows; Levelers killed 130 Pawns the model said dodge half their shots (cmd_m75).

| Fact | Where it would come from | Decision it would improve |
|---|---|---|
| armour classes and damage per armour type | unit files (`weapondefs.damage`), via gen_facts | matchups (light vs heavy vs air) |
| weapon accuracy, spread, reload vs burst | unit files, via gen_facts | effective dps against small and fast units |
| splash falloff (edge effectiveness) | unit files | splash damage away from the centre |
| paralysis (EMP), slow, veterancy | unit files, unit state | strength of EMP units, veteran units |
| the enemy army we can't see | estimate from their income and time (not a fact) | fights against a mostly unseen army (we saw 1-15 units of 5000+ metal) |
| the core's remaining unit getters | `CCircuitDef` (run `tools/sight_audit.py`) | as needed |
