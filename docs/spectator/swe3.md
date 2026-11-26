# Spectator notes: swe3 g00 - Anarva (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8, 1v1

0:00 Opening: extractor 13 s, solar 23 s, solar 35 s, extractor 51 s, lab 1:16. Level with BARb at 1:00 (6.6) and 2:00 (8.9 each); our army 108 vs 43 at 2:00 - a good start.
1:30-2:30 Commander goes out to claim extractors (522 -> 994 -> 1295 from base); extractors 2 -> 4 by 3:00. Good.
2:00-3:00 The first three Pawns are each sent ALONE to three far enemy corners (6800,752 / 6960,5888 / 7488,3728). One dies at (6406,1005) at 3:24. Same single-Pawn-to-the-corner pattern as every game this series.
3:00 Income still even (11.2 vs 11.2) but army now behind: 162 vs 215 m. Lab is making constructors (1:41, 2:47, 3:12, 3:56, 4:15).
3:29 7 Grunts arrive and an extractor (1408,2800) falls. Army is at (3841-4812, ...) forward 0.46-0.58 - out of position, not at home. Army re-tasked to defend (1423,2843) at 4:00.
4:00 Behind on everything that counts: metal income 11.2 vs 15.8, army 183 vs 430 m, static 1505 vs 1910. Pawns trade 0.61 against the Grunts.
4:17 Game stopped by tools/swing.py (log ends f=7728).

## Result
- Stopped at 4:17, no winner. Stats that tripped it: army - ours 162 vs BARb 215 m at 3:00 and 183 vs 430 m at 4:00; metal income 11.2 vs 15.8 at 4:00 (buildings 1505 vs 1910 too).
- What led to it:
  1. The first three Pawns went one by one to three far enemy corners at 2:00-3:00 (one died there at 3:24); when 7 Grunts came at 3:29 the army was at forward 0.5 and our extractor at (1408,2800) fell.
  2. Lab kept making constructors (5 by 4:15) instead of fighters while BARb doubled its army between 3:00 and 4:00.
  3. Pawns trade 0.61 against Grunts (ANV-TRADE t=240s).
- What it did well: lab 1:16, commander expanded to 4 extractors by 3:00, income and army level or ahead at 2:00.
- Stats at stop (4:00 sample): Anarva army 183 m, static 1505 m, m_inc 11.2, e_inc 158, lost 2 (units); BARb army 430 m, static 1910 m, m_inc 15.8, e_inc 191, killed 2 / lost 1.
