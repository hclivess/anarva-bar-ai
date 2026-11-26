# Spectator notes: swe31 g00 - Anarva vs BARb hard (Cortex), Comet Catcher Remake 1.8 (constructor claims valued over producers' survival)

- **0:00-1:17 commander**: extractor 9 s, solar 24 s, extractor 42 s, solar 53 s, plant 54-77 s (the same opener as swe30, 3 s later). The third extractor before the plant is still missing.
- **1:00** Buildings 410 vs 550, energy 1069/1100.
- **Plant queue**: constructor (F2345, `per metal 21.92`, **done 1:46**), Rover (F3217, `11.90` vs constructor 1.28), constructor (F3493, **done 2:34**), Blitz (F4653), constructor (F5193, about 2:53). Constructor times: **106 / 154 / ~180 s**; winners 91/167/249. So we are now at or ahead of the winners' constructor pace, and the plant makes almost no army.
- **[ANV-CONVAL] H**: 1467 -> 794 -> 589 (pre-plant), then 662, 407, 601, 816 once spots are claimable. Result 3422 / 952 / 2261 / 2323. N = 1-3. The horizon swings 407-816 between consecutive evaluations.
- **2:00** Total value ahead: army 31 + buildings 845 vs 146 + 690. Income 8.9 vs 6.6. Energy 261/1250.
- **Extractors**: 9 / 42 / 108 / 146 s, so 2 at 1:00, 3 at 1:48, 4 at 2:26. Winners 3/6 at 2/3 min. The constructors have not yet turned into extractors by 3:00 (about 4-5).
- **2:30-3:09 fighters**: one Rover, one Blitz. The Rover traded 0.61 (`dealt 35 got 59`); MICRO `fired=1 ... outranged=1`. No kills either side. The recall fires 5 times on `the corfav at (733,4827) saves 11502`: a single 31-metal scout valued at 11500, worse than swe30's 5000-6600. The army is pulled around after a scout.
- **3:00** Army **141 vs 386**, buildings 945 vs 1000, income 11.2 vs 13.5, **energy 0/1350** (EPLAN demandE 138-176 vs income 110; pull 238). Stopped about 3:09 (log ends f=5686) on total value (1086 vs 1386).

## Summary

- **Stopped** at about 3:09 on total value: army 141 vs 386 at 3:00, income 11.2 vs 13.5. 2:00 was ahead.
- **Constructors:** at 106 / 154 / ~180 s (winners 91/167/249). The change worked: the plant now builds constructors.
- **CONVAL H** 407-816 at play, unstable between calls.
- **But:** the army is only Rover + Blitz at 3:00, and energy is at 0 under the constructors' build draw. Extractors are 4 at 2:26, still behind the winners' 6 at 3:00.
- **Fighters:** they chase. The recall values one corfav scout at 11500 and pulls the army after it. No kills.
- **Rework first:** the recall value. The threat's "saves" should be bounded by what it can kill before our response arrives (its DPS times its time near our buildings). A 31-metal Rover-class scout should not outweigh everything else.
