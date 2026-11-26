# Spectator notes: swe25 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Live remarks (game time):

- **0:00** Script loads clean, no anarva ERR. Same start as swe24 (1307,3328). Lab values over 1467 -> 566 s.
- **0:00-0:45** Commander: mex 9 s, solar 23 s, mex 45 s. `t=46s commander -> armvp (lab: affordable now ...)`, values `armlab=1478 armvp=1864 armhp=1018`. **Vehicle plant done 1:07** (winners 69-77 s).
- **1:00** Buildings 255 vs BARb 550 (BARb has placed more early solars/winds). Energy 549/1050 against BARb's full 1100.
- **1:08 plant queue**: `armvp -> armcv as constructor (per metal 20.64; armmlv=4.72 armfav=12.96)`, so the **constructor vehicle comes first** (started f=2045, **done 1:40**). Then Rover (f=3045), Blitz (f=3329), Blitz (f=3797), and a constructor vehicle again at f=4249 (2:22). The minelayer is no longer first. This matches the winners' pattern (constructor, then raiders between), but the second constructor comes 42 s after the first one finished, behind three raiders.
- **REORDER**: 5 lines, all `cmds after 0`. The height is still `260 vs 237` at (1112,3432), (1232,3568) and (1192,3720), the same pair at every site. 10 BUILDFAILs.
- **1:40-2:20 stay home**: a long run of `stay home: raid spot ... worth 29-74 <= home 103 (7.8 raiders due, 2-3 fighters)`. This repeats every tick over the same 9 spots, so it is log spam, but the decision is sound.
- **2:00** Army 141 vs 120, buildings 565 vs 690, m_inc 6.6 vs 7.7, energy 706/1300 (no stall this time; e_inc 100 = BARb). Extractors: 3 (9/45 s, plus one at 2:14), then 4 at 2:24. Winners have 3 at 2:00.
- **2:00-2:25** The army still went out: `op enemy 26093 at (6071,1049) value 273` (a corgator near the enemy base), then `pull back ... strength 3.6 <= defence 8.7`. Then it took `op raid spot (6960,5888) value 99`, followed by `recall raid at (6960,5888): it gains 14, meeting the corgator at (5894,1195) saves 52`. **The new recall fires.** The Rover died at 2:25 at (6153,1161), 5424 from base, to a corgator. First loss: 31 metal, no kill. The army centre was back home (1341,3481) at 2:30.
- **2:30** `[ANV] next factory: armlab`: a second lab is chosen at 2:30 with 4 extractors and one constructor vehicle. The constructor vehicle picks armllt (`armcv -> 7:armllt`). Log ends f=4520 (2:31).

## Summary

- **Stopped** at about 2:31, after the 1:00 and 2:00 samples both favoured BARb on buildings (255 vs 550, 565 vs 690; m_inc 6.6 vs 7.7 at 2:00). Army, damage and energy were even or ahead.
- **Plant queue:** constructor first (done 1:40), then Rover, Blitz, Blitz, constructor at 2:22. Fixed: the minelayer no longer goes first. The second constructor comes behind three raiders.
- **Recall:** fired at about 2:20, but only after an op into the enemy base corner. The Rover died there at 2:25 (31 m). No Grunt raid on our base before the stop.
- **Extractors:** 3 at 2:14 and 4 at 2:24, against winners' 3/6.
- **Energy:** healthy (706/1300, income 100).
- **REORDER:** still `cmds after 0`; the height pair `260 vs 237` is constant.
- **Rework first:** the early economy build rate. BARb is 300 metal of buildings ahead at 1:00. Our commander builds one solar in 45 s and walks to extractors, while the winners' commander builds winds at base. A second constructor before the Blitzes would follow from the same reason (extractors at 3:00 = 6).
