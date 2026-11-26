# Spectator notes: swe28 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8 (same AI as swe26/27)

Live remarks (game time):

- **0:00-1:02** Commander: extractor 9 s, solar 24 s, extractor 40 s, plant ordered 41 s, done 62 s. The same order for the fourth game running (winners: extractors 9/16/31 s, solars 41/50 s, plant 69 s).
- **1:00** Buildings 255 vs 550, energy 321/1050 against BARb's 1100/1150.
- **1:03 plant queue**: `armvp -> armfav as scout (per metal 5.90; armcv=0.62)`, then Blitz, Blitz, Blitz (F2157/F2597/F3537). **No constructor vehicle at all by 2:23.** In every PROD line the constructor scores 0.62-1.22 against Blitz 1.27-1.76. This is the swe26 pattern; swe25/27 had the constructor first with the same code. EPLAN f=1830 (plant start): `idleFac 165 builders 86 demandE 86 -> 251 | pull 88`, with energy income 50 against a plant draw of 72.
- **1:03-2:23 commander**: 148 `[ANV-PICK] armcom -> 13:armmex` lines. **Extractor is its only candidate type** (`best per type: 13:armmex=28.76 ... 141.57 ... 407.17`; no solar, no wind is listed). It walks 568-736 out (BUILDFAIL dist 736 at f=2232, dist 568 vel 0 at f=3526-3555) and builds one extractor (1:55) in 80 s. Meanwhile energy falls 335 -> 287 -> **11/1150** and stays there. The commander should be building energy at base: the plant's 72 E/s draw is more than our 50 E/s.
- **2:00** Army 361 vs 120 (Rover + 3 Blitz; first kill: 1 for 0, dmg 88 out / 77 in). Buildings 305 vs 640, income **8.9 vs 6.6 (ahead)**, energy 11/1150 vs 399, e_inc 50 vs 100. Extractors: 3 (9/40/115 s); winners 3.
- **2:23** Stopped (log ends f=4290). Total value 666 vs 760 and buildings 305 vs 640 at both 1:00 and 2:00. The game never reached the middle game, so there is nothing to report on minutes 5-12, pickets against Incisors or T2.

## Summary

- **Stopped** at about 2:23 on buildings / total value (255 vs 550, then 305+361 vs 640+120). We were ahead on income (8.9 vs 6.6) and army (361 vs 120). The middle game was never reached.
- **What led to it:** (1) the plant made no constructor (`armcv=0.62` vs Blitz 1.3-1.8, the same as swe26). (2) The commander had only extractors as candidates: it walked 570-740 out, built one in 80 s, and energy sat at 11/1150 under the plant's 72 E/s draw with 50 E/s income.
- **Rework first:** the plant's opening constructor and the commander's energy. They are one decision. When energy income is below the plant's draw, the value of the units that can build energy (commander at base, constructor vehicle) has to rise. Instead it fell: the constructor scored 0.62, and solar/wind did not appear among the commander's candidates. The swing between constructor-first (swe25/27) and Rover-first (swe26/28) with the same code shows the constructor's value hinges on the energy state at the plant's first tick.
