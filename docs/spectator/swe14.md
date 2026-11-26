# Spectator notes: swe14 g00

Anarva (team 0, Armada) vs BARb hard (team 1, Cortex), Comet Catcher Remake 1.8.
Change under test: raid targets valued at an extractor's yield only until the enemy could rebuild it.
Focus: do the first fighters (min 2-4) stay home and meet BARb's first raiders (~3:00-3:40)?

## Remarks
(Starts: ours 1216,3408, BARb 6899,684 - same as swe13.)

- 0:13-0:50: mex, solar, solar, mex - identical to swe13 to the second. Only 2 extractors until past 2:30.
- 1:39: bot lab, 24 s later than swe13 (1:15). 1:53 a light laser (armllt) is built at home before any unit. 2:04 first constructor.
- 2:00: army 0 vs BARb 120 m; static 495 vs 790; m_inc 6.6 vs 6.6 but BARb e_inc 100 vs 70.
- 2:19: first Pawn still sent alone to the far SE corner: `op raid spot at (6960,5888) value 64 defence 0.0 strength 1.4 units 1`.
  The new valuation cut the value 250 -> 64 but it remains positive, so the single Pawn still leaves. AWARE 2:30
  `ops 1 [1@6960,5888] pickets 0`.
- Why the lab was late: 0:51 `[ANV-OPEN] commander -> armlab (affordable now ...)`, then `[ANV-BUILDFAIL] armcom job 0 armlab`
  fails=1..13 from 0:51 to 1:20, every ~2 s: `dist` 197-344, `canPlace=1 sitePlace=1 onSite=0 cmds=0 vel=1.25`. The site is
  valid, but the commander circles 200-250 elmos off it with an empty command queue and never starts it; ~30 s lost, plus
  build time -> lab 1:39. Meanwhile energy WASTE 64/s at 1:00 (bank 817/1100 metal unused).
- 1:36: `MexPorc: armllt valued at extractor` - the first thing out of the build queue after the lab is a light laser at home
  (94 m) before any Pawn.
- Log ends at 2:30 (f=4583).

## Summary
Stopped at 2:00 (two samples) on buildings: static_m 495 vs 790 (and army 0 vs 120). Lead-in: the commander's lab order (0:51)
failed 13 times in 30 s (site valid, canPlace=1, commander 200-340 away with cmds=0 and moving), so the lab stood at 1:39
instead of ~1:15; 2 extractors only until after 2:30; energy wasted at 1:00. Focus: the first Pawn (2:19) still went alone
to the far SE corner (6960,5888, value 64 instead of 250 in swe13 - the change lowered the value but it stayed positive),
pickets 0 at 2:30. No raid had reached us before the stop, so the defence question is unanswered here.
