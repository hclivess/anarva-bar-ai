# Spectator notes: swe22 g00

Comet Catcher Remake 1.8, Anarvā (team 0, Armada) vs BARb hard (team 1, Cortex). Log: `runs/swe22/g00/infolog.txt`.
The AI reports itself as `Anarvā-stable`. No anarva script errors at startup (only the usual engine/widget noise).
The game sim ran very fast: the log reached f=13140 (7:18) after about 29 s of real time and then stopped growing.

## Remarks by minute

- **0:00** Start chosen at (1216,3408). The planning horizon is absurd: "lab values over 11590 s" (3.2 hours),
  `producer life 11590 s`. Lab values armlab=121963, armvp=136943, **armhp=142099**: the hover plant ranks first on a
  land map with water=0.0. Every start candidate's plan says `lab armlab@~107` (bot lab), while the live value line
  ranks armhp > armvp > armlab. The three disagree.
- **0:13** First extractor. Commander goes extractor, solar, solar, extractor (0:54), solar (1:06). Every line says
  "metal x/s short of 6.7; energy y/s short of 90", so the lab is held back until income covers its full rate.
- **1:00** 2 extractors, energy WASTE 64/s, metal 781/1100 banked. The lab could have been paid for from the bank
  already. Winners have their vehicle plant at 69-77 s.
- **1:07** Commander walks 778 out to a third extractor (built 1:32) instead of building the lab.
- **1:33** Commander -> armwin: "energy 90/s short of 90". **A boundary bug: 90 is not short of 90.** It then fails
  to place the wind 102 times (`[ANV-BUILDFAIL] ... armwin fails=1..21 canPlace=1 onSite=0`, sometimes
  `onSite=1 [armcom]`: the site is under the commander itself). The job times out (`JOBEND ... timeout=757`) and is
  picked again, forever. **No lab is ever built and no wind is ever finished.**
- **2:00** Us: 3 extractors, army 0, metal 1070/1150 (overflowing), commander 850 from base. BARb: army 129, 12 units,
  e_inc 97. Winners have 3 extractors at 2:00, so the count matches, but they also have a plant and constructors.
- **3:00** Us: 3 extractors, army 0, metal **1150/1150 full**. BARb: army 172, static 850, m_inc 13.5. Winners: 6.
- **3:11** First raid: Grunts (corak) kill the start extractor, then three solars (3:22, 3:38, 3:46), the extractor
  at (1296,3776) at 3:52 and the far one at 4:05. `[ANV-ENEMY] t=4m corak:2`, strength 287. The commander was 935-1010
  from base and never engaged two Grunts, which a commander beats on its own.
- **4:00** Us: 1 extractor, m_inc 4.3, dmg_in 1533 / dmg_out 0. BARb: army 301, m_inc 18.1. Winners: 8.
- **5:00** Us: 0 extractors, 1 unit (the commander). BARb: army 473, m_inc 20.4. Winners: 12.
- **5:10-6:51** Commander restarts the exact same sequence elsewhere: extractor, solar, solar, extractor, solar,
  extractor, then armwin with "energy 90/s short of 90" and the same endless placement failure from 6:52.
- **7:00** Us: 3 extractors, army 0, m_inc 8.9. BARb: army 1033, static 3240, m_inc 27.2, 56 units. Log ends 7:18.

## Summary

**Stop.** The log stopped growing at f=13140 (7:18). swing.py should have stopped it by 2:00 (army 0 vs 129) and
certainly by 4:00 (dmg 0 vs 1529, extractors lost). Either the swing rule did not fire on these stats or it stopped
the game late. The caller should check.

**What led to it.** We never built a lab. The opener holds the lab until income covers its full rate
(`metal short of 6.7; energy short of 90`) while metal sits full in the bank. Then a strict-inequality bug,
`energy 90/s short of 90`, keeps choosing a wind turbine that fails to place 102 times
(`canPlace=1`, site under or near the commander, job timeout, picked again). With no army, two Grunts took
everything from 3:11 on.

**Focus answers.**
- **Lab:** none built. Lab values ranked armhp > armvp > armlab all game, so a hover plant on a dry map would have
  been the pick. The start plans assumed armlab@~107 s. The horizon of 10-11k s inflates every value.
- **Extractors per minute:** us 2/3/3/1/0 at 1-5 min, against winners' 3/6/8/12 at 2-5 min. BARb's static_m went
  400 -> 600 -> 850 -> 1040 -> 1480.
- **"Raiders due":** no `[ANV-CMD]` and no "raiders due" or "stay home" line at all, although `[ANV-OPEN] earliest
  raid` predicted 102-150 s and the Grunts arrived at 191 s. The commander was 800-1000 from base when they came.
- **Raid cost:** the start extractor, 3 solars and the 2 remaining extractors: about 630 metal, all income. We
  dealt 0 damage.
