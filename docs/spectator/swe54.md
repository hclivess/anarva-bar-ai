# Spectator: swe54 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=6316, 3:30). No anarva script error.

## Plant mix and per-metal values
Executes: armcv f=2197 (73 s), armflash f=3057, armcv f=3541, armcv f=4881, armflash f=5989. Only 5 units in 200 s; one Blitz before 3:00.
Long build times in the metal stall: armcv 2197 -> 101 s (31 s), armcv 3541 -> 160 s (42 s), armcv 4881 -> 197 s (34 s).
PROD lines:
- 73 s: `armvp -> armcv as constructor (value 6691 per metal 41.09; S air/surf 0/0 E 0/0 ...) | armcv=41.09 ... armfav=19.50 armflash=3.56 armpincer=2.44 defence 194 armstump=1.71 defence 131 ... armsam=4.30 defence 140`
  The defence term shows up only here, and only on armpincer/stump/art/janus/sam, **not on armflash** (3.56).
- `armflash as fighter (value 4846 per metal 21.90; ... E 0/296)` -> then `armcv=8.83 armflash=7.15`, `armcv=16.71 armflash=12.18`, `armcv=14.91 armflash=10.14`, `armcv=14.88 armflash=9.86`,
  then `armflash as fighter ... per metal 9.35 (armcv 5.82)` and `12.75 (armcv 8.81)` once E reaches 1896-1918.
  No "defence N" term appears in any later PROD line.

## Army per minute (ours / BARb / winners)
- 1:00: 0/0
- 2:00: 110/266 (winners 155-265)
- 3:00: 110/386 (winners 186-527)

## Extractors and income (ours / BARb)
mex 2/2, 3/2, 3/4; m_inc 6.6/6.6, 8.9/6.6, 8.9/11.2; `m=0/1250` at 3:00.
Built `armmex t=9, 51, 96 s`; nothing after that by 3:30.

## Constructors' first extractor
Built `armcv t=101s, 160s, 197s`.
- First: `103 s armcv -> 1:armnanotc`, `103 s -> 13:armmex`, `104 s armcv -> 22:- | 1:armnanotc=1000000000000.00 13:armmex=523.04` (GUARD the plant), held until 162 s: 58 s guarding.
  Then `162 s -> 13:armmex` (`MEXEXEC f=4890 armcv spot=36 dist=687`), `163 s -> 10:armrad`. First extractor job ~61 s after it was built.
- Extractor <-> radar pairs every second at M 0 from 199 s: `202 s armcv -> 13:armmex | 13:armmex=81.79` / `202 s armcv -> 10:armrad | ... 10:armrad=99.74 13:armmex=1107.81`.
  The two lines show different extractor values (82 vs 1108), so they are probably two constructors.

## Raids and outcomes
No extractor lost. dmg 118 dealt / 207 taken by 3:00. One raid: `op raid spot at (6960,5888) ... units 1` -> `pull back ... strength 1.7 x trade 1.0 <= defence 2.2`.
Phantom nanoframe losses again: `[ANV-DEATH] f=3521 armflash beingBuilt=1 progress=0.01 attacker=-1`, `f=4858 armcv ... 0.01`, `f=5965 armcv ... 0.00` (lost_m 2).

## [ANV-CPU]
max 28.3 / 18.3 / 21.7 ms (minutes 1-3), within the 33.3 budget.

## The stop
Army 110 vs 266 (f=3600) and 110 vs 386 (f=5400); metal income 8.9 vs 11.2 at f=5400.

## Rework first
The first constructor GUARDs the plant for 58 s (104-162 s) while the plant builds in a metal stall. The plant then makes 3 constructors to 1 Blitz, and the defence term never reaches armflash, the unit actually picked. GUARD in a metal stall adds build power with no metal to feed it.
