# Game checklist

Every game Anarvā plays is assessed with these questions (owner, 2026-11-25, #92). A test is read against this
list before anything else. The final score against BARb comes last: an army that never moves is visible in
minute 3 of the log without another match.

**How:**
- The AI writes one `[ANV-CHECK]` line per game minute (`Brain::Check` in `brain.as`).
- `python tools/check_game.py runs/<batch>/g00 ...` turns those lines, plus the harness's true values for both
  teams, into a table and the verdicts below.
- It sets Anarvā's army beside the top 1v1 winners' at the same minute (`runs/replays.db`).

Every verdict is a measured condition, not a cutoff.

## Economy

| Question | Measured as | Fails when | What it means |
|---|---|---|---|
| Am I overflowing (wasting) metal? | storage full and metal income > spending | any minute | build power or factories can't spend the income: more production capacity, or the metal went to the wrong jobs |
| Am I stalling metal? | spending > income and the stock can't cover one second of the deficit | any minute | more spending is queued than income supports; expansion is behind |
| Am I overflowing energy? | storage full and energy income > spending (converters' draw counts as surplus) | any minute | energy over-built, or converters missing |
| Am I stalling energy? | spending > income (without converters) and the stock can't cover one second | any minute | everything builds at the energy's pace: the energy plan lags what our factories need |
| Are builders idle while metal is wasted? | constructors with no job in a wasting minute | any minute | jobs are missing or not offered (pick log `[ANV-PICK]` shows what was) |
| Is a factory idle? | a factory with no job | any minute | production stopped: no affordable unit, energy stall, or a blocked decision |

## Army

| Question | Measured as | Fails when | What it means |
|---|---|---|---|
| Is my army value too low? | our armed mobile metal vs the top 1v1 winners' at the same minute, and vs the enemy's true army | below either | not enough production, or spent elsewhere |
| Is my army value too high for what it does? | our army metal > the enemy's true army, yet no unit on an attack or raid task | any minute | idle army = expansion opportunity cost (#84): it should fight where it wins, or it shouldn't have been built |
| Is my army moving at all? | army units that covered at least one second of their own top speed since the last minute | no unit moved | the army isn't being used |
| Is it fighting? | units on attack / raid / defend / no task; metal killed and lost per minute | killed 0 for minutes while stronger | it moves but doesn't engage, or engages badly |
| Does it trade well? | metal killed vs lost per minute | lost > killed for minutes | bad fights: wrong targets, wrong composition, fighting into turrets |

## Micro (every second)

Micro is judged per second, not per minute (owner, 2026-11-25). Every second, each army unit in contact (an enemy
within its weapon reach, or it lost health) records whether it fired, was hit without replying, was outranged
(hit with no enemy in its own reach), had a target in reach but did not fire, or stood still while hit. Each squad's
spread is measured too: the mean distance from its centre, in its units' reach. `[ANV-MICRO]` lines are written for
seconds with contact, and the minute line carries the totals.

| Question | Measured as | Fails when | What it means |
|---|---|---|---|
| Do units shoot when they can? | unit-seconds with an enemy in reach and no shot, vs unit-seconds firing | idle-in-reach > firing | targeting, fire state or facing is wrong |
| Are we losing the exchange? | hit without firing back, vs firing | no-reply > firing | caught out of position, outranged, or fighting into turrets |
| Are we outranged? | hit with no enemy in our reach, vs firing | outranged > firing | the enemy out-reaches us: close in fast, pull back, or bring range |
| Do units stand still under fire? | hit while not moving | any | no kiting, dodging or retreat when it pays |
| Is the squad together? | squad spread in reach units | (read with the fight) | strung-out squads fight piecemeal: the square law punishes that |

## Reading order

1. Check whether the economy wastes or stalls. Fix that first, because every other number follows from it.
2. Check whether the army exists, moves and fights, then the per-second micro.
3. Check whether it trades well.
4. Only then look at the score against BARb.

Each failure gets an issue with the minute it appears and the log lines that show it.
