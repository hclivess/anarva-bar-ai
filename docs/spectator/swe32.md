# Spectator: swe32 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by `tools/swing.py` at f=5700 (3:10). Last log line: `[ANV] Terrain: no choke tower ...` at f=5700; no further output, no engine process left.
No anarva script error in the log (the only errors are the usual headless shader/widget ones).

## Minute by minute

**0:00-1:00.** Commander: `armmex t=9s`, `armsolar t=25s`, `armmex t=48s`, then
`t=49s commander -> armvp (lab: affordable now; income 6.1 M/s, 50 E/s covers its production (5.0 M/s, 72 E/s))`,
`built armvp t=71s` (winners 69-77 s: on time). Stats f=1800: m_inc 6.6 vs 6.6, e_inc 50 vs 70, static 255 vs 400.
Note the lab line itself: 50 E/s does not cover 72 E/s of production.

**1:00-2:00.** Plant: `execute armfav` f=2153 (72 s, "as scout", value per metal 5.90), `execute armflash` f=2425,
`execute armflash` f=2865. Then at f=3761 (125 s) `armvp -> armcv as constructor (value 856 per metal 1.78 ...)`.
Three combat units in 50 s, then the plant switched to a constructor (winners: constructor at 91 s, then Rovers every 4-8 s).
Commander after the lab: only extractors (`built armmex t=115s`, `t=153s`); its pick list from 48 s to 125 s holds a single
option, `armcom -> 13:armmex | 13:armmex=31.68`, and from 126 s `armcom -> 15:armcv` (assisting the plant). No energy
candidate at all until 184 s. Energy hits zero: `[ANV-CHECK] t=2m ... energy=STALL 26.5/s short`, `eco t=2m ... E inc=50.0 E 12/1150 stall=true`.
Stats f=3600: m_inc 8.9 vs 8.9 (= winners' 8.9), army 251 vs 129 (in winners' 155-265), but e=0/1150 vs 137/1300, e_inc 50 vs 97, static 305 vs 750.
Commander redirected on zero danger: `CommRedirect: armmex gain 403 < risk 3846 (danger 0.0 cover 10.5)` (f=3497), repeated to f=3675;
`armlab gain 513 < risk 3846 (danger 0.0 ...)` f=3755. `commander ... redirects=7 ... retreats=7` at 2:00, 14/14 at 3:00.

**2:00-3:10.** The constructor took 59 s to build in the stall (`execute armcv` f=3761, `finish armcv` f=5524; `built armcv t=184s`), and
the plant queued a second `armcv` (f=5545, value per metal 1.56 vs armflash 0.36). Army frozen at 251 (`[ANV-AWARE] t=180s army 3 (251 metal ...)`).
Only at 184 s does energy enter the pick list: `armcom -> 4:armsolar | 4:armsolar=202.91 13:armmex=1000000000000.00`, then
`CommRedirect: armsolar gain 161 < risk 4166 (danger 0.0 cover 0.0)` blocks it again (f=5623-5692).
Stats f=5400: m_inc 11.2 vs 13.5 (winners 9-13.5), e=1/1150 vs 160/1450, e_inc 50 vs 131, static 355 vs 1000, army 251 vs 215 (winners 186-527).

## The stop
`energy short` (swing.py: bank under a tenth of storage) for us and not for BARb in the f=3600 and f=5400 samples
(0/1150 and 1/1150 vs 137/1300 and 160/1450). Metal income was also >10% behind at f=5400 (11.2 vs 13.5). Army was ahead in both.

## Focus answers
- **Defence/recall values.** The change was not exercised: no recall or defence op, no `[ANV-DEAD]`, dmg_in only 38 all game.
  Home value seen: `stay home: raid spot (6960,5888) worth 49 <= home 103 (7.8 raiders due, 2 fighters)` (then 3 fighters), repeated each tick.
  The one op on a cheap unit: `op enemy 27748 at (5027,2153) value 54 ... units 1 loss~53` -> `ended after 4 s: target gone ... killed 0`.
  Skips near the enemy base read 3533-4614 (`skip enemy 16306 at (6882,924) value 4614: strength 1.8 vs defence 8.8`), one 54.
- **Kill or chase.** Neither: killed_m 0, dmg_out 0. The Blitzes ran 11 single-unit raid-spot ops of value 8-26, every one
  `target gone ... enemy metal killed meanwhile 0` after 5-39 s; two `pulled back` (defence 2.2 and 6.5). `microContact=2 microFired=0 microOutranged=2` at 2m.
- **Pickets.** `pickets 0` in every `[ANV-AWARE]` line, 2-4 extractors held, none raided.
- **Plant mix.** Rover, Blitz, Blitz, armcv, armcv. Winners: constructor first at 91 s then a steady raider stream; ours: 3 raiders then 2 constructors, the first stalled 59 s.
- **Army/income.** 2:00: army 251 (in band), income 8.9 (= winners). 3:00: army 251 (low end, flat), income 11.2 (in band, behind BARb 13.5). Energy 50 E/s flat 0:25-3:04 against BARb 70/97/131.

## Rework first
The commander's job choice after the lab: from 48 s to 184 s energy is not even a candidate (`armcom -> 13:armmex | 13:armmex=31.68`
alone, then `15:armcv`) while `energy=STALL 26.5/s short`; and when it appears, `CommRedirect ... risk 4166 (danger 0.0 ...)`
vetoes it. A player's commander builds the energy its lab needs right after the lab; a risk of ~4000 metal at zero danger is wrong maths.
