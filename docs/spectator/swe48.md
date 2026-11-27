# Spectator: swe48 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Loaded fine. Stopped by swing.py after the f=9000 sample (log ends f=9466, 5:15), our longest game so far. No anarva script error.

## Extractors and income per minute (ours / BARb / winners)
- 1:00: mex 2/2/3, m_inc 6.6/6.6
- 2:00: mex 3/3/6, m_inc 8.9/8.9 (winners 8.9)
- 3:00: mex 4/5/8, m_inc 11.2/8.9
- 4:00: mex 4/5/12, m_inc 11.2/13.5 (winners 13.5-15.8), `m=0/1300`
- 5:00: mex 5/7, m_inc 13.5/18.1, `m=0/1350 e=1592/1600`
Extractors built: `t=9s, 50s, 98s, 164s, 298s, 305s, 307s` (one lost at 217 s).

## Who builds the solars
Mostly the commander now: `98 s armcom -> 4:armsolar`, `165 s armcom -> 4:armsolar`, `201/205/206/216/237/250/282 s armcom -> 4:armsolar`.
A constructor picked a solar once: `162 s armcv -> 4:armsolar | ... 4:armsolar=115.80 13:armmex=120.73 | M 296/1250`. Solars built at 113, 183, 194, 313 s.
Energy ends full again (1592/1600) with metal at 0.

## What constructors build, and time to first extractor
Plant: armflash, armflash, armcv f=3093 (103 s), armcv f=3957, armflash, armcv f=5285, armflash, armflash, armcv f=6797, armcv f=7317, armflash, armcv f=8205, armflash.
Built `armcv t=131s, 159s, 201s, 243s, 258s, 303s`.
- First constructors: `133 s armcv -> 1:armnanotc | ... 13:armmex=8584.71`, `134 s armcv -> 15:armcv` (assist), `149 s armcv -> 1:armnanotc | ... 13:armmex=48527.96`.
  The extractor value is huge (worst) for the first constructors at 133-149 s; no extractor job for them until 194 s.
- At M ~20 (194-205 s) they cycle llt/radar/extractor: `195 s armcv -> 10:armrad | ... 10:armrad=2.91`, `198 s armcv -> 7:armllt`, `198 s -> 10:armrad`, `201 s -> 13:armmex`, `202 s -> 10:armrad`, `203 s -> 7:armllt`.
  Then nano/assist at M 0: `222 s armcv -> 1:armnanotc | 1:armnanotc=17.49 ... 13:armmex=643.78 | M 0/1300`, `228 s armcv -> 15:armcv`.
- First constructor extractor order: `MEXEXEC f=6392 armcv spot=45 dist=255` (213 s), then f=7603 spot 43, f=7900 spot 22, f=8688 spot 50, f=9282 spot 38.
  The first constructor reached its first extractor job ~82 s after it was built; the constructor-built extractors only stand at 298-307 s.
- PICK changes: armcv 3 / 29 / 2 / 1 in minutes 2/3/4/5; armcom 3 / 20 / 7.

## Extractor losses and defence
`[ANV-DEAD] t=217s armmex m=50 at (1216,3408) fromBase=1074 ... nearestEnemy=corak@128` (the commander's far extractor, spot 36 at 834).
The army does recall now (the new defence value):
`recall raid at (7296,5552): it gains 119, meeting the corak at (1213,3623) saves 6151`, `... saves 6438`, `... saves 6227`, then
`op enemy 25953 at (1213,3623) value 5725 defence 1.1 strength 6.5 units 4 loss~13`.
It is chasing one Grunt: `[ANV-FIGHT] f=7110 op enemy 25953 at (826,4007) ended after 21 s: target gone, metal sent 550 left 550, enemy metal killed meanwhile 0`, then
`f=8520 op enemy 25953 at (894,3159) ended after 42 s: target gone, metal sent 660 left 660, enemy metal killed meanwhile 43`.
The 5725-6438 "saves" for one 43-metal Grunt are the same order as the old 5297-6643 (the swe32 issue).
Damage dealt/taken: 115/99 (3:00), 316/906 (4:00), 632/1229 (5:00).

## The stop
Metal income 11.2 vs 13.5 (f=7200) and 13.5 vs 18.1 (f=9000); damage share 316/906 and 632/1229. Army 550/581, 660/796.

## Rework first
The first constructors' jobs: for 133-213 s they build nano, assist, llt and radar, with extractor values of 8584-48527 at 133-149 s. They reach an extractor 82 s after leaving the plant, and mex goes 3 -> 5 in three minutes. Second: the recall's "saves 6151-6438" for one Grunt pulls the whole army after a scout it never catches.
