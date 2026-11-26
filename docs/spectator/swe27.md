# Spectator notes: swe27 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8 (same AI as swe26)

Live remarks (game time):

- **0:00-1:01** Commander: extractor 9 s, solar 23 s, extractor 39 s, plant done 61 s. Same pattern as swe25/26.
- **1:02 plant queue**: constructor vehicle first (F1865, done 1:34), then Rover, Blitz x3 (F2849-F4041), constructor x2 (F4481, F5065), Blitz, Rover, constructor, Blitz x4. Constructor vehicles done at 1:34, 2:48, 3:16 and 4:26. The constructor-first order came back with the same code that put the Rover first in swe26, so this choice is sensitive to the game state.
- **1:00** Buildings 255 vs 550, energy 324/1050 against BARb's full bank.
- **1:47** `[ANV-DEAD] armsolar at (1192,3752) fromBase=344 nearestEnemy=none`: a solar lost with no enemy near. Probably reclaimed (Recycler?). Another at 3:36 at (984,3432), flags=4. **Check who removes our solars.**
- **2:00** Army 141 vs 120, buildings 615 vs 690, income 6.6 vs 7.7, energy 831/1300. Extractors: 2. Winners have 3.
- **2:17** Extractors 3-4 (134/137 s).
- **2:18-3:30** The raid ops all go to the enemy corners: (6800,752), (6960,5888), (5904,5632), (6352,592). `enemy metal killed meanwhile 0` in all 9 FIGHT lines up to f=6300, several of them `target gone` (empty spots).
- **3:00** Army 361 vs 240, buildings 895 vs 1130, income 11.2 = 11.2, **energy 1/1350** (stall), while BARb has 1115.
- **3:35-3:51** Rover (6148,832) and Blitz (6708,724) die deep in the enemy corner, 5564-6113 from base.
- **4:00** Even: army 361 vs 360, buildings 1420 vs 1400, energy full (1500/1500) and metal at 0. Damage 1383 out vs 925 in. Blitz trade **1.59** (`armflash dealt 1349 got 845`). Rover 0.5.
- **4:19 / 4:26** Incisors kill extractors at (1408,2800) and (624,4160), 637 and 957 from base. No picket. The army is out at the enemy corner.
- **4:20-5:00** `recall raid at (5168,384): it gains 53, meeting the corgator at (6910,320) saves 997-1294`, repeated 6 times. The "threat" is a corgator in the *enemy* corner, so this recall sends the army further out, not home. The home defence op at (1702,2644) `pulled back ... killed 0`; the one at (934,2695) killed 240.
- **Extractors**: 2 at 1:00, 4 at 2:17, 6 at 4:28, 8 at 5:11. Winners 3/6/8/12 at 2/3/4/5 min: we are about 1-1.5 min behind.
- **5:00** Army 691 vs 460, buildings 1800 vs 1700, income 13.5 = 13.5, damage 2791 vs 3038. Blitz trade 1.68. Stopped on kill share 0.40 vs 0.43 (a swing.py margin bug, fixed by the coordinator).

## Summary

- **Stopped** at 5:00 on kill share (0.40 vs 0.43), while ahead on army (691 vs 460) and buildings (1800 vs 1700), with income level. The stop was a swing.py margin bug, not being outplayed.
- **Fights:** Blitz trades 1.59-1.68. Raids on spots killed 0 in 9 ops (empty spots in the enemy corner). Units died 5500-6100 from base.
- **Recall:** it fired, but toward a corgator in the enemy corner (6910,320), not to defend. The Incisors that killed 2 extractors at 4:19/4:26 went unanswered.
- **Extractors:** 4/6/8 at 2:17/4:28/5:11, about a minute behind the winners.
- **Energy:** stalled at 3:00 (1/1350), full at 4:00.
- **Rework first:** where the army goes. Raids on empty far spots and a recall pointed outward while home extractors die. The threat measure for "our buildings" should use the distance from the threat to our buildings.
