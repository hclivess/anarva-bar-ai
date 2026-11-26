# Spectator: swe35 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=3600 sample (log ends f=3802, 2:07). No anarva script error.

## REORDER (new)
8 `[ANV-REORDER]` lines: 7 end `-> move first: refused too`, 1 has no suffix (the order held: `f=631 armcom armsolar at (1112,3432) from 80 ... cmds after 1`), none say `kept`.
Every line reads `height 260 vs 237 facing 1`. Examples:
- `f=301 armcom armsolar at (1112,3432) from 222 ... cmds after 0 -> move first: refused too` (and again at f=346, f=421) - the first solar is lost from 10 s to ~21 s.
- `f=1503 armcom armvp at (1232,3520) from 106 ... -> move first: refused too`, `f=1546 ... from 108 ... refused too` - refused inside the build distance of 145.
- `f=2842 armcom armsolar at (1160,3768) from 27 ... refused too`, `f=2882 ... from 63 ... refused too` (BUILDFAIL `onSite=1 [armcom ]`: the commander stands on the footprint).
The move-first order is refused as often as the build itself, at 27, 63, 106 and 222 alike, so distance is not the cause. Height 260 vs 237 is the only thing every line shares.

## Opener vs winners (9/16/31 extractors, 41/50 solars, 69 s plant)
`armmex t=9s`, `armsolar t=31s` (4 BUILDFAIL), `armmex t=49s`, `t=50s commander -> armvp` (2 BUILDFAIL), `built armvp t=71s` - plant on time.
No third extractor: at 74-76 s the commander switches between `13:armmex` and `15:armcv` (assist) every second, with `[ANV-BUILDFAIL] f=2263 armcom job 13 armmex ... dist=848`, then solars at 91 s and 106 s.
f=1800: m_inc 6.6 vs 6.6, e_inc 50 vs 80, static 255 vs 550.

## Plant and economy to 2:07
`execute armcv` f=2165 (72 s, `armcv=20.64` per metal; winners 91 s), `built armcv t=104s`, `execute armfav` f=3141, `execute armcv` f=3429.
f=3600: m_inc 6.6 vs 6.6 (winners 8.9), e_inc 100 vs 100, army 31 vs 146 (winners 155-265), static 565 vs 690, e=728/1300 (BARb 0/1300). `[ANV-CHECK] t=2m ... mex=2`.

## The stop
army+buildings behind in both samples: 255 vs 550 (f=1800) and 596 vs 836 (f=3600). Metal and energy income were level at 2:00.

## Rework first
The army: 31 metal (one Rover) at 2:00 against BARb's 146 and winners' 155-265, because the plant made constructor, Rover, constructor. Second: REORDER does not fix refused build orders (7 of 8 refused even from 27-106 away), so the cause is something other than range.
