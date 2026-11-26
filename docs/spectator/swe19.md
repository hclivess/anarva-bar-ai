# Spectator notes: swe19 g00

Anarva (team 0, Armada, start 1216,3408) vs BARb hard (team 1, Cortex, start 6899,684), Comet Catcher Remake 1.8.
Change: a builder continues its own unfinished building found on the site. Focus: lab time, pickets before the raid, first fighters.

## Remarks
- 0:54 mex 2; 0:55 `commander -> armlab`. BUILDFAIL fails=1..11 (0:55-1:20): dist 230->175, from 1:15 `onSite=1 [armlab]`,
  vel 0, cmds=0 at 175 (reach 192) - the commander stands by its own frame and does not continue it. The fix did not fire.
  Lab built 1:34. Static 410 vs 650 at 2:00, no third extractor until 2:09.
- 1:49 first Pawn alone to 6960,5888 (value 64); 2:02 second to BARb's start 6800,752 (value 58); 2:15 and 2:27 two more
  "reinforce (6960,5888)". AWARE 2:30 `ops 2 [3@6960,5888 1@6800,752] pickets 0`; 3:00 same, army centre (3424,3415).
- 3:00: army 270 vs 172 (ahead), m_inc 11.2 vs 13.5, static 510 vs 900 (swing stop at 3:00 on income).
- 3:06 first Grunt at home: `detach 2 units to defend (1425,3226)`; 3:18 a second Grunt at (729,4813), more detaches. The raid
  units were mostly still on the way out (they had not reached the corners), so they came back in ~15-30 s.
- 3:23 extractor (576,4608) and 3:33 extractor (624,4160) killed by the Grunt corak 8655, while 3 Pawns were engaging at
  (693,4768). First picket order 3:26 (armpw -> 624,4160), after the first loss. 4:00 AWARE: 6 units at (387,3118), forward 0.04;
  m_inc 6.6 vs 19.2, static 410 vs 1770, killed 0 / dmg_out 13 vs dmg_in 1084.

## Summary
Stopped at 3:00 on metal income (11.2 vs 13.5) with army ahead (270 vs 172). Lab 1:34 after 11 failed starts beside its own
frame (continue fix not firing). All four first Pawns went to far corners (6960,5888 x3, 6800,752), pickets 0 until 3:26;
two Grunts arrived 3:06/3:18, units turned back but killed nothing (dmg_out 13) and two extractors were lost 3:23/3:33.
