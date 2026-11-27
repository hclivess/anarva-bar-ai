# Spectator summary: swe136-140 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Change under test: the opener should build ~3 extractors and ~3 energy plants before the lab at ~64 s (1v1 winners in `runs/replays.db`: 3 extractors in 66 of 106 games, lab median 64 s). Before it: extractor, solar, lab at 45 s (e.g. swe132: armmex 13, armsolar 24, armlab 45).
Per-game notes: [swe136](swe136.md), [swe137](swe137.md), [swe138](swe138.md), [swe139](swe139.md), [swe140](swe140.md). No `ERR  :` line in any game.

| game | stop | stat (ours vs BARb) | mex/plants before lab | lab, built | m_inc 2:00 | army 2:00 | m_inc 3:00 | army 3:00 | m_inc 4:00 | army 4:00 |
|---|---|---|---|---|---|---|---|---|---|---|
| swe136 | 3:00 | metal income 11.2 vs 13.5 | 2 / 1 | armvp 59 s | 6.6 / 8.9 | 110 / 129 | 11.2 / 13.5 | 361 / 172 | - | - |
| swe137 | 4:00 | damage share 0.47 vs 0.53 | 2 / 1 | armvp 59 s | 6.6 / 6.6 | 256 / 266 | 11.2 / 11.2 | 555 / 386 | 8.9 / 20.4 | 710 / 480 |
| swe138 | 3:00 | metal income 8.9 vs 11.2 | 2 / 1 | armvp 63 s | 6.6 / 8.9 | 225 / 129 | 8.9 / 11.2 | 476 / 215 | - | - |
| swe139 | 5:00 | metal income 18.1 vs 22.7 | 2 / 1 | armvp 59 s | 6.6 / 6.6 | 256 / 146 | 13.5 / 13.5 | 555 / 386 | 13.5 / 20.4 | 775 / 626 |
| swe140 | 3:00 | energy short 1 vs 0 | 2 / 1 | armvp 59 s | 8.9 / 8.9 | 110 / 43 | 13.5 / 13.5 | 471 / 215 | - | - |
| **median** | **3:00** | | **2 / 1** | **armvp 59 s** | **6.6 / 8.9** | **225 / 129** | **11.2 / 13.5** | **476 / 215** | 11.2 / 20.4 (n 2) | 743 / 553 (n 2) |

## What the five show
- **The opener is deterministic and short of the target.** All five: `[ANV-START] chose (1216, 3408)`, commander extractor 0 s, solar 14 s, extractor 25 s (`before the lab: spot 50 yields 182 before a constructor could build it, the lab loses 0`), vehicle plant ordered 38-39 s (`lab: affordable now; income 6.6 M/s, 50 E/s covers its production (5.0 M/s, 72 E/s)`), up 59-63 s. So 2 extractors and 1 solar, not 3 and 3. The lab time (59 s) is near the winners' 64 s; the third extractor was weighed and lost (`best first: spot 36 -22`), and so was a second solar (swe138: `best first: armsolar -99`). The lab test reads "50 E/s covers ... 72 E/s".
- **Energy splits the games.** Where the commander's next jobs were two solars (swe137 74/85 s, swe139 73/89 s) energy was full by 3:00 and the game lasted to 4:00-5:00. Where it went extractor or constructor first (swe136, swe138, swe140) energy sat at 0-1 from 2:00 with 186-502 metal banked (`[ANV-CHECK] t=2m ... energy=STALL 70.8/s short banked=474/1250`, swe136) and the game stopped at 3:00.
- **Army is not the gap; its use is.** Army ours > BARb from 2:00-3:00 in 4 of 5 (median 476 vs 215 at 3:00, 2.2x), but it stays home: `stay home: raid spot ... worth 193 <= home 77` (swe136), `[ANV-CHECK] t=5m ... army=1215 ... attack=0 raid=0 defend=10` (swe139). BARb meanwhile goes to 8-9 extractors by 4:00-5:00 vs our 3-7.
- Fights were few and short: every [ANV-FIGHT] ended "target gone" or "pulled back"; losses were one scout and one extractor per game (swe137, swe139). [ANV-CPU] max 127-137 ms at the start search, then 9-64 ms (swe139 above the 33 ms budget from 3:00).
