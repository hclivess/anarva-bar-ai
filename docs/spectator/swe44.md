# Spectator: swe44 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=5926, 3:17). No anarva script error.

## [ANV-PROD]: per type and group terms on one scale now
- 74 s, before contact: `armfav as scout ... S air/surf 0/0 E 0/0`, `armcv=10.50 armfav=10.75`; then `armcv as constructor ... armcv=11.12`.
- First fighter line: `armvp -> armfav as fighter (value 1389 per metal 17.82; S air/surf 0/0 E 0/447; per type ours/theirs corak 832/363) | armcv=5.04 ... armfav=17.82 per-type -108 ... groups 1:1505 armflash=12.80 per-type 101 ... groups 1:3293`.
  Same scale now (832 vs 363), and the group terms are positive.
- As E grows 447 -> 1688 and S 0 -> 424, Rover per metal falls 17.82 -> 20.23 -> 14.37 -> 11.07 -> 8.93 -> 7.44 -> 12.32 -> 6.68, while constructor stays 5.0-6.7.
  The last line: `armvp -> armcv as constructor (value 2541 per metal 8.84; S 424/424 E 0/1688; ... corak 1248/1242) | ... armfav=3.34 ... armflash=3.17`.
- Blitz always scores below the Rover (12.80/14.12/10.37/8.27/6.86/5.84/10.11/6.13 vs 17.82/20.23/14.37/11.07/8.93/7.44/12.32/6.68), so no Blitz is built.
- Air S equals surface S (`S air/surf 60/60`, `121/121` ... `424/424`), which looks like the same number copied.

## Plant mix
`execute armfav` f=2209, `armcv` f=2481 (83 s), then **9 Rovers in a row** (f=3329 -> 5289, one every ~9 s), then `armcv` f=5573 (186 s).
That is close to the winners' pattern (constructor, then raiders, next constructor ~76 s later; here 103 s later), but every raider is a 31-metal Rover.

## Army and economy per minute (ours/BARb)
- 1:00: army 0/0, m_inc 6.6/6.6, mex 2/2
- 2:00: army 31/86 (winners 155-265), m_inc 8.9/8.9, mex 3/3. A Rover was lost at 113 s (`[ANV-DEAD] t=113s armfav ... fromBase=4264 nearestEnemy=corak@129`).
- 3:00: army 248/129 (winners 186-527, our first lead), m_inc 8.9/13.5, mex 3/5, con 2/4, e=1199/1400 (overfull again, solars at 134/147/150 s)

## The stop
Fights: dmg_out 5 vs dmg_in 100 (f=3600) and 13 vs 174 (f=5400); kills 0 vs 1 in both. So the stop was most likely damage/kill share, plus metal income 8.9 vs 13.5 at f=5400.
Total value was in our favour at f=5400 (2178 vs 2109).
The Rovers trade badly: `[ANV-FIGHT] f=5430 op enemy 11095 at (2779,2118) ended after 14 s: squad lost, metal sent 31 left 0, enemy metal killed meanwhile 0`; `[ANV-DEAD] t=180s armfav ... nearestEnemy=corak@158`.
`[ANV-CHECK] t=3m ... army=248 ... moving=1/8 attack=0 raid=6`.

## Rework first
Unit choice inside the fighters. Rovers (31 m, scout) win per metal over Blitz, but lose every contact with Grunts (0 kills, 5-13 damage dealt). The per-metal value counts power per metal without the square law against the Grunt's health and range, so cheap fragile units win the score. Second: the economy stalls at mex 3 with 2 constructors while BARb reaches 5/4.
