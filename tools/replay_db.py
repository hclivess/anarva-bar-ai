#!/usr/bin/env python3
"""
Replay database: play every downloaded replay once with the analyzer widget and keep the results in SQLite, so no
replay is ever played again (owner, 2026-11-25).

  python tools/replay_db.py run    [--db runs/replays.db] [--par 1] [--format 1v1]   # play + ingest until all done
  python tools/replay_db.py ingest <playback_dir> --id <replay id>                    # parse one existing playback
  python tools/replay_db.py status                                                     # progress per format

What is stored (per replay, from ref/lib/index.json and the analyzer's [REPLAY] lines):
  replays  id, file, format, map, minutes, start, winners, status (done/nodata/noengine), attempts, end frame
  teams    team, ally, side, name, skill (from the index), won
  stats    every game minute per team: metal/energy income, current, storage, expense; army / defence / eco metal;
           units, constructors, build power, extractors and their income, factories
  built    every finished unit: frame, team, unit, metal, tech level, air/sea/static/builder/armed, range, factory, x, z
  dmg      damage and metal killed by attacker unit vs victim unit (whole game)
  comm     commander every 5 s: position, distance from start, hp, command, armed metal around (own/enemy), nearest
  cbuild   what each commander built and how far from its start
  events   CDEATH, FIRSTHIT, END and WINNERS frames
  motion   moving combat units' speed and turn use per minute and kind
Raw logs are kept gzipped in runs/replay_logs/<id>.txt.gz; the playback folder is deleted.
"""
import argparse
import gzip
import json
import os
import re
import shutil
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import run_replay  # noqa: E402

LIB = os.path.join(ROOT, "ref", "lib")
LOGS = os.path.join(ROOT, "runs", "replay_logs")
WORK = os.path.join(ROOT, "runs", "replay_work")

SCHEMA = """
CREATE TABLE IF NOT EXISTS replays (id TEXT PRIMARY KEY, file TEXT, format TEXT, map TEXT, minutes REAL, start TEXT,
  winners TEXT, status TEXT, attempts INTEGER DEFAULT 0, end_frame INTEGER, played_at REAL);
CREATE TABLE IF NOT EXISTS teams (replay_id TEXT, team INTEGER, ally INTEGER, side TEXT, name TEXT, skill REAL, won INTEGER,
  PRIMARY KEY (replay_id, team));
CREATE TABLE IF NOT EXISTS stats (replay_id TEXT, team INTEGER, minute INTEGER, m_inc REAL, e_inc REAL, army INTEGER,
  def INTEGER, eco INTEGER, units INTEGER, m_cur INTEGER, m_sto INTEGER, m_exp REAL, e_cur INTEGER, e_sto INTEGER,
  e_exp REAL, builders INTEGER, bp INTEGER, mex INTEGER, mex_inc REAL, facs INTEGER, PRIMARY KEY (replay_id, team, minute));
CREATE TABLE IF NOT EXISTS built (replay_id TEXT, frame INTEGER, team INTEGER, unit TEXT, metal INTEGER, tl INTEGER,
  air INTEGER, sea INTEGER, static INTEGER, builder INTEGER, armed INTEGER, range INTEGER, fac INTEGER, x INTEGER, z INTEGER);
CREATE TABLE IF NOT EXISTS dmg (replay_id TEXT, att TEXT, vic TEXT, dmg REAL, kill_m REAL);
CREATE TABLE IF NOT EXISTS comm (replay_id TEXT, frame INTEGER, team INTEGER, x INTEGER, z INTEGER, from_start INTEGER,
  hp REAL, cmd TEXT, own600 INTEGER, enemy600 INTEGER, nearest INTEGER);
CREATE TABLE IF NOT EXISTS cbuild (replay_id TEXT, frame INTEGER, team INTEGER, unit TEXT, from_start INTEGER);
CREATE TABLE IF NOT EXISTS events (replay_id TEXT, kind TEXT, frame INTEGER, team INTEGER, value TEXT);
CREATE TABLE IF NOT EXISTS motion (replay_id TEXT, minute INTEGER, team INTEGER, kind TEXT, n INTEGER, speed REAL, turn REAL);
CREATE INDEX IF NOT EXISTS built_r ON built(replay_id, team);
CREATE INDEX IF NOT EXISTS dmg_r ON dmg(replay_id);
CREATE INDEX IF NOT EXISTS comm_r ON comm(replay_id, team);
"""

KV = re.compile(r"(\w+)=(-?[\d.]+|\S+)")


def kv(s):
    return {k: v for k, v in KV.findall(s)}


def num(d, k, cast=float):
    v = d.get(k)
    if v is None:
        return None
    try:
        return cast(float(v))
    except ValueError:
        return None


def connect(path):
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    return db


def ingest(db, rid, log_text, meta):
    """Parse one playback log into the tables (replacing earlier rows of that replay)."""
    for t in ("teams", "stats", "built", "dmg", "comm", "cbuild", "events", "motion"):
        db.execute(f"DELETE FROM {t} WHERE replay_id=?", (rid,))
    skill = {p[0]: p[1] for p in meta.get("players", [])}
    winners = set(meta.get("winners", []))
    has_stat = False
    end_frame = None
    for line in log_text.splitlines():
        i = line.find("[REPLAY] ")
        if i < 0:
            continue
        body = line[i + 9:]
        kind, _, rest = body.partition(" ")
        d = kv(rest)
        if kind == "TEAM":
            name = d.get("name", "?")
            db.execute("INSERT OR REPLACE INTO teams VALUES (?,?,?,?,?,?,?)",
                       (rid, num(d, "team", int), num(d, "ally", int), d.get("side"), name, skill.get(name),
                        1 if name in winners else 0))
        elif kind == "STAT":
            has_stat = True
            db.execute("INSERT OR REPLACE INTO stats VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (rid, num(d, "team", int), num(d, "min", int), num(d, "m_inc"), num(d, "e_inc"), num(d, "army", int),
                        num(d, "def", int), num(d, "eco", int), num(d, "units", int), num(d, "m_cur", int), num(d, "m_sto", int),
                        num(d, "m_exp"), num(d, "e_cur", int), num(d, "e_sto", int), num(d, "e_exp"), num(d, "builders", int),
                        num(d, "bp", int), num(d, "mex", int), num(d, "mex_inc"), num(d, "facs", int)))
        elif kind == "BUILT":
            unit = rest.split()[2] if len(rest.split()) > 2 else "?"
            db.execute("INSERT INTO built VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (rid, num(d, "f", int), num(d, "team", int), unit, num(d, "m", int), num(d, "tl", int), num(d, "air", int),
                        num(d, "sea", int), num(d, "static", int), num(d, "builder", int), num(d, "armed", int),
                        num(d, "range", int), num(d, "fac", int), num(d, "x", int), num(d, "z", int)))
        elif kind == "DMG":
            db.execute("INSERT INTO dmg VALUES (?,?,?,?,?)", (rid, d.get("att"), d.get("vic"), num(d, "dmg"), num(d, "killM")))
        elif kind == "COMM":
            db.execute("INSERT INTO comm VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                       (rid, num(d, "f", int), num(d, "team", int), num(d, "x", int), num(d, "z", int), num(d, "fromStart", int),
                        num(d, "hp"), d.get("cmd"), num(d, "own600", int), num(d, "enemy600", int), num(d, "nearestEnemy", int)))
        elif kind == "CBUILD":
            unit = rest.split()[2] if len(rest.split()) > 2 else "?"
            db.execute("INSERT INTO cbuild VALUES (?,?,?,?,?)", (rid, num(d, "f", int), num(d, "team", int), unit, num(d, "fromStart", int)))
        elif kind == "WIND":
            db.execute("INSERT INTO events VALUES (?,?,?,?,?)", (rid, kind, 0, -1, "%s,%s,%s" % (d.get("min"), d.get("max"), d.get("tidal"))))
        elif kind in ("CDEATH", "FIRSTHIT"):
            db.execute("INSERT INTO events VALUES (?,?,?,?,?)", (rid, kind, num(d, "f", int), num(d, "team", int), d.get("fromStart")))
        elif kind == "WINNERS":
            db.execute("INSERT INTO events VALUES (?,?,?,?,?)", (rid, kind, num(d, "f", int), None, d.get("ally")))
            end_frame = num(d, "f", int)
        elif kind == "END":
            end_frame = end_frame or num(d, "f", int)
            db.execute("INSERT INTO events VALUES (?,?,?,?,?)", (rid, kind, num(d, "f", int), None, None))
        elif kind == "MOTION":
            db.execute("INSERT INTO motion VALUES (?,?,?,?,?,?,?)", (rid, num(d, "min", int), num(d, "team", int), d.get("kind"),
                                                                    num(d, "n", int), num(d, "speed"), num(d, "turn")))
    return has_stat, end_frame


def upsert_meta(db, meta, status, end_frame):
    db.execute("""INSERT INTO replays (id, file, format, map, minutes, start, winners, status, attempts, end_frame, played_at)
                  VALUES (?,?,?,?,?,?,?,?,1,?,?)
                  ON CONFLICT(id) DO UPDATE SET status=excluded.status, attempts=replays.attempts+1,
                  end_frame=excluded.end_frame, played_at=excluded.played_at""",
               (meta["id"], meta["file"], meta.get("format"), meta.get("map"), meta.get("minutes"), meta.get("start"),
                json.dumps(meta.get("winners", [])), status, end_frame, time.time()))


def play_one(db, meta, wall_minutes):
    demo = os.path.join(LIB, meta["file"])
    if run_replay.engine_for(demo) is None:
        upsert_meta(db, meta, "noengine", None)
        db.commit()
        return "noengine"
    args = argparse.Namespace(out=WORK, minutes=wall_minutes)
    out = run_replay.play(args, demo)
    log = os.path.join(out, "stdout.txt")
    text = open(log, encoding="utf-8", errors="replace").read() if os.path.exists(log) else ""
    has_stat, end_frame = ingest(db, meta["id"], text, meta)
    status = "done" if has_stat else "nodata"
    upsert_meta(db, meta, status, end_frame)
    db.commit()
    os.makedirs(LOGS, exist_ok=True)
    keep = "\n".join(l for l in text.splitlines() if "[REPLAY]" in l or "Error" in l)
    with gzip.open(os.path.join(LOGS, meta["id"] + ".txt.gz"), "wt", encoding="utf-8") as f:
        f.write(keep)
    shutil.rmtree(out, ignore_errors=True)
    return status


def cmd_run(a):
    db = connect(a.db)
    index = json.load(open(os.path.join(LIB, "index.json"), encoding="utf-8"))
    # the current goal is 1v1: those first, then the other formats; shortest first within a format
    order = {"1v1": 0}
    index.sort(key=lambda m: (order.get(m.get("format"), 1), m.get("format") or "", m.get("minutes") or 0))
    if a.format:
        index = [m for m in index if m.get("format") == a.format]
    done = {r[0]: (r[1], r[2]) for r in db.execute("SELECT id, status, attempts FROM replays")}
    todo = [m for m in index if m["id"] not in done or (done[m["id"]][0] == "nodata" and done[m["id"]][1] < a.retries)]
    print(f"{len(todo)} replays to play ({len(index) - len(todo)} already in {a.db})", flush=True)
    for k, meta in enumerate(todo):
        # wall clock: the analyzer skips ahead at full speed; allow a generous multiple of the game length for loading
        wall = max(a.min_wall, (meta.get("minutes") or 20) * a.wall_per_game_minute)
        t0 = time.time()
        status = play_one(db, meta, wall)
        print(f"[{k + 1}/{len(todo)}] {meta['format']:7s} {meta.get('minutes', 0):5.1f} min {status:8s} "
              f"{time.time() - t0:6.0f}s  {meta['file']}", flush=True)


def cmd_ingest(a):
    db = connect(a.db)
    text = open(os.path.join(a.dir, "stdout.txt"), encoding="utf-8", errors="replace").read()
    index = {m["id"]: m for m in json.load(open(os.path.join(LIB, "index.json"), encoding="utf-8"))}
    meta = index[a.id]
    has_stat, end_frame = ingest(db, a.id, text, meta)
    upsert_meta(db, meta, "done" if has_stat else "nodata", end_frame)
    db.commit()
    print("ingested", a.id, "stat" if has_stat else "no data")


def cmd_status(a):
    db = connect(a.db)
    index = json.load(open(os.path.join(LIB, "index.json"), encoding="utf-8"))
    total = {}
    for m in index:
        total[m.get("format")] = total.get(m.get("format"), 0) + 1
    got = {}
    for fmt, st, n in db.execute("SELECT format, status, COUNT(*) FROM replays GROUP BY format, status"):
        got.setdefault(fmt, {})[st] = n
    for fmt in sorted(total, key=str):
        print(f"{fmt:8s} {total[fmt]:4d} total  {got.get(fmt, {})}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "ingest", "status"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--db", default=os.path.join(ROOT, "runs", "replays.db"))
    ap.add_argument("--id")
    ap.add_argument("--format")
    ap.add_argument("--retries", type=int, default=2, help="replays that gave no data are tried this many times")
    ap.add_argument("--min-wall", type=float, default=20.0, help="wall-clock minutes at least per replay (tool timeout)")
    ap.add_argument("--wall-per-game-minute", type=float, default=1.5, help="wall-clock minutes per game minute (tool timeout)")
    a = ap.parse_args()
    {"run": cmd_run, "ingest": cmd_ingest, "status": cmd_status}[a.cmd](a)


if __name__ == "__main__":
    main()
