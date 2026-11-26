# Spectator: swe34 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=3600 sample (log ends f=4102, 2:17). No anarva script error.

## Minute by minute
**0:00-1:00.** `armmex t=16s` after 3 failed starts (`[ANV-BUILDFAIL] f=226 armcom job 13 armmex fails=3 dist=201 canPlace=1 ... onSite=0 ... buildDist=145`),
`armsolar t=29s` (1 fail), `armmex t=44s`, then `t=45s commander -> armsolar` fails 13 times from f=1357 to f=1966
(`fails=13 dist=150 canPlace=1 | site dist=150 ... onSite=0 ... vel=1.08 ... buildDist=145 radius=40`): the commander hovers 149-173 from the site
with build distance 145 and never starts it for 20 s. `built armsolar t=75s`. Meanwhile `[ANV-CHECK] t=1m ... energy=WASTE 44.0/s banked=976/1100`.
f=1800: m_inc 6.6 vs 6.6, e_inc 50 vs 90, static 255 vs 550.

**1:00-2:17.** `t=76s commander -> armvp`, 2 failed starts (`f=2326 ... armvp fails=1 dist=27 ... onSite=1 [armcom ]` - the commander stands on its own site;
`f=2355 fails=2 dist=54 ... onSite=1 [armcom ]`), `built armvp t=99s` (winners 69-77 s; swe33 118 s, swe32 71 s).
Plant: `execute armfav` f=2993 (100 s), `execute armcv` f=3265 (109 s; winners 91 s), `built armcv t=133s`, `execute armcv` f=4017 (second constructor, no raiders).
Commander: `armcom -> 7:armllt` at 99 s - 3 fails `canPlace=0 ... onSite=2 [armsolar armllt ]` - `built armllt t=113s`, then `armcom -> 15:armcv` (assist) at 113 s,
extractor at 134 s (`f=4050 armcom job 13 armmex fails=1 dist=551`), solar at 136 s. No CommRedirect line in this game.
CONVAL: `N 1 H 253 ... first work 29 life 963 yield 1.06 -> 1854` (2:00).
`[ANV-CHECK] t=2m ... energy=STALL 152.7/s short ... mex=2`. f=3600: m_inc 6.6 vs 8.9 (winners 8.9), army 31 vs 146 (winners 155-265), static 495 vs 690, e=15/1200.

## The stop
Two samples behind: army+buildings 255 vs 550 (f=1800) and 526 vs 836 (f=3600); energy income 50 vs 90 and 70 vs 90; metal income 6.6 vs 8.9 at f=3600.

## Focus answers
- Plant time 99 s, 2 failed starts (commander on its own footprint). Opener total: 23 BUILDFAIL lines, 17 of them for solars.
- Commander 50-200 s: solar (13 fails, 45-75 s), lab, llt, assist, extractor, solar. Energy is a candidate now (`4:armsolar=89.68` at 113 s). CommRedirect: none.
- Energy income/min: 50/70 vs BARb 90/90.
- Plant mix: Rover, Constructor, Constructor - no raiders by 2:17.
- Army/income: 2:00 army 31, income 6.6 vs BARb 146 / 8.9.

## Rework first
Build starts: the commander stops 150-200 from a site with build distance 145 and retries (`onSite=0`, `canPlace=1`) - every opener job lost seconds, the 45-75 s solar lost 20 s and pushed the lab to 99 s.
