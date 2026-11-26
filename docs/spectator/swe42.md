# Spectator: swe42 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=5400 sample (log ends f=5881, 3:16). No anarva script error. 7 BUILDFAIL lines, 0 CommRedirect lines.

## [ANV-PROD] strength
Every PROD line reads `S air/surf 832/832 E 0/1665`, from the first one at 73 s (`enemyArmyKnown=0`) to the last at 178 s.
Our S does not move while our army goes 0 -> 31 -> 62 -> 93, and E is 1665 before any enemy is seen. Both look like fixed or projected numbers, not the live armies.
The per-type comparison still mixes scales: `per type ours/theirs corak 19/1227` (ours 19, theirs 1227 for one Grunt type), so the `groups 1:-123` / `1:-119` terms are negative.
Fighter vs constructor per metal:
- 73 s: `armfav=10.75` (scout, `firstRaid 25 (5.8 raiders, duel 0.11)`), `armflash=2.25`, `armcv=1.15`
- ~82 s: `armcv=11.10`, `armflash=2.91`
- ~111 s: `armcv=4.97`, `armflash=0.09`, `armfav=0.56` (as scout)
- later: `armcv=5.16 / armflash=0.10`, then `armcv=2.81 / armflash=0.12`
Fighters still score ~0.1 per metal once a Grunt is seen; the change did not lift them.

## Minute by minute
**0:00-1:00.** `armmex t=9s`, `armsolar t=23s`, `armsolar t=39s`, `armmex t=50s`, `t=51s commander -> armvp`, `built armvp t=72s`. f=1800 level: m_inc 6.6/6.6, e_inc 70/70.
**1:00-2:00.** `execute armfav` f=2181, `execute armcv` f=2461 (82 s), `built armmex t=96s`, `built armcv t=110s`, `execute armfav` f=3337, `execute armcv` f=3605.
f=3600: m_inc 8.9 vs 6.6, army 62 vs 129 (winners 155-265), static 460 vs 650.
**2:00-3:16.** `execute armcv` f=4469, `execute armfav` f=5057, `execute armcv` f=5329. Solars at 133, 150, 160, 192 s; `eco t=3m workers=4 mex=3 M inc=8.9 M 126/1250 E inc=160.0 E 1497/1500`, an overfull energy bank again.
f=5400: m_inc 8.9 vs 13.5, e_inc 160 vs 124, army 93 vs 172 (winners 186-527), mex 3 (4th at 192 s), build_m 1130 vs 830.

## The stop
Army 62 vs 129 (f=3600) and 93 vs 172 (f=5400); metal income 8.9 vs 13.5 at f=5400.

## Focus answers
- Plant mix: Rover, constructor, Rover, constructor, constructor, constructor, Rover, constructor: 5 constructors, 3 Rovers, no Blitz. Winners: constructor, then raiders.
- Army/min: 0/62/93 vs BARb 0/129/172.
- Economy did not collapse: metal 6.6/8.9/8.9 (BARb 6.6/6.6/13.5), but mex stays 3 with 5 constructors, and the energy bank is full at 3:00 (overbuilt solars).

## Rework first
The PROD strength inputs: `S 832/832 E 0/1665` is constant all game, and per-type `corak 19/1227` is still on two scales. Fighters still score 0.1 per metal against constructors' 3-5, so the plant keeps making constructors.
