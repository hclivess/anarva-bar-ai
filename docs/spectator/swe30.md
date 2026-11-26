# Spectator notes: swe30 g00 - Anarva vs BARb hard (Cortex), Comet Catcher Remake 1.8 (build-before-the-lab test includes energy plants)

- **0:00-1:14 commander**: extractor 9 s, solar 23 s, extractor 39 s, **solar 51 s** (`before the lab: armsolar yields 7 before a constructor could build it, the lab loses 0`), plant ordered 52 s (`70 E/s covers its production`), **plant done 74 s**. Winners: extractors 9/16/31 s, solars 41/50 s, plant 69 s. Now 2 extractors + 2 solars + plant. The winners' third extractor is still missing, but the plant time matches.
- **1:00** Buildings **410 vs 550** (was 255 vs 550 in swe25-29). Energy 1014/1100.
- **1:15 plant queue**: Rover, Blitz, Blitz, Blitz (F2241-F3441), **first constructor vehicle F3921, done 2:38**. Then Rover, Blitz, constructor (3:31), then **5 Rovers in a row** (F6373-F7457, 3:32-4:08).
- **2:00** Army 361 vs 146, buildings 615 vs 690, income 8.9 vs 6.6 (ahead), energy 762 vs 84. Our best 2:00 so far.
- **2:00-3:00 army**: 4-6 units at (4118-4733, 3444-3674), forward 0.45-0.55, ops at the enemy corners (6960,5888) and (5904,5632). The recall fires: `recall raid at (6960,5888) ... meeting the corfav at (5007,2125) saves 5297`, and later at (654,5411) `saves 6643`. The values are in the thousands for a lone Rover-class scout (corfav, about 31 m). The recall then chases scouts around the map.
- **3:00** Army 502 vs 386, buildings 725 vs **1140**, income 11.2 vs 13.5. Extractors: 4 (9/39/108/158 s); winners 6. 0 kills either side.
- **3:09-3:53 Incisor/corfav raid in our base**: our Rover dies at (6559,905) in the enemy corner. The radar at (1264,3360), 67 from base, goes to a corgator at 3:24. Extractors at (624,4160) and (576,4608) go to a corfav at 3:44/3:52, and a Rover dies at (1186,3247). Defence ops: `op enemy 16712 at (622,3144) ended after 62 s: target gone ... killed 0`; `pulled back, metal sent 722 ... killed 0`. **The 533-metal army sat home (forward 0.03) and killed nothing**: dmg out 162 vs in 2892. The raiders are faster than our response.
- **4:00** Army 533 vs 746, buildings 650 vs 1650, **income 6.6 vs 20.4**, lost 5 / killed 0. Stopped (log ends f~7600).

## Summary

- **Stopped** at 4:00 on everything: income 6.6 vs 20.4, buildings 650 vs 1650, dmg 162 vs 2892. 3:00 was already behind (buildings 725 vs 1140).
- **Opener:** 2 extractors + 2 solars, plant 74 s. Buildings at 1:00 rose to 410 vs 550, the best yet. The third extractor before the plant is still missing.
- **What led to it:** the first constructor came only at 2:38 (Rover/Blitz x4 first), so we had 4 extractors at 3:00 against the winners' 6. Then 2 Incisors and a corfav raided the base from 3:09 to 3:53. Our army (ahead 502 vs 386) was first in the enemy corner, then chased scouts on recalls worth 5000-6600, then sat home and killed 0. Meanwhile the plant made 5 Rovers in a row.
- **Rework first:** the defence response to raiders. It should be pickets placed at the extractors raiders can reach, sized from the raiders seen, instead of a whole-army op that arrives after "target gone". Also cap what a recall values at what the threat can actually destroy: a 31 m scout is not worth 5000.
