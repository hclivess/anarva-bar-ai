# Spectator notes: swe15 g00

Anarva (team 0, Armada, start 1216,3408) vs BARb hard (team 1, Cortex, start 6899,684), Comet Catcher Remake 1.8.
Focus: when the lab goes up and whether the commander struggles to start it; first fighters home vs far corners; first raid.

## Remarks
- 0:00-0:51: mex 0:13, solar 0:23, solar 0:35, mex 0:51 (same as swe13/14). Small BUILDFAILs on each (fails=1-2, onSite=1,
  dist 50-87) - a second or two each.
- 0:52: `commander -> armlab (affordable now; income 6.6 M/s, 70 E/s ...)`. 0:59-1:04 BUILDFAIL fails=1-3, dist 239->190,
  canPlace=1, onSite=0, cmds=0. From 1:05 (fails=4..12) `canPlace=0 sitePlace=0 onSite=1 [armlab]`: the frame is placed but the
  commander stays 174-207 from it (buildDist 145 + radius 47 = 192 reach), moving (vel 1.25) with cmds=0, never in range
  long enough to build. 1:21: `[ANV-DEATH] armlab beingBuilt=1 progress=0.00 attacker=-1` - the empty frame vanishes
  (lost_m=1 at 2:00 is this), ~30 s wasted.
- 1:22: lab ordered again (fails 1-2 at 207-222), finally built at 1:44 (`lab standing at 105 s after 6 plans`). Lab 29 s
  later than swe13 (1:15).
- 1:36: `MexPorc: armllt valued at extractor (loss ... 36220 > turret 94)`: commander's next job is a light laser at home;
  it fails 6 times at dist 84 with vel 0.00 (1:46-2:00), built 2:05. Then a mex at dist 773 fails twice with vel 0.
- 2:00: static 495 vs 790, army 108 vs 266, m_inc 6.6 each (we still have 2 extractors), BARb e_inc 100 vs 70.
- 1:59: first Pawn sent alone to 6960,5888 (value 64); 2:12 second to 6800,752 (BARb's start, value 58); 2:25 third to
  7296,5552 (value 59). AWARE 2:30: `ops 3 [1@6960,5888 1@6800,752 1@7296,5552] pickets 0`, spread 914. Every fighter
  left, one by one, for the far corners; none at home.
- Log stops at f=4710 (2:37), so the run was stopped by the swing check, apparently on buildings at 1:00 (410 vs 550) and
  2:00 (495 vs 790).

## Summary
Stopped at 2:00 on buildings (static_m 495 vs 790; already 410 vs 550 at 1:00). Lab ordered 0:52, built 1:44 after 12+2
failed starts: the commander hovered 174-239 from the site (reach ~192) with cmds=0; the placed empty frame died at 1:21
(progress 0) and was reordered. Then the commander's light laser failed 6 times at dist 84, vel 0. Fighters: all three
Pawns (1:59, 2:12, 2:25) went alone to far corners (6960,5888 / 6800,752 / 7296,5552), pickets 0; no raid before the stop.
