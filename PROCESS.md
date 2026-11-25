# The process: think like the player, then close the largest gap

Owner, 2026-11-25: "you now see far beyond barbs limitations but you must learn to use your sight, build a process".
This loop is run every time. No step is skipped, and nothing is fixed outside it.

## 1. Decisions: is every player decision ours?

A player decides, in order: faction (lobby), start location, the first builds and the lab, what each factory makes,
where constructors go, scouting, where to fight and when to pull back, commander use (D-gun, position), tech timing.

For each: who decides now in Anarvā? It must be Anarvā's own decision, made like a player: what does the player
see, what does it buy, what does it cost. A BARb default, a fixed rule or a harness setting is fixed first.
Status table: [FEATURES.md](FEATURES.md).

## 2. Conditions: play under the players' conditions

A comparison only holds under the same conditions. Tests run:
- **Maps:** on the maps top players play 1v1 (the most frequent in `runs/replays.db`).
- **Start boxes:** with the start boxes those games had (`tools/run_match.py` reads them from the replays).
- **Starts:** choosing starts in game, as every 1v1 replay does.
- **Factions:** compared against games of the same faction matchup. An AI's faction comes from the lobby.

A game under other conditions is reported as such, never as a gap.

## 3. Gaps, ranked

`python tools/check_game.py runs/<batch>/gNN` compares the game with the 1v1 winners of the most similar games:
- **How games are matched:** by their actual start distance, the spots each player had, water, wind and faction matchup.
- **What is compared:** the start, extractors, constructors, factories, energy and army, by minute.
- **How gaps are ranked:** by size against the winners' own spread, as (ours - theirs) / spread.

The largest gap is the next job. The checklist failures (overflow, stalls, an army that doesn't move) come before it.

## 4. Reason: why do the players do it?

For that gap, find in the replays what the players were looking at and why they acted:
- **Situation:** what the map and the enemy looked like at that moment.
- **Aim:** what they wanted.
- **Effect:** what it bought them and what it cost.

Cite the replays (CLAUDE.md §1). Then trace in our logs why Anarvā doesn't do the same: the decision that made the
choice, and the value it compared. Usually it is a frozen rule, a missing option or a wrong value.

## 5. Decision: make Anarvā see it and decide it

Build the reason into the AI as a value computed from the live game (CLAUDE.md §2: no constants, no tables).
Log every decision with its alternatives, so the next game shows what it weighed.

### How to trace (confirmed by the owner, 2026-11-25: "good vector, good working procedures")

1. **Start at the earliest gap.** Take the first minute where check_game puts us outside the winners' spread
   (often energy and extractors at minutes 3 and 4), not the biggest gap later.
2. **Read the decision lines with their inputs:**
   - `[ANV-PICK]` gives each job's value, the metal and energy prices (pM/pE) and the bank.
   - `[ANV-JOBS]`, `[ANV-PROD]` and `[ANV-CHECK]` give jobs per type, production picks and stalls.
   - Ask whether the chosen job is what a player would pick here, and which input made it win.
3. **If the logs don't explain it, add a diagnostic log where it fails, then run one short game.** Example: `[ANV-MEXIDLE]` logs
   distance, velocity and spot offset at each idle. It showed builders "failing" while walking at full speed.
4. **Read the inherited code that actually decides.** Hidden rules found this way:
   - Idles on the way counted as build failures, and spots were then marked blocked.
   - Re-assigning the same job restarted the walk.
   - Towers were re-ordered on every update.
5. **Fix the cause as a player reasons it, from unit facts and live measurements.** Examples:
   - Production is the least of build power, metal and energy. A full bank means that resource doesn't bind.
   - Price a job's own energy draw.
   - Value wind as it blows, including lulls.
6. **Test one short game on the map that showed the failure, then read the logs again.** Repeat until the mechanism is right, then go to step 6
   with the batch.

## 6. Verify: one round, then back to 3

Run one round under step 2's conditions and read the ranked gaps. Did the gap close, and did nothing else open?
Record the result in [PROGRESS.md](PROGRESS.md) and the issue. Then take the next largest gap.
