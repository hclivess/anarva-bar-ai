# Spectator summary: swe156-160 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Changes under test: (a) spare metal for construction turrets (armnanotc) is the metal bank's signed growth below full storage, so a falling bank means none (swe151-155: the first constructor took a turret in 4 of 5 while metal fell); (b) the enemy army before contact is estimated from their lab, the raiders it has made by now (`RaidExists`, brain.as:3363), instead of 0; (c) `enemyArmyKnown` no longer counts the enemy commander.
Per-game notes: [swe156](swe156.md), [swe157](swe157.md), [swe158](swe158.md), [swe159](swe159.md), [swe160](swe160.md). No `ERR  :` line in any game. Start (1216, 3408) and the opener to the lab are the same in all five (2 extractors, 1 solar, armvp ordered 38-39 s, up 59 s; 64 s in swe159 after `[ANV-BUILDFAIL] f=1294 armcom job 0 armvp`). BARb opened corlab in 156/158/160 and a vehicle plant in 157/159.

| game | stop | stat (ours vs BARb) | turrets built | 1st con's 1st job | mex 3:00 | con 3:00 | mex 4:00 | con 4:00 | m_inc 2:00 | army 2:00 | m_inc 3:00 | army 3:00 | m_inc 4:00 | army 4:00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| swe156 | 4:00 | damage share 0.34 vs 0.63 | 0 | armmex (turret V -288 excluded) | 4 / 5 | 2 / 4 | 4 / 4 | 2 / 4 | 8.9 / 6.6 | 220 / 129 | 11.2 / 13.5 | 550 / 215 | 11.2 / 11.2 | 440 / 452 |
| swe157 | 4:00 | metal income 6.6 vs 18.1 | 1 (180 s) | armnanotc (excluded f=2793, picked f=2821) | 4 / 5 | 2 / 2 | 2 / 7 | 2 / 3 | 6.6 / 6.6 | 251 / 146 | 11.2 / 13.5 | 471 / 386 | 6.6 / 18.1 | 784 / 480 |
| swe158 | 3:00 | metal income 8.9 vs 13.5 | 0 (1 unfinished) | armnanotc (V 1747) | 3 / 5 | 2 / 4 | - | - | 6.6 / 8.9 | 141 / 86 | 8.9 / 13.5 | 440 / 172 | - | - |
| swe159 | 3:00 | energy short 1.00 vs 0.00 | 0 | armadvsol (turret held 13 frames, V 772) | 4 / 5 | 2 / 2 | - | - | 8.9 / 6.6 | 251 / 146 | 8.9 / 12.3 | 471 / 386 | - | - |
| swe160 | 3:00 | damage share 0.39 vs 0.61 | 0 | armmex (turret V -224 excluded) | 5 / 4 | 2 / 4 | - | - | 6.6 / 8.9 | 251 / 129 | 13.5 / 8.9 | 550 / 215 | - | - |
| **median** | **3:00** | | 1 in 5 games | | **4 / 5** | **2 / 4** | 3 / 5.5 (n 2) | 2 / 3.5 (n 2) | **6.6 / 6.6** | **251 / 129** | **11.2 / 13.5** | **471 / 215** | 8.9 / 14.7 (n 2) | 612 / 466 (n 2) |
| swe151-155 median | 3:00 | | 2 in 5 games | armnanotc in 4 of 5 | 3 / 4 | 3 / 4 | | | 6.6 / 8.9 | 0 / 129 | 8.9 / 11.2 | 220 / 215 | 11.2 / 15.8 (n 2) | 634 / 457 (n 2) |

## What the five show
- **(b) changed the lab, through the plan split.** E is no longer 0 before contact, so `sSurf < eSurf` holds and the plan-split override (brain.as:3101) forces a fighter over the constructor that had the better value per metal: `f=2081 ... armflash as fighter ... armcv=25.74 ... armflash=6.85 ... | plan split 0.79: fighter leaves it 29 off, constructor 100` (swe156; the same lines in all five). Army at 2:00 went 0 -> 251 (BARb 129), but constructors fell to 1 at 2:00 and 2 at 3:00 (winners 3 and 5) and extractors at 4:00 to 2-4 (winners 9). The stops moved from "army behind" to "economy behind" (157, 158) or "army unused" (160).
- **(b)'s estimate runs ~3x high from 3:00.** E in strength (a corak reads 143) against the truth: ~1.6-2x at 2:00, 2.4-3.5x at 3:00 (swe156 E 2105 vs 5 corak, swe158 E 2001 vs 4 corak, swe160 E 2071 vs 5 corak with 3 of them in sight). `RaidExists` gives them a raider at min(lab rate, *our* income / raider cost): all their income into raiders, while BARb's lab made 2-4 constructors. Seen units only raise E (`max(seen, model)`), so seeing 3 coraks at 3:00 doesn't lower a 14.5-corak estimate.
- **The first lab pick runs before the lab-time correction** in 3 of 5 (swe156 f=1793, swe159 f=1941, swe160 f=1793, each 7-9 frames before `their lab expected when ours stood`): E 744-829 from the lab-first time, and the first item is a scout (`armfav ... info 6550`). In 157/158 (pick at f=1805) E was 0 and the first item a constructor.
- **(a) works on a falling bank and fails on a rising one.** Excluded where the bank fell (swe156 `gain 0.0 ... V -288`, swe160 `gain 0.2 ... V -224`; swe151 had `gain 3.3 ... V 1995` at the same overflow). Taken where the bank rose for a few seconds while the lab switched from the first constructor to a cheap scout: swe158 `M 176 -> 195`, `mPull 0.0`, `gain 3.3 ... V 1747`; swe157 excluded at f=2793 then picked at f=2821 after the bank went 191 -> 193; swe159 `V 772` from a rise earlier in the window while the pick line shows `M 230 -> 227`. So the first constructor's first job was the turret in 2 of 5 (4 of 5 before), held briefly in a third; 1 turret built (swe157, the constructor busy 94-180 s). Later positive values come from `fromBuilders`/`fromUnits`, not spare metal (`overflow 0.2 ... gain 3.6 ... V 1029`, swe160).
- **(c) holds for `enemyArmyKnown`**: `seen: corthud:2 corcom:1` -> `280` (swe156), `corfav:1 corgator:1 corcom:1` -> `146` (swe159), `corak:1 corcom:1` -> `43` (swe160). The Director's ratio still counts the commander: swe160 `enemyArmyKnown=43 ratio=0.6` with our 251 (AWARE `enemy armed 2 strength 976` = corak 143 + corcom).
- **Fights**: the first kills of the series (swe156: 43 + 136 + 183 metal; swe157: the corgator, 120), but 3 armflash died to the enemy commander in its base (swe156), and the army sat at home in 158 and 160 (`ratio=7.1 ... none=4`; `none=5`, 420 stay-home lines) while BARb out-expanded us. One corfav killed two extractors in swe157 with 784 army at home.
- **Energy**: bank e 0-30 at 2:00 in all five; swe159 stopped on it (`energy=STALL 123.4/s short banked=298/1300`, the one constructor flip-flopping armadvsol / armmex / armsolar).
- **Swing stop on small numbers**: swe160 stopped on damage share 90 vs 141 while income 13.5 vs 8.9, extractors 5 vs 4, army 550 vs 215.
- [ANV-CPU] max 131.9-134.5 ms at 1:00 (start search), 15.6-41.0 ms at 3:00, 25.3-42.8 ms at 4:00.

## Against the 1v1 winners (`runs/vs_winners_156-160.txt`)
```
largest gaps (|ours - winners| / winners spread):
  4:00 m_inc         ours 8.9      winners 19.1     gap 2.00
  2:00 builders      ours 1        winners 3.0      gap 2.00
  1:00 e_inc         ours 50       winners 78.0     gap 1.65
  4:00 mex           ours 3        winners 9.0      gap 1.50
  3:00 builders      ours 2        winners 5.0      gap 1.50
  4:00 builders      ours 2        winners 6.0      gap 1.33
  2:00 army          ours 251      winners 86.0     gap 1.33
  4:00 e_inc         ours 110      winners 221.0    gap 1.23
```
Against swe151-155: builders at 2:00/3:00/4:00 are new in the list (we now make too few), and 2:00 army is now a gap the other way (251 vs winners' 86: too much army too early). 4:00 m_inc widened (1.55 -> 2.00). `first_armed_s` 59.8/64.7/91.2 vs winners 76/96/120: our first armed unit comes before theirs.

## Sight gaps across the five (truth `[HARNESS] team=1` vs Anarvā's log)
| t | BARb truth (median) | Anarvā knew | player access |
|---|---|---|---|
| 1:00 | army 0, mex 2, lab 0 (157/159: vehicle plant under way, static 550) | `seen: none`, `enemyArmyKnown=0`; PROD E 0 (157/158) or 744-829 (156/159/160, the uncorrected lab-first model) | Inferable that no lab stands yet; which plant is hidden from players too. |
| 2:00 | army 129 (86-146), mex 2-3, con 1-3 | `seen` none or 1 unit; `enemyArmyKnown` 0-43; PROD E 539-1018 | Mostly not in sight; inferable from the clock. E 1.6-3.5x the truth. |
| 3:00 | army 215 (172-386), mex 5 (4-5), con 4 | `seen` 0-3 units, `enemyArmyKnown` 0-146; PROD E 2001-2126; `theirs seen` 0-3 extractors | Partly in sight; inferable. E 2.4-3.5x the truth; extractors 1-3 seen vs 4-5. |
| 4:00 | army 452-480, mex 4-7 | `enemyArmyKnown` 120-280; E 2780-3303; `theirs seen 1` | In sight partly; inferable. |

### Missing to the bot (collected)
1. **The enemy lab's split between raiders and constructors** (all five): `RaidExists` assumes all their income becomes raiders; a player knows their lab also makes constructors for the extractors they will need. E ~3x the truth from 3:00 drives the plan-split override.
2. **Seen units capping the model** (swe160: 3 coraks and 3 extractors seen, estimate 14.5 coraks): sight should replace the model where it covers, not only raise it.
3. **Expected enemy extractor count from the clock** (all five; `theirs seen` 0-3 vs 4-7) - also the missing raid target for an army that sits at home (158, 160).
4. **Which plant they opened** (157, 159: vehicle plant, still modelled as `corak from corlab`); hidden until a scout, but our scouts reached their base at 112-168 s and nothing in the log says what they saw.
5. **Memory of seen enemy units** in `enemyArmyKnown` (swe156: 43 at 2:00 -> 0 at 3:00 with the corak still alive).
6. **A seen raider's track as a threat to our extractors** (swe157: one corfav killed two extractors 11 s apart).
- Not blindness, readings to fix: the Director's ratio counts the commander (swe160 `ratio=0.6`); the first lab pick runs before `raidLabAt` is corrected (3 of 5); [ANV-BPVAL] doesn't print the bank growth and logs once per 10 s, so the value behind swe157's f=2821 pick is not in the log; `[ANV-TRADE] ... got 60955` (swe156); an own builder's cancelled frame logged as `[ANV-DEAD] armmex ... attacker=3171` (our commander, swe159).

## Rework first
1. **The lab's split**: E at the raiders their lab can make after its constructors, capped by what is seen; with that the plan-split override stops forcing fighters while ours already lead (251 vs 129 at 2:00, constructors 1 vs 3).
2. **Correct the enemy lab time before the first production pick** (3 of 5 first picks used the lab-first model).
3. **Turret spare metal over the turret's own build time** (or net of the lab's queued demand), not the job window that catches the gap between two lab items (swe157/158/159).
4. **An army that leads and stays home** (158: 440 vs 172, 160: 550 vs 215): the raid value of their unseen extractors is 0 (Missing 3).
5. `tools/swing.py`: the damage share stopped swe160 on 90 vs 141 damage while every economic stat favoured us.
