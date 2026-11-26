# Spectator notes: swe18 g00

Anarva (team 0, Armada, start 1216,3408) vs BARb hard (team 1, Cortex, start 6899,684), Comet Catcher Remake 1.8.
Change: pickets value our extractor sites by the modelled first raid before anything is seen. Focus: pickets before the raid, do they meet it.

## Remarks
- 0:51 mex 2; 0:52 `commander -> armlab`. BUILDFAIL fails=1..9 (0:52-1:04): dist 216->178, vel 0 most of the time; from 0:59
  `onSite=1 [armlab]` - our own frame on the site, commander 178-180 away, cmds=0 (coordinator: the job never learned its target).
  Lab built 1:21.
- 1:00: static 410 vs 550, e_inc 70 vs 90. 2:00: static 460 vs 690, army 54 vs 146 (swing stop at 2:00).
- 1:35: first Pawn alone to far SE corner (6960,5888, value 64). AWARE 2:00 `ops 1 [1@6960,5888] pickets 0`; 2:30 same, army
  spread 2213. Pickets 0 in every AWARE line 0:00-3:30 - the new raid model produced no picket before contact.
- 2:10-2:30: commander solar BUILDFAILs again (fails up to 5 at dist 79-210, onSite=1 [armsolar]); a nanotower frame dies at 2:10
  (progress 0, no enemy near).
- 2:35: second unit (a 270 m one, strength 4.2) sent alone to BARb's start (6800,752).
- 2:49: first picket order `armpw -> (624,4160)` (losses there 169), but the raider came elsewhere: 2:54 start extractor
  (1216,3408) killed by an Incisor (corgator@48). 3:09 `detach 1 units to defend (1174,3135)`, then at 3:11 that unit is
  sent back out to 7488,3728 / 6800,752, recalled 3:12, re-sent 3:13, detached again 3:18, re-sent to 6800,752 at 3:21 -
  it flip-flops between the raid and home.
- 3:00: m_inc 6.6 vs 13.5, army 324 vs 360. 3:30 AWARE army centre (5030,4188), forward 0.63, pickets 0. Log ends ~3:47.

## Summary
Stopped at 2:00 on buildings (460 vs 690). Lab 1:21 after 9 failed starts with our own frame on the site. Pickets: none before
the first raid (AWARE pickets 0 to 3:30; one picket order at 2:49 to a different extractor); the first Pawn went to 6960,5888
at 1:35 and the big unit to 6800,752 at 2:35. An Incisor killed the start extractor at 2:54 unopposed; the defending unit then
alternated between home defence and the 6800,752 raid every few seconds.
