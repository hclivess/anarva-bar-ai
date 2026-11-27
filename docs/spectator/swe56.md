# Spectator: swe56 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=7200 sample (log ends f=7698, 4:16). No anarva script error. 4 BUILDFAIL lines.

## Constructor picks
armcv PICK lines by job: `13:armmex` 135, `15:armcv` (assist) 9, `1:armnanotc` 2, `10:armrad` 2.
Median values (builder-ms per metal, lower is better): armmex 52.0 (n 148), armllt 30.6 (n 17), armcv-assist 71.9, armsolar 179, armnanotc 1969 (n 26).
The horizon fix works: nano dropped from 151 (swe55) to ~1969, and extractors are now the constructors' job almost every time.

## But extractors stay low (ours / BARb)
mex 2/2, 3/3, **3/5**, **4/8**; m_inc 6.6/6.6, 8.9/8.9, 8.9/13.5, 11.2/18.1.
Extractors built `t=9, 50, 97, 195, 251, 253 s`; one lost `[ANV-DEAD] t=237s armmex m=50 at (2032,3360) fromBase=1472 ... nearestEnemy=corgator@183`.
The spots the constructors walk to are far:
- `MEXEXEC f=4281 armcv spot=36 dist=683` (143 s; the first constructor built 115 s; extractor up at 195 s, 52 s after the order). `MEXIDLE f=4302 armcv spot=36 dist=666 ... vel=0.07` (barely moving)
- `f=5871 armcv spot=45 dist=1018`, `f=5891 armcv spot=50 dist=1035` (196 s; built 251/253 s)
- `f=6885 armcv spot=43 dist=246` only at 229 s.
So the picks are right, but the spots are far and the walks long. 52-57 s from order to extractor, and the nearby spot 43 (246) is taken last.

## Plant output and army
Executes: armflash f=2181, armcv 2682, armcv 3477, armcv 4242, armcv 4853, armflash 5802, armflash 6265, armcv 6793: 5 constructors and 3 Blitzes.
army 0/0, 110/120, 110/240, 330/580 (winners 155-265 at 2:00, 186-527 at 3:00).
Fights: `op raid spot at (6960,5888) ended after 76 s: target gone ... killed 0`; `op enemy 26376 at (1877,3446) ended after 23 s: target gone, metal sent 330 left 330, killed 0`. dmg 239/550 at 4:00.
A Blitz died at the plant: `[ANV-DEAD] t=225s armflash ... at (885,2480) fromBase=126 nearestEnemy=corgator@1550 flags=3`.

## Banks
metal 625, 390, **0**, **0**; energy 979, 275, 470, **1526/1550** (full at 4:00; e_inc 170 vs 180).

## [ANV-CPU]
max 28.2 / 23.0 / 24.5 / 36.5 ms.

## The stop
Metal income 8.9 vs 13.5 (f=5400) and 11.2 vs 18.1 (f=7200); army 110/240 and 330/580.

## Rework first
Which spot a constructor takes: they head for spots 683-1035 away (one moving at 0.07) while spot 43 at 246 is left until 229 s. Extractors land 50+ s after the pick. Then the plant mix: 5 constructors to 3 Blitzes, with metal at 0 from 3:00.
