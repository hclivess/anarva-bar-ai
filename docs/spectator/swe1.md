# Spectator notes: swe1 g00 - Anarva (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8, 1v1

(The game ran at several times real speed and finished between two of my checks; notes from the full log runs/swe1/g00/infolog.txt.)

0:00 Opening: extractor 13 s, solar 23 s, solar 36 s, extractor 48 s, lab 1:22. Commander then wastes energy at 1:00 (WASTE) with 823 metal banked.
1:44-3:38 Lab makes constructors 1:44, 2:09, 2:41, 3:01, 3:38, 4:35, 6:16 - seven constructors; the army is 1 Pawn until 4:00 (army_m 54 at 2:00-3:00, 75 at 4:00 vs BARb 258/594).
2:00 First Pawn sent alone across the map to the far corner (6800,752), then on to (7584,5200): forward 0.84 at 3:00. One Pawn touring the enemy half while Grunts come to ours.
3:00 Metal income 6.6 vs BARb 13.5 (6.6 vs 8.9 at 2:00): by the swing rule (behind >10% two samples running) this game was lost on metal income from 2:00-3:00. Energy STALL at 2:00 and 3:00.
3:22-4:00 Grunts inside: extractor 3:22, solar 3:23, extractor 3:54, solar 4:03, radar 5:16 lost. Extractors held: 2 (ours) all through minutes 4-9.
4:00 Pawns that do fight trade well (0.97 at 4:00, 1.29 at 5:00) - but there are only 1-2 of them. Army ratio 0.2 at 4:00.
4:00-9:00 Metal STALL every minute (12.5 / 37.5 / 16.7 / 37.1 / 1.4 / 11.8 per s short) with 7-8 builders: too many constructors for the income, and the extractors they build die (6:43, 7:15, 7:47, 7:58, 8:19).
7:00 Centurion appears (one), deals 122-1484 dmg for 0-753 taken: by far the best-trading unit, but only 1 built against 21 Pawns and 17 Ticks.
9:00 Army 10-11 (756 m) moves out to (5744,2336), forward 0.61, while BARb's army is 594 -> 2016 m. At 9:30-10:00 the raid group of 6 Pawns + Centurion dies at (5300,2000-2500) in 30 s.
10:00 Simultaneously BARb's Grunt wave x12 hits the base: advanced bot lab (just started) lost 10:12, con turret, 8 solars, radar 10:00-10:26. Commander is 1434 from base at 10:00 - away expanding when the base is hit.
11:00 Lost 3327 m that minute. Ratio 0.3. Ticks keep coming from the lab (17 total) and die at 0.16-0.42 trade.
12:00-13:00 BARb tier 2 arrives: Thud x9, Storm x4. Our army 9-12 units, strength 1339-1522 vs 3988-5365.
13:44 Commander killed by a Thud at base along with lab, con turrets, solars. Game over 13:50 (f=24901).

## Result
- Ended 13:50, BARb wins (commander killed 13:44 by Thud). The swing stop (tools/swing.py) did not cut this game; by its own rule it would have stopped at ~3:00 on metal income (ours 6.6 vs BARb 8.9 at 2:00, 6.6 vs 13.5 at 3:00), led by the late, single-Pawn army and the constructor queue while Grunts killed the first extractors.
- What cost it:
  1. Constructor-heavy lab (7 constructors, army 54 m until 4:00) with income too small to feed them: metal STALL 12-37/s every minute 4:00-9:00.
  2. Grunt raids unanswered: 2 extractors held for 5 minutes; 20 extractors lost over the game.
  3. Lab output mix: 17 Ticks (trade 0.16-0.50) and 21 Pawns vs 1 Centurion, which traded 1.5-2.0 - the strongest unit was built once.
  4. Army and commander away (raid at 5300,2000; commander 1434 out) exactly when BARb's 12-Grunt wave hit the base at 10:00; lost 3327 m in minute 11.
  5. No answer to tier 2 (Thud/Storm) at 12-13 min; no tier 2 of our own (advanced lab died while building).
- What it did well: Pawns traded >1 when grouped (1.29 at 5:00, 1.36 at 9:00); radar early (4:05); extractors rebuilt persistently; light lasers at raided spots.
- Final stats: Anarva units 0, killed 37 / lost 110 (harness units), dmg out 26441 / in 36982. BARb units 147, army 4095 m, static 12492 m, m_inc 50.7, e_inc 928, killed 59 / lost 41, dmg out 36849 / in 26752.
