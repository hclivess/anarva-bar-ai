# Spectator: swe38 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=5716, 3:10). No anarva script error. 6 BUILDFAIL lines, 0 CommRedirect lines.

## Minute by minute
**0:00-1:00.** `armmex t=9s`, `armsolar t=25s`, `armmex t=44s`, `armsolar t=56s`, `t=57s commander -> armvp`. f=1800: static 410 vs 400, e_inc 70 vs 70, m_inc 6.6 vs 6.6 (level).
Plant start failed once: `BUILDFAIL f=1711 armcom job 0 armvp fails=1 dist=222`. `built armvp t=81s` (winners 69).

**1:00-2:00.** Plant: `execute armcv` f=2465 (82 s; winners 91 s), `built armcv t=110s`, `execute armfav` f=3341, `execute armcv` f=3637.
Commander: `82 s armcom -> 13:armmex` (`built armmex t=115s`), `116 s armcom -> 4:armsolar | ... 4:armsolar=288.96 13:armmex=378.25` (`built armsolar t=131s`).
First constructor: `113 s armcv -> 1:armnanotc | 1:armnanotc=25.74 13:armmex=33.48`, a nano before an extractor.
f=3600: m_inc 8.9 vs 8.9 (= winners), e_inc 80 vs 101, army 31 vs 43, mex 3 vs 3, build_m 725 vs 710.

**2:00-3:10.** Commander: assist only briefly, `132 s armcom -> 15:armcv | ... 13:armmex=237.51 15:armcv=95.49` (E 3/1300), then `141 s armcom -> 13:armmex` (`built armmex t=162s`),
`178 s armcom -> 10:armrad`, `181 s -> 13:armmex` (fails `f=4650/4725 armcom job 13 armmex ... canPlace=0`). Second constructor `160 s armcv -> 13:armmex`, then `178 s armcv -> 10:armrad`.
Plant: `execute armflash` f=4753 (158 s), `execute armcv` f=5353 (178 s). `[ANV-DEAD] t=152s armfav ... fromBase=4956 ... nearestEnemy=corak@85` (scout lost again).
f=5400: m_inc 11.2 vs 13.5 (winners 9-13.5), e_inc 110 vs 144, army 110 vs 215 (winners 186-527), mex 4 vs 5, static 895 vs 1200, build_m 995 vs 830.

## The stop
Army 31 vs 43 (f=3600) and 110 vs 215 (f=5400); metal income 11.2 vs 13.5 at f=5400.

## Focus answers
- Commander 70-200 s: extractor, solar, ~9 s of assist (132-141 s), extractor, radar, extractor. The assist that took 113-194 s in swe37 is gone, so the change works.
- Energy income/min: 70/80/110 vs BARb 70/101/144 (swe37: 50/50/80). Better, still behind from 2:00.
- `13:armmex=1000000000000.00` did not recur (0 lines). The sentinel now sits on `1:armnanotc` from 132 s, with the nano unbuildable or already taken.
- Plant mix: constructor, Rover, constructor, Blitz, constructor (3 constructors, 2 combat units by 178 s). First jobs of the constructors: nano (113 s), extractor (160 s), then radar for both at 178 s.
- Army/income: 0/6.6, 31/8.9, 110/11.2 vs BARb 0/6.6, 43/8.9, 215/13.5.

## Rework first
The plant queue still favours constructors (3 vs 2 combat units by 3:00, army 110 vs 215). Then the first constructor's job: a nano at 113 s, while winners' constructors take far extractors.
