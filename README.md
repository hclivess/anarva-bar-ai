# Anarvā — a smarter Skirmish AI for Beyond All Reason

Anarvā runs on BARb's C++ core (CircuitAI) and adds its own AngelScript brain and tuned configs:

- massed attack waves with a posture-driven Director (boom, hold, balanced, pressure, all-in)
- broken-squad recall, so armies don't trickle in one by one
- eco recycling: solars and winds → fusions → advanced fusions, plus T1 makers and obsolete T1 units
- jammer hunting: phantom threat on seen jammers, Dragon's Eyes where we die unseen, Junos
- strategic buildings BARb never makes: anti-nuke, tactical/EMP launchers, nukes, shields over key
  infrastructure, and anti-air placed when air is scouted

**Goal:** one Anarvā beats six BARb (hard) opponents on every map type. Status is in
[PROGRESS.md](PROGRESS.md) and [progress.json](progress.json).

- Players: install, lobby and online notes are in [Anarva/README.md](Anarva/README.md).
- Developers: everything is in `tools/`.
  - `install.ps1` deploys the AI (use `-Name AnarvaDev` for a side-by-side test copy).
  - `run_match.py` and `batch.py` run headless AI-vs-AI matches, including 1vN, with a scoreboard by
    map type.
  - `fetch_replays.py`, `run_replay.py` and `analyze_replays.py` find, play back and analyze
    high-skill replays, producing per-format development curves.

License: GPL-2.0, the same as CircuitAI and Beyond All Reason, which this is derived from.
