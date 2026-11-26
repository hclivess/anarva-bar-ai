# Spectator: swe45 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=7200 sample (log ends f=7606, 4:13). No anarva script error.

## Plant mix
armcv, Blitz, Blitz, Blitz, armcv, Blitz, Blitz, armcv, Blitz, armcv (`execute` order). Constructor first, then raiders, now Blitzes; no Rover at all.

## Ops (strength vs defence, units per op)
- The army holds home until ~165 s: `hold at (944,2368): mean distance 216 to 3 extractors and the base`; 294 `stay home` lines, last `stay home: raid spot (7488,3728) worth 56 <= home 97 (8.3 raiders due, 3 fighters)`.
- From ~170 s, every op is one Blitz to a far raid spot at defence 0: `op raid spot at (6960,5888) value 116 defence 0.0 strength 2.0 units 1 loss~0`, same for (7536,784), (7296,5552), (7584,5200), (7568,1536), (7488,3728), (7616,2016).
  There were 5 parallel single-unit ops at 240 s (`ops 5 [1@6960,5888 1@7536,784 1@7296,5552 2@7584,5200 1@7568,1536]`, spread 2545).
- Outcomes: `ended after 81 s: target gone, metal sent 110 left 110, enemy metal killed meanwhile 43`; `ended after 82 s: target gone ... killed meanwhile 43`; `ended after 42 s: target gone ... 0`.
  Then three at once: `pull back from (7616,2016): strength 4.4 x trade 1.0 <= defence 4.3`, `pull back from (7568,1536): strength 2.2 ... <= defence 4.3`, `pull back from (7536,784) ... ended after 92 s`.
- Regrouped: `op enemy 3857 at (6849,858) value 415 defence 4.3 strength 8.9 units 4 loss~100`; then `[ANV-DEAD] t=252s armflash m=110 at (6577,725) fromBase=5867 ... nearestEnemy=corak@123`.
- No lone Rover attacks on Grunts this time (the EffThreat fix holds); strength numbers sit in a sane range (2.0 per Blitz, 4.3 defence).

## Damage and kills per minute (ours/BARb)
- 2:00: dealt 0, taken 0
- 3:00: dealt 241, taken 263
- 4:00: dealt 477, taken 705; `ANV-CHECK t=4m ... killed=43 lost=0 ... microContact=12 microFired=8 microNoReply=4 microOutranged=6`
- The "43 killed meanwhile" in two ops is the same single 43-metal kill (`killed=43` total at 4m).

## Army, income, extractors (ours/BARb)
- 1:00: army 0/0, m_inc 6.6/6.6, mex 2/2
- 2:00: army 220/129 (winners 155-265, in band), m_inc 8.9/8.9, mex 3/3
- 3:00: army 330/258 (winners 186-527), m_inc 11.2/13.5, mex 4/5, con 2/4
- 4:00: army 660/441, m_inc 11.2/18.1, mex 4/7, con 4/5, e=1495/1500 (bank full again), metal 14/1300

## The stop
Metal income 11.2 vs 13.5 (f=5400) and 11.2 vs 18.1 (f=7200); damage share 241/263 and 477/705. Army was ahead all game.

## Rework first
Expansion: mex stays at 4 from 3:00 to 4:00 while BARb goes 5 -> 7, and the energy bank fills. The army leads by 50%, and 6 Blitzes are spread over 5 single-unit raids across the map (spread 2545), killing one 43-metal unit in 80 s, instead of holding or claiming the middle extractors.
