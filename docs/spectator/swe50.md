# Spectator: swe50 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

The run restarted once (the infolog was rewritten at 04:25). Stopped by swing.py after the f=7200 sample (log ends f=7372, 4:05). No anarva script error. 13 REISSUE and 4 BUILDFAIL lines.

## [ANV-PROF] / [ANV-CPU]
- `f=1800 heaviest per minute: Opening::Update 90ms/max 28 Scout::Update 30ms/max 1 EcoPos::Update 15ms/max 0 ...` / `[ANV-CPU] f=1800 ... mean 0.22 ms max 32.8 ms ... units 6`
- `f=3600 ... Scout::Update 602ms/max 14 EcoPos::Update 71ms/max 1 Command::Update 24ms/max 1 ...` / `mean 0.60 max 22.4 units 10`
- `f=5400 ... Scout::Update 868ms/max 17 EcoPos::Update 89ms/max 1 Command::Update 44ms/max 0 ...` / `mean 0.80 max 24.5 units 16`
- `f=7200 ... Scout::Update 1373ms/max 34 EcoPos::Update 95ms/max 2 Command::Update 27ms/max 2 Radar::Update 24ms/max 1 ...` / `mean 1.14 max 42.6 units 24`
Scout::Update dominates: 602 -> 868 -> 1373 ms per minute, growing with time. Its 34 ms single max at minute 4 is most of the 42.6 ms update max (budget 33.3). The 28 ms max in minute 1 is the opener.

## Why extractors stay at 3 (mex 2/3/3/5 vs BARb 2/3/5?/5+, income 6.6/8.9/8.9/13.5 vs 6.6/8.9/11.2/18.1)
Extractors built `t=9s, 50s, 97s, 203s, 228s`; a third far one was killed while being built (`[ANV-DEATH] f=7104 armmex beingBuilt=1 progress=0.03 attacker=2044 corak`, (1296,3776), 1451 from base).
Constructors built `armcv t=114s, 171s, 205s, 220s`. Their jobs:
- `117 s armcv -> 1:armnanotc | 1:armnanotc=236.10 13:armmex=741.33`, then `118 s armcv -> 22:- | 1:armnanotc=511.01 13:armmex=671.03` (job type 22, no def, held until 174 s: 56 s on an unnamed job)
- `174 s armcv -> 10:armrad | ... 10:armrad=4.78 13:armmex=87.26 | M 16/1250` (`built armrad t=209s`)
- the first extractor pick by a constructor is at `208 s armcv -> 13:armmex`, 94 s after the first constructor; then it alternates `209 s -> 10:armrad` / `-> 13:armmex`.
- Distances when they go: `MEXEXEC f=6246 armcv spot=50 dist=1397`, `f=6335 spot=22 dist=758`, `f=6336 spot=14 dist=1103`. The commander takes spots at 643, 835, 714, 803.
- armcv PICK changes are low (1/1/4/1 per minute): they are not switching, they are on the wrong jobs (nano, job 22, radar).

## [ANV-REISSUE]: who overwrites orders
The re-sends fall on frames 2981, 3491, 3521, 4061, 4511, 5171, 6161, 6281, 6341, 6371, all at frame 11 mod 30, the same pass as the watchdog.
At least one re-send **restores an old job over a new pick**:
`[ANV-PICK] f=3488 armcom -> 13:armmex | 4:armsolar=1929.24 13:armmex=155.40` -> `[ANV-REISSUE] f=3491 armcom order lost: re-sent` -> `[ANV-REORDER] f=3491 armcom armsolar at (552,2216) from 325 ... refused too`.
The commander had just chosen an extractor; the re-send put back the solar it had left.
Similar at `f=6278 armcv -> 10:armrad` -> `REISSUE f=6281 armcv` -> `MEXEXEC f=6281 armcv spot=50 ... dist=1400` (an old extractor order coming back over the new radar pick).
The re-send seems to keep the last *sent* order, not the current job.

## Phantom losses (factory re-issue)
`[ANV-DEATH] f=2646 armflash beingBuilt=1 progress=0.00 attacker=-1` / `[ANV-DEAD] t=88s armflash ... nearestEnemy=none`, and again `f=4038 ... progress=0.02` (134 s).
These are cancelled duplicate nanoframes counted as losses (lost_m 1 -> 2 -> 3).

## Army and fights
army 0/0, 220/86, 220/258, 330/583; dmg dealt/taken 0/0 until 4:00, then 0/499.

## The stop
Metal income 8.9 vs 11.2 (f=5400) and 13.5 vs 18.1 (f=7200); damage 0/499.

## Rework first
1. [ANV-REISSUE] re-sends a stale order over the builder's new job (f=3488 extractor pick -> f=3491 solar re-sent). Re-send the current job only, or drop the re-send when the job changed.
2. The first constructor spends 118-174 s on `22:-` and the next 35 s on radar before its first extractor pick (94 s).
3. Scout::Update CPU growth (1373 ms/min, 34 ms max).
