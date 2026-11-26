# Spectator: swe33 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=7200 sample (log ends f=7830, 4:21). No anarva script error.

## Minute by minute
**0:00-1:00.** Commander: `armmex t=9s`, `armsolar t=22s`, `armmex t=39s`, `armsolar t=53s` (energy is now built: e_inc 70 = BARb 70 at f=1800).
`t=54s commander -> armvp (lab: affordable now; income 6.6 M/s, 70 E/s covers ...)`, and the energy bank overflows: `[ANV-CHECK] t=1m ... energy=WASTE 64.0/s banked=861/1100`.

**1:00-2:00.** Nothing is built. The lab is ordered again `t=97s commander -> armvp`, `built armvp t=118s` (winners 69-77 s);
`lab standing at 119 s after 6 plans`. f=3600: m_inc 6.6 vs 8.9, army 0 vs 86, static 410 vs 750, e=894/1200 (unused).

**2:00-3:00.** Plant: `execute armfav` f=3561 (119 s), `execute armcv` f=3853 (128 s, `armcv=6.33` per metal), `execute armflash` f=4601,
`execute armcv` f=5045, `execute armflash` f=5877. Commander: `armllt t=129s`, then `armcom -> 15:armcv` (assist) at 130 s,
`armsolar` from 153 s (`built armsolar t=170s`). First CommRedirect only at f=5905:
`armmex gain 209 < risk 4351 (danger 1.1 cover 8.5)`, then `gain 219-223 < risk 4461 (danger 1.1 cover 10.5)` through f=6135 (danger is non-zero now,
risk still ~20x the gain). f=5400: m_inc 6.6 vs 13.5, e=0/1300, army 141 vs 215. `[ANV-CHECK] t=3m ... energy=STALL 177.0/s short`.
CONVAL life: `N 1 H 679 ... life 679 ... -> 3569`, `N 1 H 189 ... life 189 ... -> 1088`, `N 2 ... life 292 -> 1437`, `N 3 ... life 633 -> 801`, `N 4 ... life 606 -> 671`.

**3:00-4:21.** `[ANV-DEAD] t=194s armnanotc m=230 at (1320,3384) fromBase=106 ... nearestEnemy=corak@85` (a Grunt raid at home), `[ANV-DEAD] t=250s armfav`.
Plant keeps making constructors: `execute armcv` f=6149, 6909, 7553 (5 constructors by 251 s). They do not build extractors: from 195 s to 210 s every
armcv flips each second between `13:armmex` and `15:-` (assist), e.g. `201 s armcv -> 15:- | ... 13:armmex=221.32 15:-=140.33` / `armcv -> 13:armmex`,
while `4:armsolar=1000000000000.00` (a sentinel). mex=2 the whole game (`eco t=4m workers=4 mex=2 M inc=6.6 ... E 0/1400 stall=true`).
f=7200: m_inc 6.6 vs 13.5, army 282 vs 570, static 700 vs 1390, lost 230 (nano).

## The stop
Metal income 6.6 vs 8.9 at f=3600 and 6.6 vs 13.5 at f=5400/7200 (also energy short at f=5400 and f=7200).

## Focus answers
- Commander 50-200 s: energy built before the lab (2 solars), then lab late (118 s), llt, assist, solar at 170 s. CommRedirect risk 4351-4461 at danger 1.1 vs gains ~210.
- Energy income/min: 70/70/100/120 vs BARb 70/97/131/171.
- Plant mix: Rover, Constructor, Blitz, Constructor, Blitz, Constructor, Rover, Constructor, Constructor - constructor-heavy, no raider stream; first constructor 128 s (winners 91 s).
- Army/income: 0 / 6.6 at 2:00 (winners 155-265 / 8.9); 141 / 6.6 at 3:00 (winners 186-527 / 9-13.5).

## Rework first
The plant start (lab at 118 s, nothing built 1:00-2:00). Next: constructors oscillating extractor/assist every second and never claiming a spot (mex stays 2 with 5 constructors).
