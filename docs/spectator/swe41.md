# Spectator: swe41 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=5785, 3:13). No anarva script error. 8 BUILDFAIL lines (23 before), 138 BLOCKED lines, 15 CommRedirect lines.

## BLOCKED
All 138 at f=11, one per unit: water and geothermal units, plus `[ANV-BLOCKED] f=11 armwin blocked by the game (terrain_wind)` and `corwin ... (terrain_wind)`.
The wind failure loop is gone: the opener now picks a second solar instead (`t=24s commander -> armsolar`).

## Opener (players: extractors 9/16 s, plant 69 s)
Start unchanged: `[ANV-START] chose (832, 2392)`. `armmex t=9s`, `armsolar t=23s`, `armsolar t=39s`,
`t=40s commander -> armmex at spot 30` (dist 232), `built armmex t=50s`, `t=51s commander -> armvp` (2 fails at 145-151, `canPlace=0`), `built armvp t=73s` (players 69 s).
f=1800: level with BARb on income: m_inc 6.6 vs 6.6, e_inc 70 vs 70, static 410 vs 400.

## 1:00-2:00
Plant: `execute armcv` f=2225 (74 s; winners 91 s), `built armcv t=102s`, `execute armfav` f=3085, `execute armcv` f=3381.
Commander walks 660 for a third extractor (`MEXIDLE f=2326 armcom spot=19 dist=660`), `built armmex t=99s`, then `built armsolar t=114s`.
f=3600: m_inc 8.9 vs 8.9 (= winners), e_inc 100 vs 97, army 31 vs 129 (winners 155-265), static 770 vs 600, build_m 860 vs 590.

## 2:00-3:13
Plant: `execute armcv` f=4073, `execute armflash` f=4929, `execute armcv` f=5557: 4 constructors and 2 combat units by 185 s.
Constructors: `BUILDFAIL f=4217 armcv job 1 armnanotc ... dist=257`; one walks 900+ to spot 36 (`MEXIDLE f=4669 armcv spot=36 dist=937`), and that extractor dies at once:
`[ANV-DEAD] t=192s armmex m=50 at (1408,2800) fromBase=633 ... nearestEnemy=corak@176`. Another goes for a radar 874 away (`BUILDFAIL f=5151 armcv job 10 armrad ... dist=874`).
Solars at 148 s and 159 s, then `[ANV-CHECK] t=3m metal=STALL 4.2/s short energy=WASTE 20.0/s banked=0/1250 ... eco t=3m ... mex=3 ... E 1500/1500`: too much energy, metal at 0.
CommRedirect at danger 0 again: `armmex gain 443 < risk 5126 (danger 0.0 cover 8.5)` (f=5365-5610, 15 lines).
f=5400: m_inc 8.9 vs 8.9 (winners 9-13.5), e_inc 160 vs 151, army 141 vs 258 (winners 186-527), static 1290 vs 950, build_m 995 vs 830; mex 3 vs 3.

## The stop
Army 31 vs 129 (f=3600) and 141 vs 258 (f=5400). Economy level or ahead; total value 2426 vs 2038 in our favour at f=5400.

## Rework first
The plant queue: 4 constructors (74, 113, 136, 185 s) for 2 combat units, while the extra constructors build solars into a full bank, walk 900 to a lone extractor that dies, or try a radar 874 away; mex stays 3. A player's plant at this point makes raiders after the second constructor. Then CommRedirect: risk 5076-5261 at danger 0.0.
