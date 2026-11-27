# Spectator: swe46 g00 (third start, owner's BAR closed) - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Loading was fast this time: no watchdog hang lines, already at f=7042 at the first check. Stopped by swing.py after the f=7200 sample (log ends f=7380, 4:06). No anarva script error.
(Earlier attempts: the first was stopped on purpose because the owner opened BAR; the second hung in loading with two engines plus the owner's BAR running.)

## Metal income and extractors per minute (ours / BARb / winners)
- 1:00: m_inc 6.6 / 6.6, mex 2 / 2 (winners 3)
- 2:00: m_inc 8.9 / 8.9 / 8.9, mex 3 / 3 (winners 6)
- 3:00: m_inc 11.2 / 13.5, mex 4 / 5 (winners 8)
- 4:00: m_inc 11.2 / 13.5 / 13.5-15.8, mex 4 / 5 (winners 12); `m=0/1300` (we spend everything), e=880/1550

Extractors built: `armmex t=9s`, `t=50s`, `t=96s` (commander), `t=168s`, `t=242s`.

## Constructors
Plant: `execute` armflash f=2181, armflash f=2637, **armcv f=3093 (103 s)**, armcv f=3953, armflash f=4817, armcv f=5429, armflash f=6261, armcv f=6473, armflash f=6909, armflash f=7297.
Built: `armcv t=131s`, `t=159s`, `t=207s`, `t=229s` (4 constructors; winners have one at 91 s, then the next ~76 s later).
First constructor's jobs: `134 s armcv -> 1:armnanotc | 1:armnanotc=45.45 ... 13:armmex=228.80`, then at once `134 s armcv -> 15:armcv` (assisting the plant's next constructor).
`162 s armcv -> 13:armmex` / `armcv -> 4:armsolar` (E 2/1350), with `ANV-MEXEXEC f=4884 armcv spot=36 ... dist=709`.
At f=5886-5987 (196-200 s) it is still 730 from spot 36 (`MEXIDLE ... spot=36 dist=730 ... vel=0.47`), then `197 s armcv -> 10:armrad`, `200 s -> 7:armllt`, `201 s -> 10:armrad`.
First constructor extractor: the commander builds the 168 s one (`168 s armcom -> 13:armmex`). The constructors' first extractor is most likely the 242 s one, about 110 s after the first constructor.
PICK lines carry no unit id, so the per-constructor split is inferred.

## Job switches (PICK changes per builder type)
armcv: 3 in minute 2, **23 in minute 3**, 6 in minute 4. armcom: 2 / 4 / 11 / 2.
The extractor <-> radar switching is still there, about every second from 215 s to 233 s:
`219 s armcv -> 13:armmex | ... 13:armmex=80.68`, `220 s armcv -> 10:armrad | ... 10:armrad=6.74 13:armmex=70.85`, `221 s armcv -> 13:armmex`, `222 s -> 10:armrad`, ... `229 s -> 13:armmex`.
The radar line's armmex value is the same size as in the extractor line (70-90), while radar reads 4.5-7.9 (lower is better). The two lines seem to come from two different candidate sets, one with radar and one without (the extractor-only line lists only `4:armsolar 13:armmex`).
This could be two constructors, but it alternates second by second.

## [ANV-CONVAL] spend
`N 1 H 300 ... spend 2.5 -> 2176`, `N 2 ... spend 2.4 -> 1683`, `N 3 H 328 ... life 328 ... spend 0.0 -> 1352`, `N 4 ... unemployed 1 ... spend 1.8 -> 0`, `N 5 ... spend 0.0 -> 1024`.
The spend term is 0-2.5 M/s and shows up. N 4 values 0 with one constructor unemployed.

## Army and fights (ours/BARb)
army 0/0, 220/129, 330/258, 550/484. Damage dealt/taken: 0/0, 0/0, 54/160 by 4:00. No kills either side.

## The stop
Metal income 11.2 vs 13.5 at f=5400 and f=7200 (damage share 54/160 at f=7200). Army ahead all game.

## Rework first
Constructor job choice: extractor <-> radar switching every second (23 switches in minute 3) persists after the self-share fix. The first constructor spends 134-242 s on nano, assist, a 730-away extractor it doesn't reach, radar and llt, and builds its first extractor ~110 s after leaving the plant. mex is flat at 4 from 3:00 to 4:00.
