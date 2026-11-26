# Spectator notes: swe26 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Live remarks (game time):

- **0:00** Script loads clean, no anarva ERR. Same start as swe24/25.
- **0:00-0:42 commander order**: extractor 9 s, **solar 25 s** (`t=10s commander -> armsolar (metal 3.8/s short of 5.0; energy 30/s short of 72 ...)`), extractor 41 s, plant ordered 42 s, **plant done 63 s**. Winners: extractors 9/16/31 s, solars 41/50 s, plant 69 s. **The order did not change from swe25**: the solar still comes second (ordered at 10 s), and there is no third extractor or second solar before the plant. The new storage rule does not show in the OPEN lines. Either it did not move the comparison, or the solar won on the metal-short term (3.8 vs 5.0) and not on energy.
- **1:00** Buildings 255 vs BARb 400 (2 extractors + 1 solar + a plant under construction, against BARb's 6 units). **Energy 365/1050** while BARb is at 1085/1100, so our bank was not overflowing at 1:00. The plant drains it.
- **1:04 plant queue**: `armvp -> armfav as scout (per metal 5.90; armcv=0.62)`, so this time **the Rover comes first**, then Blitz (f=2205), Blitz (f=2669), and **the first constructor vehicle at f=3585 (2:00)**. This is a regression from swe25 (constructor first at 1:08, scoring 20.64). The constructor's value fell from 20.64 to 0.62 between two games with the same start. EPLAN f=1830: `idleFac 165 builders 86 demandE 86 -> 251 | pull 88`, so energy was short when the plant started (income 50, e 365), and that probably cut the constructor's value.
- **1:45** The Rover was sent to `op enemy 12597 at (6014,1196) value 54` near the enemy base and died at (5953,1239), 5210 from base, to a Grunt (31 m). There is no recall line: the recall covers raids on spots, not ops on enemies.
- **2:00** Army 220 vs 86 (two Blitzes), buildings 460 vs 600, m_inc 8.9 vs 8.9. **Energy 47/1150, e_inc 50 vs BARb 104**: one solar all game until a second at 2:07. Extractors: 2 at 0:41, 3 at 1:46 (winners 3 at 2:00, 6 at 3:00). 10 BUILDFAILs.
- **2:23** Stopped (log ends f=4290) on buildings 1:00 + 2:00 (255 vs 400, 460 vs 600).

## Summary

- **Stopped** at about 2:23 on buildings, behind in both samples (255 vs 400 and 460 vs 600). Energy income was 50 vs 104 at 2:00.
- **Commander's first 70 s:** extractor 9 s, solar 25 s, extractor 41 s, plant 42-63 s. Winners: 3 extractors and 2 solars before a plant at 69 s. The new energy-storage rule did not change the order (the solar was picked on `metal 3.8/s short of 5.0`).
- **Energy:** 365/1050 at 1:00 (not full, so no overflow), 47/1150 at 2:00. We were short of energy, not overflowing.
- **Plant queue:** Rover first; the constructor came at 2:00 (its value fell from 20.64 in swe25 to 0.62 here). This is a regression.
- **First loss:** the Rover, at 1:45, deep in enemy land (31 m).
- **Rework first:** the plant's first unit. The constructor vehicle's value collapses when energy is short. The constructor is the unit that fixes energy (it builds solars and winds), so the energy shortfall should raise its value, not lower it.
