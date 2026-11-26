# Spectator notes: swe23 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Live remarks (game time):

- **0:00** Script loads clean (only "unknown UnitDef leg*" config warnings; no anarva ERR). Start chosen (1029,5456), south-west box. Start search scored armvp first at most candidates (lab armvp@159-181 s), armhp at some.
- **0:00-2:00** Opening is commander-only: mex 11 s, solar 27 s, solar 57 s, mex 74 s, solar 86 s, mex 109 s. **No lab placed by 2:00** (winners: vehicle plant at 69-77 s). `[ANV-OPEN] lab values over ~10600-11600 s` (a 3-hour horizon) rank armhp > armvp > armlab every time (e.g. 2:18 `armlab=183942 armvp=198482 armhp=202056`) - hover plant leads on a land map, and whichever leads, nothing gets built.
- **2:00** Floating: M 994/1150, E 1148/1150, army 0, m_inc 8.9 vs BARb 6.6 with 146 metal of army and 13 units vs our 7. A strong player would be screaming "build the lab" - full storage for a minute is pure waste.
- **0:03-2:18** 65 BUILDFAILs, all the commander: solar job failed 11 times in a row (f 841-1426), wind 21 times (f 3348-4122). Every line has `canPlace=1 sitePlace=1` and `cmds=0` - site is legal, the commander simply holds no build command; dist 132-214 against buildDist 145, often vel=0. Not a placement problem: the order is never issued / is dropped while the commander stands still.
- **2:29** First raid: a Cortex Rover-class scout (corfav) kills our extractor at (1376,5344), 430 from base. We have no army to answer.
- **1:50-2:51** `[ANV-OPEN] t=110s/138s commander -> armwin (energy 90/s short of 90 ...)` - the strict energy-first gate holds the lab on a gap of zero; at 171 s it still says "energy 54/s short of 90". Log ends f=5205 (2:53).

## Summary

- **Stopped** at the 2:00 sample (swing.py): buildings 615 vs 840, army 0 vs 146, units 7 vs 13. We floated M 994/1150 and E 1148/1150.
- **What led to it:** no lab at all. Lab values over a ~10400-11600 s horizon (the map crossing priced at army speed 0) ranked hover plant > vehicle plant > bot lab, and the "energy income first" gate (`90/s short of 90`) kept the commander on wind/solar.
- **Lab:** none by 2:53 (winners: vehicle plant at 69-77 s).
- **Failed placements:** 65, all commander, all `canPlace=1 sitePlace=1 cmds=0` at dist 130-215 vs buildDist 145, often vel 0. The site is legal; the build order is not held (missing or dropped). The build-distance change did not stop it.
- **Extractors:** 3 built (11/74/109 s), 1 lost at 2:29 to a corfav. Winners 3 at 2:00 (we match by count, but with no lab or constructor).
- **First raid:** 2:29 corfav, cost one extractor (50 m), nothing to answer.
- **Rework first:** the lab decision (horizon and energy gate). Coordinator has already fixed it in swe24.
