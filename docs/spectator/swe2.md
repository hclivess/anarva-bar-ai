# Spectator notes: swe2 g00 - Anarva (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8, 1v1

0:00 Opening: extractor 13 s, solar 23 s, solar 35 s, extractor 50 s, lab 1:15 - the fastest lab of the series so far. Even with BARb at 1:00 (6.6 each) and 2:00 (8.9 each).
1:40 Lab again starts with constructors: 1:40, 2:35, 3:03, 3:28, 3:48 (5 by 4:00), but two Pawns are out by 2:00 (army 108 vs BARb 86) - better than swe1.
2:00 Commander walks 878-1080 from base at 2:00-3:00 to claim extractors (3 -> 4 by 3:00): the right idea in an empty early map.
2:00-3:00 The two Pawns go to opposite far corners (6800,752 and 6960,5888), forward 0.69. They kill 43 m (3:00) but trade 0.83.
2:09/2:41 A solar and an extractor vanish with no enemy flag - looks like our own reclaim/replace, not a raid (ANV-DEAD with no flags).
3:17-3:55 Grunts arrive: extractor 3:17, constructor 3:27, solar 3:50, extractor 3:55 lost. Army called home (defend=3, ops at our west extractors 683,4006 / 30,3721).
4:00 Energy STALL with 5 builders. Metal income 8.9 vs BARb 13.5 (4:00) - BARb pulls ahead here.
5:00 Army concentrated: 13 units (702 m, strength 2372) at home vs BARb 527 m; ratio 3.0. Good: one group instead of singles. But Pawns trade only 0.52 vs Grunts (5:00), Ticks 0.22. Income 11.2 vs 20.4.
5:28 Game stopped by tools/swing.py (log ends f=9846).

## Result
- Stopped at 5:28, no winner. Stat that tripped it: metal income - ours 8.9 vs BARb 13.5 at 4:00 and 11.2 vs 20.4 at 5:00 (behind by more than a tenth two samples running). Buildings also behind (static 1555 vs 2310 m at 5:00); army was ahead (702 vs 527 m).
- What led to it:
  1. Grunt raid at 3:17-3:55 killed 2 extractors, a constructor and a solar; we held 2 extractors at 4:00-5:00 while BARb kept expanding.
  2. Five constructors from the lab by 4:00 but extractor count stuck at 3-4 (spots ours 1-2 in AWARE) - constructors rebuilt what the Grunts killed instead of reaching new spots.
  3. The first two Pawns spent 2:00-3:30 in the far corners of the enemy half instead of covering our own extractors when the Grunts arrived.
  4. Energy STALL at 4:00 (eInc 124) with 5 builders.
- What it did well: lab at 1:15, commander expanded out to ~1000 from base early, army of 13 concentrated at home by 5:00 with ratio 3.0 - the best army position of the series at that minute.
- Stats at stop (5:00 sample): Anarva army 702 m, static 1555 m, m_inc 11.2, e_inc 148, killed 1 / lost 8; BARb army 527 m, static 2310 m, m_inc 20.4, e_inc 211, killed 4 / lost 2.
