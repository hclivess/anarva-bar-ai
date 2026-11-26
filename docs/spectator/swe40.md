# Spectator: swe40 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

Stopped by swing.py after the f=3600 sample (log ends f=3765, 2:05). No anarva script error. 23 BUILDFAIL lines (same as swe39), 1 STEPOFF line.

## Start
Same as swe39: `[ANV-START] chose (832, 2392) in box (0-1638, 0-6144)`, `[HARNESS] start team=0 x=832 z=2392`.
Second extractor (spot 30) 303-307 away (`MEXIDLE f=2636 armcom spot=30 dist=303`); players have it 104-167 away.

## Opener (players: extractors 9/16 s, plant 69 s)
`armmex t=9s`, `armsolar t=23s`, `t=24s commander -> armwin` fails 21 times again (f=721-2566, 24-86 s), but this time **not on its site**:
`f=1456 armcom job 4 armwin fails=8 dist=61 canPlace=1 | site dist=61 ... sitePlace=1 onSite=0 [] vel=1.25 ... buildDist=145 radius=24`,
`f=2566 ... fails=21 dist=103 ... onSite=0 [] vel=1.25`. The commander is within build distance (59-116 < 145), the site can be placed, nothing stands on it,
and it is still moving (vel 1.25) at every check. Something other than a blocked footprint is replacing or ending the order.
`t=86s commander -> armmex at spot 30`, `built armmex t=100s`, `t=101s commander -> armvp`, `built armvp t=122s` (players 69 s).
The single `[ANV-STEPOFF] f=3765 armcom off its armwin site (24 < 56)` comes at 2:05, after the opener. It is the wind job again, 21 failures after the first attempt.
f=1800: m_inc 4.3 vs 6.6, static 205 vs 550, `energy=WASTE 47.0/s banked=1020/1050`.

## 2:00-2:05
`execute armfav` f=3681 (123 s). f=3600: m_inc 6.6 vs 6.6, e_inc 50 vs 100, army 0 vs 146, static 255 vs 840.

## The stop
static 205/255 vs 550/840, army 0 vs 146, energy income 50 vs 70/100, metal income 4.3 vs 6.6 at f=1800.

## Rework first
The wind turbine order: a buildable site (canPlace=1, onSite=0) within range fails every 3 s while the commander keeps moving. Read what moves it (vel 1.25 at every check: a move or guard order taking over, the watchdog, or the wind site re-picked each pass at a new spot; dist jumps 61 -> 103 -> 116). Then the start: the same point gives a second extractor 300 away.
