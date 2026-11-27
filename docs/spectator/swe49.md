# Spectator: swe49 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=7200 sample (log ends f=7479, 4:09). No anarva script error.

## Per minute (ours / BARb)
- 1:00: mex 2/2, m_inc 6.6/6.6, army 0/0
- 2:00: mex 3/3, m_inc 8.9/8.9, army 110/43
- 3:00: mex 3/5, m_inc 8.9/13.5, army 110/215
- 4:00: mex 3/5, m_inc 8.9/13.5, army 440/430, `m=0/1250 e=1494/1500`
Extractors built `t=9s, 51s, 97s, 248s`; MEXEXEC distances: commander spot 19 at 646, spot 36 at 656 (221 s); constructors spot 22 at 166 (225 s), spot 45 at 276 (235 s). Vritrasura's 13 by 6:00 lie 904-4709 away.

## Constructors
Built `armcv t=114s, 164s, 194s` (Vritrasura 79/102/125/171/184). Jobs:
- `117 s armcv -> 7:armeyes | 1:armnanotc=1362.43 7:armeyes=301.99 13:armmex=1188.44`, `built armeyes t=150s`
- `151 s armcv -> 7:armllt | ... 7:armllt=NOW:1089.23 13:armmex=655.98`, `-> 1:armnanotc`, `153 s -> 7:armllt` (`built armllt t=174s`)
- `175 s armcv -> 1:armnanotc`, `176 s -> 10:armrad | ... 10:armrad=3.95 13:armmex=70.62` (`built armrad t=210s`)
- the first extractor pick by a constructor is at `185 s armcv -> 13:armmex | 13:armmex=69.68`, 71 s after the first constructor; the extractor stands at 248 s.
The commander builds llt (`116 s armcom -> 7:armllt ... NOW:227.78`, `built armllt t=138s`) and solars.

## Phantom deaths from order re-sends
`[ANV-FAC] f=2661 execute armcv` -> `f=2691 re-issue armcv (order lost: queue ...)` -> `f=3428 finish armcv` / `cancel armcv: removes 2 queued builds (queue 2)` ->
`[ANV-DEATH] f=3473 armcv beingBuilt=1 progress=0.00 attacker=-1` -> `[ANV-DEAD] t=115s armcv m=135 at (885,2480) fromBase=126 ... nearestEnemy=none`.
The same happens for armflash at f=6479 (`progress=0.01`), t=215 s and t=237 s. The factory re-issue queues a second build, and cancelling it destroys a fresh nanoframe that is counted as a loss (lost_m 1 -> 3).
18 `[ANV-REISSUE]` lines (`f=1241 armcom order lost: re-sent`, `f=1601`, `f=2291` ...), 5 factory re-issues.

## Factory output
execute armflash f=2213, armcv 2661, armcv 3493, armcv 4992, armflash 5857, 6492, 7149. One Blitz between 74 s and 195 s; the constructors take 48 s (116-164 s) in the metal stall. No idle stretch, but slow.

## [ANV-CPU]
- `f=1800 ... mean 0.13 ms max 26.5 ms ... units 6`
- `f=3600 mean 0.52 max 28.2 units 10`
- `f=5400 mean 0.84 max 37.8 units 16`
- `f=7200 mean 0.98 max 40.2 units 25`
The max is over the 33.3 ms budget from minute 3.

## Fights
Single-Blitz raids, all `target gone ... killed 0`; dmg 0/0 all game.

## The stop
Metal income 8.9 vs 13.5 at f=5400 and f=7200.
