# Spectator summary: swe151-155 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Changes under test, both for construction turrets (armnanotc): (1) a build-power job whose `[ANV-BPVAL]` V <= 0 is no longer picked (in swe145 the first constructor took a turret at `V -275`); (2) a turret site must be within the turret's build distance of the factory (issue #122).
Per-game notes: [swe151](swe151.md), [swe152](swe152.md), [swe153](swe153.md), [swe154](swe154.md), [swe155](swe155.md). No `ERR  :` line in any game. Start (1216, 3408) and the opener to the lab (2 extractors, 1 solar, armvp ordered 38 s, up 59 s) are identical in all five.

| game | stop | stat (ours vs BARb) | turrets built / reclaimed | 1st con's 1st job (V) | mex 3:00 | con 3:00 | m_inc 2:00 | army 2:00 | m_inc 3:00 | army 3:00 | m_inc 4:00 | army 4:00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| swe151 | 5:00 | army+buildings 3504 vs 3980 | 1 (197 s) / 0 | armnanotc (V 1995) | 4 / 3 | 3 / 4 | 6.6 / 8.9 | 0 / 129 | 11.2 / 8.9 | 256 / 215 | 11.2 / 15.8 | 521 / 484 |
| swe152 | 5:00 | metal income 13.5 vs 18.1 | 1 (298 s) / 0 | armmex (turret V -282 excluded) | 6 / 4 | 3 / 4 | 6.6 / 8.9 | 0 / 43 | 15.8 / 11.2 | 386 / 215 | 11.2 / 15.8 | 747 / 430 |
| swe153 | 3:00 | metal income 8.9 vs 13.5 | 0 (1 unfinished) / 0 | armnanotc (V 1715) | 3 / 5 | 3 / 4 | 6.6 / 8.9 | 0 / 129 | 8.9 / 13.5 | 220 / 215 | - | - |
| swe154 | 3:00 | metal income 8.9 vs 11.2 | 0 (1 unfinished) / 0 | armnanotc (V 1891) | 3 / 4 | 3 / 4 | 6.6 / 8.9 | 0 / 129 | 8.9 / 11.2 | 166 / 215 | - | - |
| swe155 | 3:00 | army 166 vs 386 | 0 (1 unfinished) / 0 | armnanotc (V 62) | 3 / 4 | 3 / 2 | 6.6 / 6.6 | 0 / 266 | 8.9 / 11.2 | 166 / 386 | - | - |
| **median** | **3:00** | | 2 built in 5 games / 0 | | **3 / 4** | **3 / 4** | **6.6 / 8.9** | **0 / 129** | **8.9 / 11.2** | **220 / 215** | 11.2 / 15.8 (n 2) | 634 / 457 (n 2) |
| swe141-145 median | 3:00 | | | | 3 / 5 | | 6.6 / 8.9 | 225 / 86 | 8.9 / 12.3 | 476 / 215 | 6.6 / 18.1 (n 2) | 791 / 670 (n 2) |

## What the five show
- **Fix (1) did what it says, and only that.** The one time the turret's value was negative at the first constructor's pick, it was excluded: `[ANV-BPVAL] f=2809 armnanotc ... gain 0.0 ... V -282` -> `[ANV-PICK] f=2809 armcv#4706 ... 1:armnanotc=1000000000000.00 13:armmex=629.83`, `-> 13:armmex` (swe152). That game had the best 3:00 of the series: 6 extractors vs 4 and m_inc 15.8 vs 11.2. In swe151, all five post-build values were negative (V -63..-411) and none was picked.
- **The first constructor still took the turret in 4 of 5**, because its value is positive whenever the lab queue waits: `overflow 3.2-3.6 ... gain 3.2-3.4 ... V 1715-1995` (swe151/153/154), `overflow 3.3 ... gain 0.5 ... V 62` (swe155). The overflow comes from two armcv queued while metal is at ~190 and falling to 0. In swe153/154/155 the turret was **still unfinished at the 3:00 stop** (`[ANV-JOBS] t=3m armmex:1 armnanotc:1`, metal `banked=0`), 85-89 s of the only early constructor for nothing. In swe151 it took 104 s (93 -> 197 s).
- **swe152 shows a flip-flop**: armcv#4706 alternated `-> 1:armnanotc` / `-> 13:armmex` 5 times between f=3936 and f=6384 while walking from (1906,3385) to (2254,3071). There were 16 turret picks before one went up at 298 s.
- **Fix (2) can't be read from the logs.** Only 2 turrets were built in five games, no `Nanos: reclaiming` line and no [ANV-BUILDFAIL] armnanotc, but the turret's site and its distance to the lab are not logged. Issue #122's case (6 turrets, 1 in reach) did not come up.
- **Army 0 at 2:00 in all five** (BARb 43-266). In every game the lab built `armcv` twice (f=1793-1805 and f=2729-2765) before its first combat unit (f=3629-3877). In swe141-145, 2 of 5 had armstump first and army 225 at 2:00. A corgator killed a solar 147 from base at 184 s (swe155, stopped on army 166 vs 386).
- Energy dipped at 2:00 in 4 of 5 (`energy=STALL 12.6-115.9/s short`, bank 0-1) and was full by 3:00 (1366-1402). The 3:00 check is `metal=STALL` in 4 of 5.
- Fights: every [ANV-FIGHT] `enemy metal killed meanwhile 0`; kills 0 in all five. Extractors lost to corak at 201-232 s (swe151: 1, swe152: 2). Scouts: 4 armfav died together in BARb's base (swe151, 275-277 s), and swe152's lab built 17 armfav at the end. A huge number in swe155: `[ANV-PICKET] armart ... = 163219 > its value in the army 89821` with 166 metal of army.
- [ANV-CPU] max 134-139 ms at 1:00 (start search), 35.9-52.1 ms at 3:00, 82.9-83.7 ms at 5:00 (swe151/152, above the 33 ms budget).

## Sight gaps across the five (truth `[HARNESS] team=1` vs Anarvā's own log)
| t | BARb truth (median) | Anarvā knew (all five) | player access |
|---|---|---|---|
| 1:00 | army 0, mex 2, lab 0 (swe155: vehicle plant, static 550) | `seen: none`; AWARE `seen last minute 1.00 of the map` | Nothing missed. The 1.00 is an artifact: `Scout::lastSeen` starts at 0 (brain.as:1075), so every cell reads as seen for 60 s. |
| 2:00 | army 129 (43-266), mex 3, con 2, lab 1 | `seen: none`, `enemyArmyKnown=0`, PROD `S air/surf 0/0 E 0/0`, `spots 2 ours 0 theirs seen`, `seen last minute 0.00-0.04` | Not in sight (army 0, no scout before f=4285-5305). **Inferable**: Anarvā's own model says `their lab expected when ours stood (60 s): earliest raid 109 -> 152 s`, yet it doesn't feed the army estimate the lab and PROD read. |
| 3:00 | army 215 (215-386), mex 4 (3-5), con 4 | enemyArmyKnown 0-120; `theirs seen 0` in all five | Partly in sight (1 raider); the rest is inferable from the time. |
| 4:00-5:00 | army 430-1065, mex 6-9 | swe151 `enemyArmyKnown=3098` (counts the seen corcom at cost) vs 820; swe152 `=86` vs 1065; `theirs seen 2-3` vs 6-9 | Inferable from BARb's time and the income shown by its seen extractors. |

### Missing to the bot (script blindness, collected)
1. **Expected unseen enemy army** from the time and the enemy lab's expected start (all five; at 2:00 it reads 0 vs 43-266, the minute the lab picks its second constructor). The raid-time model already exists in [ANV-OPEN].
2. **Expected enemy extractor count / income** from the time (all five; `theirs seen 0` through 3:00 vs 3-5).
3. **Enemy army later from what was seen** (swe152 at 5:00: known 86 vs 1065, with seen extractors and time pointing higher).
- Not blindness, but readings to fix: `enemyArmyKnown` includes the enemy commander (swe151, 3098), and `seen last minute` reads 1.00 in the first minute.
- Not available to a player either: which plant BARb chose before a scout (swe155 corvp; Anarvā's raid model assumed corlab/corak).

## Rework first
1. The turret's value at the first constructor's pick rests on lab overflow from a queue that metal can't pay (`overflow 3.2-3.6` with M 190 -> 0). Count only the overflow that income can fund, or set the turret against the extractors it delays (each extractor's yield over the turret's horizon, metal-equivalent). 3 of 5 games ended with that turret unfinished.
2. Log the turret's site and its distance to the factory, so fix (2) can be checked.
3. Lab: two armcv before any unit, army 0 at 2:00 in all five; feed it the expected enemy army (Missing 1).
4. Army use is unchanged: 0 kills in five games.
