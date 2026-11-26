# Spectator notes: swe17 g00

Anarva (team 0, Armada, start 1216,3408) vs BARb hard (team 1, Cortex, start 6899,684), Comet Catcher Remake 1.8.
Change: lab placed at the commander's build distance. Focus: lab time and failed starts; first fighters home vs far corners; first raid.

## Remarks
- 0:13 mex, 0:24 solar, 0:36 solar, 0:53 mex (same as before).
- 0:54 `commander -> armlab`; BUILDFAIL fails=1..5 (0:54-0:59), site 145-193 away, vel 0 then 1.08; no more fails after 0:59.
  Lab built 1:16 (`lab standing at 77 s`): the fix worked, ~5 s of failed starts instead of 20-30 s; lab 12-28 s earlier
  than swe14-16, on par with swe13 (1:15).
- 1:00: even (static 410 vs 400). 2:00: static 615 vs 900, army 108 vs 86, m_inc 8.9 each.
- Lab: armck 1:41, then Pawns. 1:56 first Pawn alone to far SE corner (6960,5888, value 96); 2:10 second to 7296,5552 (value 88);
  2:23 a third "reinforce (6960,5888)". AWARE 2:30 `ops 2 [2@6960,5888 1@7296,5552] pickets 0`, army at (2548,4142).
- 2:58: a Grunt in our base: `detach 1 units to defend (1426,3238)`, but 3:00 AWARE `ops 3 [1@6960,5888 1@7296,5552 1@1376,3280]`,
  army centre (4390,4071), forward 0.53 - two of three Pawns are on the far side of the map.
- 3:03 extractor at our start (1216,3408) killed by a Grunt (corak@43). 3:11 "detach 3 units to defend (856,3447)"; 3:16
  extractor at (576,4608) lost; 3:21 unfinished light laser frame gone; 3:39 solar frame, 3:49 solar, 3:53 nanotower frame,
  4:00 start extractor again, 4:06 solar - all to Grunts (corak 19677 / 19832). Pickets only from 3:30 (armpw -> 624,4160 /
  1216,3408), after the losses began.
- 3:00: army 162 vs 312, static 1035 vs 1370, m_inc 11.2 vs 13.5. 4:00: army 291 vs 648, static 915 vs 1430, m_inc 8.9 vs 15.8,
  killed 3 / lost 6 units, dmg_in 2794 vs dmg_out 273. Log ends f=7425 (4:07).

## Summary
Stopped at 3:00 on buildings (1035 vs 1370; coordinator), the log running on to 4:07 with every stat behind by 4:00: metal income 8.9 vs 15.8, army 291 vs 648, buildings 915 vs 1430
(already behind at 3:00 on army/buildings/income). The lab fix worked: 5 failed starts in 5 s, lab 1:16. But the first three
Pawns again left one by one for the far SE corners (6960,5888 / 7296,5552) with pickets 0, so two Grunts arriving ~2:58
walked through the base: 2 extractors (one twice), 3 solars, a nanotower frame and a light laser frame lost 3:03-4:06 for
3 kills. Defence ops started at 2:58/3:11 with the army 3000+ away; pickets only from 3:30.
