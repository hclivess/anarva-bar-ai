# Spectator notes: swe7 g00 - Anarva (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8, 1v1

(Ran between two of my checks; notes from the log.)

0:00 Opening: extractor 13 s, solar 23 s, solar 39 s, extractor 51 s, lab 1:14. Even at 1:00 (6.6 each).
1:14-3:25 Lab makes only fighters again: 8 Ticks, 7 Pawns, 1 Mace - no constructor. Commander expands alone (3rd extractor 1:45, 4th 2:19), out to 945 from base at 2:30. Good expansion by the commander.
2:00 Army 259 vs 129, income even (8.9), but energy 70 vs 97 - only 2 solars + 1 at 1:59 for a lab running non-stop.
2:00-3:00 Army splits: 2-3 units to the far enemy corner (7488,3728), 3-5 to mid (3735-4119, 3862-4131). Ticks die one by one at mid at 2:23, 2:57, 2:58, 3:16 - Ticks traded 0.09 (17 dealt, 191 taken), Pawn 0.00.
3:00 Metal income now ahead: 11.2 vs 8.9 (first time we lead at 3:00 in the series), army 442 vs 258 (ratio 8.6 on what we've seen). But energy 90 vs 131 and buildings 665 vs 850.
3:25 Game stopped by tools/swing.py (log ends f=6149).

## Result
- Stopped at 3:25, no winner. Stat that tripped it: energy income (70 vs 97 at 2:00, 90 vs 131 at 3:00) and/or buildings (615 vs 750, 665 vs 850) - both behind by more than a tenth two samples running. Metal income and army were ahead.
- What led to it:
  1. No constructors: only the commander builds, so it can't keep up both extractors and energy; 3 solars by 3:00 vs BARb's ~130 e/s.
  2. Ticks as the main fighter (8 of 16) - they die singly at mid for nothing (trade 0.09), wasting ~170 m.
- What it did well: metal income ahead of BARb at 3:00 (11.2 vs 8.9) with 4 extractors from the commander alone; lab 1:14; army 1.7x BARb's; a Mace in the mix.
- Stats at stop (3:00 sample): Anarva army 442 m, static 665 m, m_inc 11.2, e_inc 90, lost 3 (units); BARb army 258 m, static 850 m, m_inc 8.9, e_inc 131, killed 3.
