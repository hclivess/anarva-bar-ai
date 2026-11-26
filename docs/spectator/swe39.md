# Spectator: swe39 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=3600 sample (log ends f=4761, 2:39). No anarva script error. 23 BUILDFAIL lines, 0 CommRedirect lines.

## Start
`[ANV-START] chose (832, 2392) in box (0-1638, 0-6144)`, `[HARNESS] start team=0 x=832 z=2392`. 29 candidates evaluated.
The best was `(832,2392) value 1953 [end t 96 mInc 5.5 eInc 52.5 lab armvp@96 ...]`, next `(1296,3776) value 1913`.
The chosen point is ~200 from the players' (936,2562). Its second extractor (spot 30) is 332 away (`MEXIDLE f=2698 armcom spot=30 dist=332`), not 104-167.

## Opener (players: extractors 9/16 s, plant 69 s)
`armmex t=9s`, `armsolar t=23s`, then `t=24s commander -> armwin` fails **21 times** from f=721 to f=2626 (24-88 s), mostly with the commander standing on the turbine's footprint:
`[ANV-BUILDFAIL] f=1456 armcom job 4 armwin fails=8 dist=37 canPlace=1 | ... onSite=1 [armcom ] vel=1.25 ... radius=24` ... `f=2626 ... fails=21 dist=27 ... onSite=1 [armcom ]`.
The turbine is abandoned at 88 s: `t=88s commander -> armmex at spot 30`, `built armmex t=103s` (players 16 s). `t=104s commander -> armvp`, `built armvp t=124s` (players 69 s).
f=1800: mex 1, m_inc 4.3 vs 6.6, static 205 vs 550, `[ANV-CHECK] t=1m ... energy=WASTE 47.0/s banked=1020/1050`.

## 2:00-2:39
`execute armcv` f=3769 (126 s), `built armsolar t=148s`. f=3600: m_inc 6.6 vs 8.9, e_inc 50 vs 90, army 0 vs 146, static 255 vs 840, build_m 590 vs 715.
No assist and no other energy job in 24-148 s besides the failed turbine.

## The stop
Every stat behind in both samples: metal income 4.3 vs 6.6 (f=1800) and 6.6 vs 8.9 (f=3600), static 205/255 vs 550/840, army 0 vs 146.

## Rework first
Build-site placement against the builder's own position: the commander stood on the wind turbine's footprint (`onSite=1 [armcom ]`, dist 27-60) and the order failed 21 times over 64 s. The commander never moves off the footprint and the site is never moved. The start choice cost too: the second extractor was 332 away and built at 103 s.
