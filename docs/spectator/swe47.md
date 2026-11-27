# Spectator: swe47 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Loaded fine (no watchdog hang lines). Stopped by swing.py after the f=7200 sample (log ends f=7347, 4:05). No anarva script error.

## Metal income and extractors per minute (ours / BARb / winners)
- 1:00: m_inc 6.6 / 6.6, mex 2 / 2 (winners 3)
- 2:00: m_inc 8.9 / 6.6 / 8.9, mex 3 / 2 (winners 6)
- 3:00: m_inc 8.9 / 11.2, mex 3 / 4 (winners 8), `m=0/1250`, `e=1436/1450`
- 4:00: m_inc 8.9 / 13.5 / 13.5-15.8, mex 3 / 5 (winners 12), `m=10/1250`, `e=1438/1500`

Extractors built `t=9s, 51s, 98s, 195s`. Two of the far ones were lost to Grunt raids:
`[ANV-DEAD] t=201s armrad m=60 at (1456,2800) ... nearestEnemy=corak@127`, `[ANV-DEAD] t=204s armmex m=50 at (1408,2800) fromBase=633 ... corak@168`,
`[ANV-DEAD] t=220s armmex m=50 at (1216,3408) fromBase=1074 ... corak@961`.
Our army was 330-440 against BARb's 129-301 and dealt **0 damage** all game (`dmg_out=0`, dmg_in 312, lost_m 3).

## What constructors build while metal is at 0
- `161 s armcv -> 7:armllt | 1:armnanotc=1000000000000.00 4:armsolar=1000000000000.00 7:armllt=26.11 13:armmex=75.93 | M 0/1250`
- `164 s armcv -> 10:armrad | ... 10:armrad=4.88 13:armmex=69. | M 0/1250`
- `210 s armcv -> 10:armrad | 0:armavp=80.06 ... 10:armrad=13.10 ... | M 3/1250`
- `233 s armcv -> 7:armllt | ... 7:armllt=31.87 13:armmex=35.65 | M 0/1250`
The new ranking pushes nano/solar to the sentinel at M 0, but radar (4.9-13) and llt (26-32) still beat extractors (36-76).
Extractor vs radar alternation again: `209 s armcv -> 13:armmex | 13:armmex=14.85`, `210 s armcv -> 10:armrad`, `210 s -> 13:armmex`, `211 s -> 10:armrad`, `212 s -> 13:armmex`, ... `241 s -> 13:armmex`.
The extractor lines list only `13:armmex` and the radar lines list the full set, so this is probably two constructors writing interleaved lines rather than one switching (PICK lines have no unit id).
armcv PICK changes: 4 in minute 2, 12 in minute 3, 1 in minute 4.

## Constructors
Plant: armflash f=2213, armcv f=2661 (89 s), armflash f=3481, armcv f=3945, armflash f=4509, armcv f=5161, armflash f=6161, armcv f=6757 (alternating, close to the winners' pattern).
Built `armcv t=115s, 149s, 204s`.
- First constructor: `118 s armcv -> 4:armsolar` (M 380, E 247; built 134 s), `152 s -> 1:armnanotc`, `153 s -> 13:armmex` with `MEXEXEC f=4612 armcv spot=36 ... dist=884` (154 s), then `161 s -> 7:armllt`, `164 s -> 10:armrad`.
  Its first extractor is most likely spot 36 (1408,2800), built 195 s and dead 204 s: ~80 s after leaving the plant.
- Commander walking far: `MEXEXEC f=5022 armcom spot=45 ... dist=1134`, `MEXIDLE f=5090 ... dist=1106 vel=1.25`. That extractor at (1216,3408) is the one lost at 220 s.
- Solars at 134, 152, 166 s fill the energy bank (1436/1450 at 3:00) while metal is at 0.

## The stop
Metal income 8.9 vs 11.2 (f=5400) and 8.9 vs 13.5 (f=7200); damage share 0/312. Army ahead.

## Rework first
Defending the extractors: an army 1.5-3x BARb's dealt 0 damage while Grunts killed the radar and two extractors 633-1074 from base (201-220 s). After that, the job ranking at M 0: radar and llt still outrank extractors.
