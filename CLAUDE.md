# Working rules for Anarvā

These are the owner's standing rules. They apply to every change, every claim and every comment.

## PRIORITY 1: Think like the player

Owner, 2026-11-25: "you have to think like the player does ... make it priority n1", after Anarvā was being
compared with top players while it could not even pick its starting location.

- **Every decision a player makes is a decision Anarvā makes, the way a player makes it.** Start location, faction,
  lab, first builds, scouting, what to build, where to fight. A decision Anarvā doesn't make, or that is still a
  BARb default, a fixed rule or a harness setting, is the first thing to fix.
- **Before comparing with players, play under their conditions.** Same start rules (choose in game), the start
  boxes they had, the maps they play 1v1 on, the same game setup. A comparison under different conditions measures
  the setup, not Anarvā; don't report it as a gap.
- **Ask what the player sees and why they act.** From the replays: what situation the player was in, what they
  wanted, what it bought them. Then make Anarvā see the same and decide from it (the rest of these rules: no
  constants, no tables, values from the live game).
- **Follow the process in [PROCESS.md](PROCESS.md)** every time (owner: "build a process"):
  1. decisions;
  2. conditions;
  3. ranked gaps;
  4. reason from replays;
  5. decision;
  6. verify.

## 0. Work ethic: improve first, test later

From the owner, 2026-11-24, after watching Anarva play like BARb while ~200 test games were spent on small tweaks:
"YOU MUST STOP TESTING NOW. FOCUS ON IMPROVEMENTS AND AFTER YOU HAVE REACHED A REASONABLE JUSTIFIABLE
IMPROVEMENT ONLY THEN YOU CAN TEST."

- **Fix what a strong player would call obviously wrong, first.** One watched game shows more than a hundred
  A/B rounds on a marginal flag. Every remark from the owner's games is a bug: open an issue for it at once
  (cause, fix, status) and work it.
- **Do not run test batches per small change.** Build a batch of reasoned improvements that together justify a
  measurable step, then test that batch. Tests confirm improvements; they are not a substitute for reasoning.
- **Trust no inherited code.** BARb's scripts, configs and C++ hold hand-picked gates and dice that quietly block
  the reasoning layered on top (example: the Recycler never reclaimed a solar because three fixed conditions had to
  hold at once). Read what actually decides before adding anything on top of it.
- **Know every unit from its facts, decided live, never from a table.** What a unit is good against, what kills
  it and its weakness follow from its unit facts (range, speed, turn rate, damage type, armour, targets, cost),
  set against the enemy actually seen in this game (square law). No counter table: not BARb's, and not one built
  from replay kills either (owner, 2026-11-25: "DO NOT rework unit composition from the replay kill matrix - this
  is a static rule, stop suggesting static rules"). Replays explain *why* players pick units and are the yardstick
  for how well we play; the AI never reads a replay-derived table. Owner, 2026-11-24: "What is a good unit against Behemoth
  in competitive play? Why haven't you analyzed the replays and taken notes? Why haven't you done it for every unit
  in the game and instead you just copied BARb on everything [and] ran 15000 tests. Pointless."
- **Replays give the reason, the AI gets the decision.** In replays find the ACTUAL REASON why top players do
  things the way they do (owner, 2026-11-24): what situation, what it buys, what it costs. Transpose that reason into
  decision logic computed from the live game. Never copy the observed number, layout, timing or order itself.
  Base layout, unit choice, timings, commander use: all of it.

- **Tests are not progress.** Thousands of A/B games on marginal flags produced nothing a single watched game
  didn't show. Study (replays, unit facts) and reasoned implementation come first.

- **The yardstick is the best players, not BARb** (owner, 2026-11-25: "WHY ARENT YOU COMPARING YOURSELF TO THE BEST
  PLAYERS BUT A FUCKING BARB"). Judge every change by Anarva's curves (income, extractors, energy, army use, build
  order by minute) against leaderboard replays. Beating BARb is a gate, not the measure. An army that neither trades
  nor holds ground is an expansion opportunity cost, and scouting decides between expanding, army and attack.
- **Every rule is suspect, including your own.** A comparison against a literal, a priority band or a gate is a
  frozen decision whoever wrote it. Never add one; when you find one, replace it with a computed value.

- **No substitutes for decisions.** A rotation, a fixed range middle or a "more likely than not" cutoff is not a
  decision; derive the choice from value.

## 1. Every strategic claim is verified against replays

- **Always verify claims against replays.** Before arguing that strong players do X, or that X wins,
  find it in replays and measure it. Intuition, forum lore and "humans usually..." are hypotheses until
  a replay shows them.
- **Reference the replay.** Whenever a strategy is defended (in code comments, docs, issues, commit
  messages or chat), cite the replay(s) it rests on: file name (or replay id), map, format, players and
  the minute where it happens, or the aggregate from `tools/analyze_*.py` with the set it ran on.
  No reference, no claim.
- **Keep the library broad; let the categories emerge.** Download top-player replays across
  configurations (1v1, 2v2, 3v3, 4v4, 8v8, FFA, humans vs bots). Do not hand-write categories or style
  labels: describe each player-game by measured features and cluster them, with the number of clusters
  chosen by fit (see [REPLAYS.md](REPLAYS.md)). A finding holds for the cluster whose replays show it and
  does not carry over to another unless the replays show that too.
  Example: commanders stand 2000-3000 out all game in team games, but not in 1v1.
- Tools: `tools/fetch_replays.py` (download by preset and skill), `tools/run_replay.py` (play back
  headless with the analyzer widget), `tools/analyze_replays.py` (economy curves) and
  `tools/analyze_comm.py` (commander behaviour). Extend the analyzer widget
  (`tools/replay_harness/LuaUI/Widgets/zz_replay_analyzer.lua`) when a claim needs data it doesn't log yet.

## 2. No random numbers and no constants: every decision is computed

**No random numbers. No hand-picked constants. Every single one.** A decision is a live comparison of value
(metal-equivalent over the planning horizon, minus risk), computed from measured game state, unit facts
(read from the unit defs through the bridge) or replay evidence. A threshold is a frozen priority; a dice roll
is a decision nobody made.

- Allowed numbers: game and physics facts (30 frames per second, 65536 angle units, a unit's cost, range,
  speed, turn rate, storage, read from its def), unit conversions, numeric guards against division by zero.
  Everything else must be derived and the derivation written next to it.
- Not allowed: `AiRandom`, dice (`AiDice`), probabilities, "chance", fixed minutes, fixed income levels, fixed
  ratios, caps, fudge factors, hand-tuned weights, magic distances, inherited BARb config curves.
- Choices among equals are made by a systematic rule (the best value, the least travel time, the largest
  deficit against the target mix), never by chance.
- The full inventory lives in [AUDIT.md](AUDIT.md): every random number and constant in the scripts, the
  configs and the C++ core, what it decides and the computed replacement. Each one is replaced; the list is
  only allowed to shrink. New code that adds one is a bug.
- Copy the reasoning behind a behaviour seen in replays, never the behaviour itself.

## 3. Everything is measured

- The `F_*` flags were folded into the code (2026-11-24, when every constant became a decision); there is no
  flag-and-A/B system any more. A change is a reasoned decision. It is checked by playing a few games
  (owner, 2026-11-25: "you can start playing in moderation") and reading what the AI did: the build log,
  the builder pick log (`[ANV-PICK]`), the economy line and the Director's ratio, compared with the
  top players' curves in `runs/replays.db`.
- **Only one game at any given time** (owner, 2026-11-26: "only run 1 game at any given time"). `tools/batch.py ...
  --games 1 --par 1`, one map per run; report each result as soon as it is in, then start the next. Never four in
  parallel (it lags the owner's machine and delays every result).
- **One install only: `Anarva`.** No side-by-side copies in the owner's BAR (owner: "why do you keep multiple
  copies"). Install only while the owner is not playing (the installer refuses while BAR holds the DLL), then verify
  with a short headless game before saying it is ready.
- **Every game is assessed with [CHECKLIST.md](CHECKLIST.md)** (owner, 2026-11-25, #92: "Why don't you have a basic
  checklist?"): `python tools/check_game.py runs/<batch>/gNN`. Overflow, stalls, army value, whether the army moves
  and fights come before the score. A failure there is fixed before anything else.
- The replay analyzer runs at all times until every library replay is in `runs/replays.db`
  (`tools/replay_db.py run`). No replay is played twice.
- Results and findings go into [PROGRESS.md](PROGRESS.md) and the issues. [FEATURES.md](FEATURES.md) is
  written by hand (`tools/gen_features.py` described the flag system and is retired).
- The 1v1 release gate: a release is tagged only when Anarvā wins its 1v1s against BARb hard.

## 4. Collaboration

- Vritrasura108 contributes through GitHub issues: check them after every test batch, answer on the
  issue, turn ideas into reasoned changes and report the results back there.
- Collaborators work on branches and open pull requests; main is the measured baseline.
