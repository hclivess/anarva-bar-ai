# Spectator summary: swe141-145 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Change under test: the energy planner counts the energy bank net of what the builders' current jobs will still draw (an extractor costs 500 energy), to stop the 2:00-3:00 energy stalls that ended swe136, swe138 and swe140 ([summary](swe136-140-summary.md)).
Per-game notes: [swe141](swe141.md), [swe142](swe142.md), [swe143](swe143.md), [swe144](swe144.md), [swe145](swe145.md). No `ERR  :` line in any game.

| game | stop | stat (ours vs BARb) | e bank 2:00 | e bank 3:00 | m_inc 2:00 | army 2:00 | m_inc 3:00 | army 3:00 | m_inc 4:00 | army 4:00 | mex 3:00 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| swe141 | 4:00 | metal income 8.9 vs 18.1 | 211 | 800 | 8.9 / 8.9 | 256 / 86 | 11.2 / 13.5 | 555 / 215 | 8.9 / 18.1 | 775 / 691 | 4 / 5 |
| swe142 | 3:00 | metal income 8.9 vs 13.5 | 244 | 1342 | 6.6 / 8.9 | 225 / 86 | 8.9 / 13.5 | 366 / 172 | - | - | 3 / 5 |
| swe143 | 4:00 | damage share 0.06 vs 0.94 | 228 | 777 | 8.9 / 8.9 | 256 / 86 | 11.2 / 12.3 | 586 / 172 | 4.3 / 18.1 | 806 / 648 | 4 / 5 |
| swe144 | 3:00 | metal income 8.9 vs 11.2 | 151 | 1332 | 6.6 / 8.9 | 225 / 43 | 8.9 / 11.2 | 476 / 215 | - | - | 3 / 4 |
| swe145 | 3:00 | metal income 8.9 vs 11.2 | 143 | 1310 | 6.6 / 8.9 | 225 / 86 | 8.9 / 11.2 | 445 / 258 | - | - | 3 / 4 |
| **median** | **3:00** | | **211** | **1310** | **6.6 / 8.9** | **225 / 86** | **8.9 / 12.3** | **476 / 215** | 6.6 / 18.1 (n 2) | 791 / 670 (n 2) | **3 / 5** |
| swe136-140 median | 3:00 | | 1 | 1 | 6.6 / 8.9 | 225 / 129 | 11.2 / 13.5 | 476 / 215 | 11.2 / 20.4 (n 2) | 743 / 553 (n 2) | 4 / 5 |

## What the five show
- **The change did what it was meant to.** The commander's first pick after the lab is now a solar in all five (swe141/143: `f=1793 ... -> 4:armsolar | 4:armsolar=9.47 13:armmex=30.99 | ... ePullReal 88`; swe142/144/145 flip from armmex to armsolar within 2-4 frames), where swe136/140 took the extractor with solar not even a candidate (`f=1809 ... -> 13:armmex | 13:armmex=25.63 | ... ePullReal 47`). First plant after the lab 74-78 s in all five (swe136-140: 73-123 s). Energy bank at 2:00 median 211 (was 1), 3:00 median 1310 (was 1); no `energy=STALL` at any check; the swing's `energy short` is 0 in all five. The only dip is 10-15 s at ~1:17-1:29 (`E 1/1200`..`E 17/1200`).
- **The stall moved to metal, and the stop with it.** `metal=STALL` at 2:00 in 3 of 5 (`25.1/s short ... mex=2`, swe142/144/145) and at 3:00 in all five, with energy at 777-1342 and overflowing by 4:00 (swe141 `energy=WASTE 108.7/s`). Four of five stops are metal income. Metal income at 3:00 fell from a median 11.2 to 8.9; extractors at 3:00 3 vs BARb 5 (was 4 vs 5).
- **Two openings, same start.** The opener to the lab is identical in all five (2 extractors, 1 solar, armvp ordered 38 s, up 59 s). Then the lab's first unit splits the games:
  - armstump first (swe141, swe143): armcv started 101-102 s, up 128-129 s; 3 extractors at 2:00, m_inc 8.9 = BARb; the games ran to 4:00.
  - armcv first (swe142, swe144, swe145): the constructor (up 90-91 s) took a construction turret as its first job (`-> 1:armnanotc | 1:armnanotc=38.12 4:armsolar=3677.22 13:armmex=1055.31 | M 197/1200`, swe144), valued on lab overflow 2.6-3.0 with metal at ~190 and falling. In swe145 it took the turret though its own value line read `[ANV-BPVAL] ... armnanotc ... gain 0.0 ... V -275`; in swe142 it never placed it (`[ANV-BUILDFAIL] f=4757 armcv job 1 armnanotc fails=1 ... canPlace=0`). 2 extractors at 2:00 (BARb 3) and the third from the commander at 145-151 s; stopped at 3:00.
  - Meanwhile the commander built 3 solars in the first minute after the lab (74-91 s and 127-133 s) and its third extractor only at 116-151 s.
- **Army is still ahead and still unused.** Army 2:00 225 vs 86, 3:00 476 vs 215 (2.2x), but `stay home` from ~2:00 to the stop in every game (45-344 lines), `attack=0 raid=0 defend=0` at every check. swe143 lost 3 of 4 extractors in 43 s (205-228 s) to corak with 806 metal of army at home (`seen last minute 0.04 of the map`), every op `target gone ... enemy metal killed meanwhile 0`; swe141 lost 1 (220 s). Scouts (armfav) died in 3 of 5.
- [ANV-CPU] max 134-153 ms at 1:00 (start search), then 9-36 ms (swe141 35.7 ms at 4:00, above the 33 ms budget).

## Rework first
1. The construction-turret pick for the first constructor: its value rests on lab overflow while metal is short; the swe145 pick contradicts its own `V -275`. The constructor's first jobs should be extractors (each extractor's yield vs the turret's, metal-equivalent).
2. The commander after the lab now over-weights energy (3 solars, energy full by 3:00 and wasting by 4:00): the net-of-jobs bank fixed the stall, but energy and metal should be planned together - with the extractors the constructor did not build, the solars had nothing to power.
3. Army use: defend raided extractors (swe143), not only `stay home`.
