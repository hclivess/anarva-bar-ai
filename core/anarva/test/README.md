# Terrain field checks

`bash core/anarva/test/run.sh` — needs a C++17 compiler and nothing else.

Until now the only way to verify anything in the core was to compile the whole engine and play a
game (see the note on AngelScript in the root README). The terrain fields are plain arithmetic over
a grid, so they can be checked directly, and that is worth doing: the two bugs below were found this
way and neither would have been visible in a game.

## Why there are stubs

`AnarvaTerrain.h` reads four things from the core — the movedef's slope and depth limits, the live
height map, the live slope map and a def's footprint — and nothing else. `stub/` supplies exactly
those, with the same signatures as the real headers at the pinned CircuitAI commit (`f4a6ca3`):

| stub | stands in for | what the test controls through it |
|---|---|---|
| `terrain/TerrainData.h` | `SMobileType`, `SAreaData`, `CTerrainData` | movedef limits, height map, harmful/void water |
| `terrain/TerrainManager.h` | `CTerrainManager` | map extent, movedef lookup |
| `spring/SpringMap.h` | `CMap` | the slope map |
| `unit/CircuitDef.h` | `CCircuitDef` | `GetMoveXSize()`, `GetMobileId()`, `IsAbleToFly()` |

So the tests drive terrain drawn as a picture — `.` passable, `#` impassable, one character per
8-elmo square — and check values worked out by hand.

A passing run here does **not** prove it compiles against the real headers; only
`tools/build_dll.sh` or the `core` workflow does that. It proves the arithmetic is right, which is
the part a game cannot show you.

## What the checks pin down

- clearance is the Chebyshev distance to ground the unit cannot stand on, in elmos
- a Flea fits through a gap its footprint allows and a 56-elmo unit does not, from
  `GetMoveXSize()` alone (`clearance >= xsize / 2`, the engine's own half-size)
- two halves of a sealed map are not the same ground, and no route is reported across it
- the approach width follows the widest way through, and drops when that way is sealed
- the same ground reads differently for a movedef at the bot tier (0.41) and the vehicle tier
  (0.161) — the per-unit answer the old map table could not give

## Two bugs these caught

1. The maximin sweep seeded the source square with its own clearance, so a base in a map corner
   reported every route off the map as one square wide. How much room a unit has where it already
   stands says nothing about the way out, so the source is now seeded wide open.
2. `Narrowest` returned the first square matching the route width rather than the narrowest one on
   the route.

## Known limit

`Narrowest` names *a* tightest square on the route, not necessarily the choke. At a clearance of one
square, a two-square gap and a square merely tucked against a wall are identical in room, and one
check documents that. Telling a separating pinch from a cramped square needs a cut test — does
removing it disconnect the two sides — which the component field makes cheap but which is not
written yet.
