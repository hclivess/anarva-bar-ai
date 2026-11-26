# Spectator notes: swe24 g00 - Anarva (Armada, team 0) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Live remarks (game time):

- **0:00** Script loads clean, no anarva ERR. Start (1307,3328), middle of the west box. Lab values horizon is now sane: 1467 s at t=0, 841 s at 0:10, 566 s at 0:39 (swe23 had ~11000 s).
- **0:00-0:39** Commander: mex 9 s, solar 23 s, mex 39 s (`extractor first: spot 50 yields 162 before a constructor could build it`).
- **0:40** `commander -> armvp (lab: affordable now; income 6.6 M/s, 50 E/s covers its production (5.0 M/s, 72 E/s))`; lab values `armlab=1452 armvp=1838 armhp=993`. **Vehicle plant done 1:04** - inside the winners' 69-77 s window. The swe23 fix works.
- **0:10-1:53 REORDER**: 9 `[ANV-REORDER]` lines, **every one `cmds after 0`**: the engine does not keep a re-issued build order in the queue (re-issued from 9 to 222 elmos). The builds still happen a few seconds later (armvp after 3 re-orders at 104/111/145), so the build starts on a later tick, not from the re-order. Height is `260 vs 237` for the commander at three different sites (1112,3432), (1232,3520), (744,4072): the same pair at every site, so one side is probably a stale or constant read (a blind input). The armcv armrad reads `243 vs 237`. BUILDFAILs are down to 14 (swe23: 65).
- **1:05-1:29** **The first unit out of the plant is armmlv, a minelayer** (`[ANV-FAC] f=1941 execute armmlv`, finishes f=2668). After that come Rover (1:30-1:41), then Blitz (1:42-2:00). Winners build a constructor vehicle first, with Rovers between. Our first constructor vehicle is at **2:43**; more follow at 3:09 and 3:33.
- **1:30-2:00** The commander walks 806 -> 1208 from base (mex 1:34, solars 1:53/2:07, mex 2:28).
- **2:00** Even: army 141 vs 129, buildings 615 vs 650, m_inc 8.9 vs 8.9. **Energy 0/1200 from here to the end.** e_inc 70-100 against a pull of about 220 (`ePullReal 220`, EPLAN demandE 214-227). Only 3 solars and no winds all game.
- **2:30-3:00** The army (Rover + 2 Blitz) is sent to raid a far spot at (6960,5888) in the enemy corner: `op raid spot ... value 74`, army centre at (5384,3287), forward 0.68. Meanwhile Grunts walk into our base.
- **3:00** m_inc 8.9 vs 11.2, extractors 4 vs ~6+. Stat swing begins (income).
- **3:17-3:59** The Grunt raid kills extractors at (1216,3408) **in our base** (fromBase 0), (576,4608) and (624,4160), then solars at (744,4072), (728,4232) and (808,3368). We kill nothing: `dmg_out=0`, `armfav dealt 0 got 49`, MICRO `fired=0 noReply=1 outranged=1`. Defence op `pulled back ... enemy metal killed meanwhile 0`.
- **4:00** Stopped. Buildings 365 vs 1190, m_inc 4.3 vs 18.1, E 1/1300, damage dealt 0 vs 1785 taken, lost 6 buildings, killed 0. At the end the commander picks `15:-` (nothing) with energy at 0 and armsolar among its candidates. armlab (a second lab) is a candidate as well.

## Summary

- **Stopped** at the 4:00 sample (income swing from 3:00: m_inc 8.9 vs 11.2, then 4.3 vs 18.1; buildings 365 vs 1190).
- **Lab:** vehicle plant at 0:40, done 1:04. Fixed: winners' timing.
- **What led to it:** (1) the plant's first unit was a minelayer, then Rover/Blitz; first constructor at 2:43, so extractors stalled at 4. (2) Energy at 0 from 2:00 (3 solars, pull 220 vs income 80-100), so everything built slowly. (3) The army went raiding the enemy corner while Grunts raided our base. The Rover/Blitz fired 0 shots (outranged / no reply).
- **Extractors:** 3 at 1:34, 4 at 2:28, then 1 left at 4:00 (winners 3/6/8).
- **Placements/REORDER:** 14 BUILDFAILs (65 in swe23). Re-issued orders are never kept (`cmds after 0` in 9/9). The height pair 260 vs 237 is identical across sites, so it looks like a stale read.
- **Rework first:** the plant's opening queue. Constructor vehicles first, every 40-60 s (armmlv scored 2.05 per metal in the first PROD line), with energy planned for their draw.
