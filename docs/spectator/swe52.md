# Spectator: swe52 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=7200 sample (log ends f=7346, 4:05). No anarva script error. 13 REISSUE and 4 BUILDFAIL lines.

## Extractors and income per minute (ours / BARb)
- 1:00: mex 2/2, m_inc 6.6/6.6
- 2:00: mex 3/3, m_inc 7.7/8.9, e=0/1200 (energy stall)
- 3:00: mex 4/5, m_inc 11.2/12.3
- 4:00: mex **6/6**, m_inc **15.8/15.8** (winners 13.5-15.8)
This is the first game level with BARb on income at 4:00. Extractors built `t=9, 50, 97, 171, 219, 225 s`.

## [ANV-REISSUE]
Most re-sends repeat the builder's current pick:
- `PICK f=2259 armcom -> 13:armmex` -> `REISSUE f=2261` -> `MEXEXEC f=2261 armcom spot=19`
- `PICK f=2975 armcom -> 7:armllt` -> `REISSUE f=2981` -> `REORDER armllt`
- `PICK f=3782 armcom -> 4:armsolar` -> `REISSUE f=3791` -> `REORDER armsolar`
- `PICK f=4923 armcom -> 10:armrad` -> `REISSUE f=4931` -> `REORDER armrad`
The commander's stale-order overwrite from swe50 is gone.
Two cases are unclear, because PICK lines carry no unit id and two constructors interleave:
`PICK f=3787 armcv -> 1:armnanotc` -> `REISSUE f=3791 armcv` -> `MEXEXEC f=3791 armcv spot=36` (likely the other constructor), and
`REISSUE f=5501/5531 armcv` -> `MEXEXEC spot=45`, followed by `PICK f=5509/5534 armcv -> 1:armnanotc`.

## Constructors (built 122, 162, 192, 212, 242 s)
- GUARD (`22:-`): only 2 lines, at 242 s (`242 s armcv -> 22:- | 1:armnanotc=20773.08 ... 13:armmex=863.81 | M 75/1400`). Down from 56 s in swe50.
- First extractor jobs: `MEXEXEC f=3765 armcv spot=36 dist=690` (125 s, 3 s after the first constructor), `f=5493 spot=45 dist=658` (183 s, 21 s after the second),
  `f=5942 spot=43 dist=282` (198 s, 6 s after the third), `f=6840 spot=50 dist=244` (228 s, 16 s after the fourth). The commander took spot 22 at 867.
- Interleaved picks from 182-195 s: `armcv -> 13:armmex | ... 13:armmex=145.01` / `armcv -> 1:armnanotc | ... 13:armmex=623.30`, every second.
  The two lines carry different candidate sets, so they are most likely two constructors, one of which keeps ranking a nano first.
- Early detours: `127 s armcv -> 7:armeyes`, `165 s armcv -> 10:armrad` (built 181 s).

## [ANV-CPU] / [ANV-PROF]
- `f=1800 mean 0.21 max 31.7 ms` (Opening::Update max 26)
- `f=3600 mean 0.28 max 12.2`
- `f=5400 mean 0.37 max 20.1`
- `f=7200 mean 0.42 max 37.4`, PROF `Command::Update 48ms/max 28`
Scout::Update is down to 67/138/175 ms per minute (max 2-3). The minute-4 spike is Command::Update (28 ms).

## Army and fights (ours/BARb)
army 0/0, 110/43, 220/258, 220/344. Damage dealt/taken 514/592 at 4:00, kills 1 vs 3 losses (one is the phantom `[ANV-DEATH] f=2666 armflash beingBuilt=1 progress=0.01 attacker=-1`).

## The stop
Army 220 vs 258 (f=5400) and 220 vs 344 (f=7200); income was level at f=7200.

## Rework first
Army output: it stays at 220 from 3:00 to 4:00 while BARb doubles. The plant made 5 constructors by 242 s. The economy now holds; the army is the gap. Then the one constructor that keeps picking a nano over extractors (182-195 s).
