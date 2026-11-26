# Spectator: swe36 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=3600 sample (log ends f=4530, 2:31). No anarva script error.

## Failed starts
5 BUILDFAIL lines (was 10-23 by 2:00), 4 REORDER lines, all `-> move first: refused too`:
- `f=301 armcom job 4 armsolar fails=1 dist=222` (first solar)
- `f=1351 ... armsolar fails=1 dist=145 ... site dist=-1` and `f=1426 ... fails=2 dist=98` (second solar)
- `f=1711 armcom job 0 armvp fails=1 dist=215 ... onSite=1 [armmex ]` (an extractor sits on the plant site)
- `f=3314 armcv job 1 armnanotc fails=1 dist=149`

## Opener vs winners (9/16/31 extractors, 41/50 solars, 69 s plant)
`armmex t=9s`, `armsolar t=25s`, `armmex t=44s`, `armsolar t=56s`, `t=57s commander -> armvp`, `built armvp t=81s` (12 s late).
No third extractor before the plant. f=1800: static 410 vs BARb 550, m_inc 6.6 vs 6.6, e_inc 70 vs 70; `[ANV-CHECK] t=1m ... energy=WASTE 62.0/s banked=848/1100`.

## 1:00-2:31
Plant: `execute armfav` f=2453 (82 s), `execute armcv` f=2601 (87 s; winners 91 s), `built armcv t=105s`, `execute armcv` f=3173, `built armcv t=135s`,
`execute armfav` f=4077, `execute armflash` f=4361. `[ANV-DEAD] t=124s armfav m=31 at (6628,825) fromBase=5996 ... nearestEnemy=corcv@153` (the scout, deep in their base).
Commander held back from extractors, risk still at danger 0: `CommRedirect: armmex gain 1615 < risk 3700 (danger 0.0 cover 6.5)` (~82 s),
`gain 265 < risk 4231 (danger 0.0 cover 7.0)`, then `gain 173-194 < risk 4231-4341 (danger 0.4 ...)` repeated to the end.
`[ANV-CHECK] t=2m metal=ok energy=STALL 197.0/s short ... mInc=5.0 eInc=80.0 mex=2`.
f=3600: m_inc 6.6 vs 6.6 (winners 8.9), e_inc 80 vs 100, e=0/1250 vs 236/1300, army 31 vs 146 (winners 155-265), static 640 vs 640.

## The stop
army+buildings 410 vs 550 (f=1800) and 671 vs 786 (f=3600); energy short at f=3600.

## Rework first
Army at the plant: Rover, constructor, constructor, Rover, Blitz gives 31 army at 2:00 (BARb 146). Second: CommRedirect risk of 3700-4341 at danger 0.0-0.4 keeps the commander off extractors (mex=2 at 2:00).
