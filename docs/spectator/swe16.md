# Spectator notes: swe16 g00

Anarva (team 0, Armada, start 1216,3408) vs BARb hard (team 1, Cortex, start 6899,684), Comet Catcher Remake 1.8.
Change: the opener places the lab beside the commander. Focus: lab time and failed starts; first fighters home vs far corners; first raid.

## Remarks
- 0:13 mex, 0:24 solar, 0:36 solar, 0:52 mex (same as swe13-15).
- 0:53 `commander -> armlab`. Site now 79-115 from the commander (was 190-340). But BUILDFAIL fails=1..15 from 0:53 to 1:12:
  fails 4-5 `canPlace=0 sitePlace=0 onSite=0` at dist 112, vel 0; fails 6-15 (0:59-1:12) `onSite=1 [armlab]` at dist 112,
  vel 0.00, cmds=0 - the frame is there, the commander stands within reach (112 < 145+47) and still is not building it.
  Then no more fails; lab built 1:28 (`lab standing at 89 s after 5 plans`). 11-16 s earlier than swe14/15, 13 s later than swe13.
- 1:00: static 410 vs 550 again (BARb's lab/first builds earlier).
- 1:54 first lab product is a constructor (armck), 2:00 mex, 2:22 second armck. 2:00: army 0 vs 146, static 690 vs 640
  (we lead buildings now), m_inc 6.6 each. 2:30: army 0, ops 0, pickets 0 - no fighter has been made yet.

## Summary
Stopped at 2:00 on army (0 vs 146; also 0 vs ~0 at 1:00 was even, buildings 410 vs 550 at 1:00). Lab ordered 0:53, 15 failed
starts to 1:12 with the commander standing 112 from the site, vel 0 (coordinator: the footprint overlapped the commander),
built 1:28. The lab's first two products were constructors (1:54, 2:22), so no fighter existed by 2:30: the home/far-corner
question and the first raid could not be observed.
