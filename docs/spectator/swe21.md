# swe21 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Change under test: a free unit raids an empty enemy spot only if that beats what it saves at home against the
predicted first raid ("stay home" lines).

## Remarks by minute

- **0:00-0:52** Commander: extractor (t=13s), solar, solar, extractor (t=51s). Then `t=52s commander -> armlab`.
  Two `[ANV-BUILDFAIL]` on the lab (f=1561 canPlace=0 at dist 145; f=1602 dist 301) before it started.
  Lab stood at **t=77s** (`[ANV] built armlab t=77s`). Its first unit was a constructor (t=102s), then Pawns.
- **1:57 (f=3510)** First "stay home" line: `raid spot (7584,5200) worth 81 <= home 108 (7.9 raiders due, 1 fighters)`.
  `hold at (1216,3408): mean distance 333 to 3 extractors and the base`. From here on every free Pawn stayed home: 693
  stay-home lines, no raid op launched. The decision did what it was meant to.
- **Suspect inputs:** `7.9 raiders due` and `home 108` never change from 1:57 to 4:39, whether 1, 2, 3, 4, 5 or 7
  Pawns are free and after the raid had already come and gone. The prediction is not updated from what was seen
  (BARb sent 2 Grunts, not 7.9 raiders). The home value does not depend on how many fighters there are.
- **2:00** Pawns 2 (108 m) at (1033,3402) next to the base; 3 extractors (BARb 3). Commander 778 from base.
- **3:00** Pawns 4 (216 m) at (1190,3410), forward 0.00 - at home as intended. But our economy: 3 extractors vs BARb 5,
  m_inc 4.3 vs 13.5, energy STALL 223 E/s short (`[ANV-CHECK] t=3m`). Swing sample 1 against us.
- **3:06 (f=5580)** First Grunt (28011) seen at (1556,3113), ~370 from base. 3 Pawns engage it at once; it left after
  4 s (`ended after 4 s: target gone`), the Pawns followed it out to (1831,3280) and later (2967,2321) (forward 0.33).
  So the first raider was met, at the base, about 3:06.
- **3:27 (f=6210)** Second Grunt (25030) hits the far extractor at (661,4427), 957 from base.
  `detach 2 units to defend (661,4427) value 11982: strength 2.3 > 2.2`. The 2 Pawns arrive and fire at 3:36 (f=6480),
  but the Grunt kills solar (3:39), extractor (624,4160) (3:39) and another solar (3:41) - 2 Pawns vs 1 Grunt and the
  micro log shows `outranged=1` / `noReply=1` (Grunt kiting). The defence came 9 s after the first hit and was too thin
  to stop it.
- **4:00 (f=7198)** The first Grunt (28011), which the 3-Pawn op had been chasing toward the enemy, doubled back and
  killed an advanced solar being built (7%) at (944,3424), 272 from base. The home group was out of position: it had
  followed the raider away instead of holding the extractors.
  `[ANV-TRADE] t=240s armpw dealt 372 got 165 (2.25)` - Pawns traded well, but did not kill a Grunt
  (killed_m 0 at 4:00; enemy metal killed 43).
- **4:00** Swing sample 2 against us: m_inc 6.6 vs 20.4, army_m 270 vs 605, extractors 2 vs 8, BARb has 180 m of
  defences. Energy still STALL. Log ends at f=8550 (4:45).

## Summary

Stopped at ~4:45 (last line f=8550) after the 3:00 and 4:00 samples both favoured BARb by far more than a tenth:
metal income 4.3 vs 13.5 and 6.6 vs 20.4 (army_m 216 vs 312, 270 vs 605 also). The cause is economic, not the
fight: 3 extractors at 3:00 and 2 at 4:00 against BARb's 5 and 8, plus an energy stall from 3:00 on.

Focus: yes, the free Pawns now stay home in minutes 2-3 (693 stay-home lines from 1:57, army forward 0.00 at 3:00),
and the first Grunt was met at the base at 3:06. But (a) the inputs are frozen (7.9 raiders due, home 108 at any
fighter count), (b) chasing the first Grunt pulled the group away, so it came back and killed the advanced solar at
4:00, and (c) the second Grunt at the far extractor (957 from base) met only 2 Pawns 9 s late: lost 1 extractor and
2 solars there. Lab: ordered 52 s, two failed starts, stood 77 s.
