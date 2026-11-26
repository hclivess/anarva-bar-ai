# Spectator: swe37 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=6000, 3:20). No anarva script error. 7 BUILDFAIL lines.

## CommRedirect
None in this game (0 lines). The commander was never pulled off a job.

## Minute by minute
**0:00-1:00.** `armmex t=9s`, `armsolar t=25s`, `armmex t=48s`, `t=49s commander -> armvp (... 50 E/s covers its production (5.0 M/s, 72 E/s))`.
f=1800: mex 2 (winners 3), static 255 vs 550, e_inc 50 vs 90, `build_m=590` vs BARb 0, while `tech ... con=1` for both. Only the commander exists, and the vehicle plant is still being built, so build_m seems to count the plant.

**1:00-2:00.** `built armvp t=72s` (winners 69). Plant: `execute armfav` f=2181 (73 s), `execute armcv` f=2445 (81 s; winners 91 s).
Commander: `72 s armcom -> 13:armmex`, `84 s -> 15:armcv` (assist), `91 s -> 13:armmex`, `built armmex t=113s`. No energy after 25 s: e_inc 50 until 160 s.
`[ANV-CHECK] t=2m ... energy=STALL 31.2/s short`. f=3600: mex 3 (winners 6), m_inc 8.9 vs 6.6 (= winners 8.9), army 31 vs 120 (winners 155-265), build_m 725 vs 860, e=2/1150.

**2:00-3:20.** `[ANV-DEAD] t=123s armfav ... fromBase=5996 ... nearestEnemy=corcv@197` (the scout again, in their base). The first constructor took 48 s in the stall (`built armcv t=129s`).
Plant: `execute armfav` f=3909, `execute armcv` f=4201, `built armcv t=193s`, `execute armflash` f=5821 (194 s).
Commander: switches each second between solar and a second lab, `130 s armcom -> 4:armsolar` / `armcom -> 0:armlab` / `133 s -> 0:armlab` / `139 s -> 4:armsolar`,
then `141 s armcom -> 15:armcv` (assist) to 194 s, `built armsolar t=160s`. Extractors are not even a candidate: `13:armmex=1000000000000.00` from 133 s.
First constructor: `132 s armcv -> 1:armnanotc`, `BUILDFAIL f=4040/4066/4093 armcv job 1 armnanotc fails=1..3 dist=186`. No extractor from it; mex stays 3 at 3:00 (`eco t=3m workers=2 mex=3`).
f=5400: mex 3 vs 5 (winners 8), m_inc 8.9 vs 13.5, e_inc 80 vs 110, army 31 vs 240, build_m 860 vs 1005, static 690 vs 1090.

## The stop
Army 31 vs 120 (f=3600) and 31 vs 240 (f=5400); metal income 8.9 vs 13.5 and energy short at f=5400.

## Focus answers
- Extractors per minute: 2/3/3 vs winners 3/6/8.
- Plant mix: Rover, constructor, Rover, constructor, Blitz. One combat unit in 194 s.
- build_m: 590/725/860 vs 0/860/1005. The 590 at 1:00 with con=1 is the plant (or the plant under construction), not a mobile builder.
- Army/income: 0/6.6, 31/8.9, 31/8.9 vs BARb 0/6.6, 120/6.6, 240/13.5.

## Rework first
The plant's queue. Rover, constructor, Rover, constructor gives an army of 31 at 3:00. The first Rover dies scouting their base every game (swe36 124 s, swe37 123 s). The constructors don't claim extractors either: the first goes for a nano (`armcv -> 1:armnanotc`), so their value is spent on nothing.
