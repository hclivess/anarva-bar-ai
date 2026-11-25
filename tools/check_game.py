#!/usr/bin/env python3
"""
Per-game checklist (owner #92, CHECKLIST.md): read a game's infolog and answer, minute by minute:
  - Am I wasting (overflowing) or stalling metal? Energy?
  - Is my army value too low (vs the enemy's real army, vs top players at that minute)?
  - Is my army value too high for what it does (stronger than the enemy, yet nobody attacking or raiding)?
  - Is my army moving at all? Fighting? Killing?
  - Are builders or factories idle while resources pile up?

usage: python tools/check_game.py runs/<batch>/g00 [runs/<batch>/g01 ...] [--db runs/replays.db]
Reads [ANV-CHECK] lines (the AI's own per-minute assessment) and [HARNESS] stats (the truth for both teams).
"""
import argparse
import os
import re
import sqlite3

CHECK = re.compile(r"\[ANV-CHECK\] t=(\d+)m (.*)")
STAT = re.compile(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d) units=\d+ army_m=(\d+) static_m=(\d+) m_inc=([\d.]+)")
KV = re.compile(r"(\w+)=([^ ]+(?: [\d.]+/s(?: short)?)?)")


def winners_curve(db_path):
    """Average 1v1 winner per minute from the replay database: army metal, extractors, constructors, factories."""
    if not os.path.exists(db_path):
        return {}
    db = sqlite3.connect(db_path)
    q = """select s.minute, avg(s.army), avg(s.mex), avg(s.builders), avg(s.facs), avg(s.e_inc), count(*)
           from stats s join teams t on t.replay_id=s.replay_id and t.team=s.team join replays r on r.id=s.replay_id
           where r.format='1v1' and r.status='done' and t.won=1 group by s.minute"""
    return {m: (a, x, b, f, e, n) for m, a, x, b, f, e, n in db.execute(q)}


def parse(game_dir):
    log = os.path.join(game_dir, "infolog.txt")
    text = open(log, encoding="utf-8", errors="replace").read()
    checks = {}
    for m in CHECK.finditer(text):
        kv = dict(KV.findall(m.group(2)))
        checks[int(m.group(1))] = kv
    truth = {}  # minute -> {team: (army, static, m_inc)}
    for m in STAT.finditer(text):
        minute = int(m.group(1)) // 1800
        truth.setdefault(minute, {})[int(m.group(2))] = (int(m.group(3)), int(m.group(4)), float(m.group(5)))
    me = None
    script = os.path.join(game_dir, "_script.txt")
    if os.path.exists(script):  # our team: the one whose AI shortName starts with Anarva
        s = open(script, encoding="utf-8", errors="replace").read()
        # an [aiN] block nests an [options]{...} block, so take everything up to the next top-level [section]
        for blk in re.split(r"\n\s*\[(?=ai\d+\])", s, flags=re.I)[1:]:
            body = blk.split("\n[", 1)[0] if not blk.lower().startswith("ai") else blk
            if re.search(r"shortname=Anarva", body, re.I):
                t = re.search(r"^\s*team=(\d+);", body, re.M)
                me = int(t.group(1)) if t else None
                break
    return checks, truth, me


def frac(a, b):
    try:
        return int(a) / max(1, int(b))
    except ValueError:
        return 0.0


def report(game_dir, curve):
    checks, truth, me = parse(game_dir)
    print(f"\n=== {game_dir}  (Anarva team {me})")
    if not checks:
        print("  no [ANV-CHECK] lines: the AI build predates the self-assessment")
        return
    print("  min  metal        energy       army  enemy  top1v1  ratio  moving  atk/raid/def/none  killed lost  idleB  idleF")
    flags = {"metal waste": [], "metal stall": [], "energy waste": [], "energy stall": [], "army idle while stronger": [],
             "army did not move": [], "below top players' army": [], "builders idle while wasting": [], "factory idle": [],
             "micro: more units idle with a target in reach than firing": [],
             "micro: more units hit without replying than firing": [],
             "micro: more outranged hits than shots fired": [], "micro: units standing still under fire": []}
    for minute in sorted(checks):
        c = checks[minute]
        t = truth.get(minute, {})
        enemy_true = sum(v[0] for k, v in t.items() if k != me) if (t and me is not None) else None
        top = curve.get(minute)
        army = int(c.get("army", 0))
        mv = c.get("moving", "0/0").split("/")
        moving = frac(mv[0], mv[1])
        atk, raid = int(c.get("attack", 0)), int(c.get("raid", 0))
        ib = c.get("idleBuilders", "0/0").split("/")
        ifac = c.get("idleFactories", "0/0").split("/")
        print(f"  {minute:3d}  {c.get('metal', '?')[:11]:11s}  {c.get('energy', '?')[:11]:11s}  {army:5d}  "
              f"{(enemy_true if enemy_true is not None else -1):5d}  {(int(top[0]) if top else -1):6d}  {c.get('ratio', '?'):>5s}  "
              f"{c.get('moving', '?'):>6s}  {atk}/{raid}/{c.get('defend', 0)}/{c.get('none', 0):>4}  "
              f"{c.get('killed', 0):>6s} {c.get('lost', 0):>4s}  {c.get('idleBuilders', '?'):>5s}  {c.get('idleFactories', '?'):>5s}")
        if c.get("metal", "").startswith("WASTE"): flags["metal waste"].append(minute)
        if c.get("metal", "").startswith("STALL"): flags["metal stall"].append(minute)
        if c.get("energy", "").startswith("WASTE"): flags["energy waste"].append(minute)
        if c.get("energy", "").startswith("STALL"): flags["energy stall"].append(minute)
        try:
            ratio = float(c.get("ratio", 0))
        except ValueError:
            ratio = 0.0
        if army > 0 and enemy_true is not None and army > enemy_true and atk + raid == 0:
            flags["army idle while stronger"].append(minute)
        if int(mv[1] or 0) > 0 and int(mv[0] or 0) == 0:  # not one army unit moved a second's worth all minute
            flags["army did not move"].append(minute)
        if top and army < top[0]:
            flags["below top players' army"].append(minute)
        if c.get("metal", "").startswith("WASTE") and int(ib[0] or 0) > 0:
            flags["builders idle while wasting"].append(minute)
        if int(ifac[0] or 0) > 0:
            flags["factory idle"].append(minute)
        mc = {k: int(c.get(k, 0) or 0) for k in ("microContact", "microFired", "microNoReply", "microOutranged", "microIdleInRange", "microStillHit")}
        if mc["microContact"] > 0:
            print(f"        micro (unit-seconds): contact {mc['microContact']} fired {mc['microFired']} noReply {mc['microNoReply']} "
                  f"outranged {mc['microOutranged']} idleInRange {mc['microIdleInRange']} stillHit {mc['microStillHit']}")
            if mc["microIdleInRange"] > mc["microFired"]: flags["micro: more units idle with a target in reach than firing"].append(minute)
            if mc["microNoReply"] > mc["microFired"]: flags["micro: more units hit without replying than firing"].append(minute)
            if mc["microOutranged"] > mc["microFired"]: flags["micro: more outranged hits than shots fired"].append(minute)
            if mc["microStillHit"] > 0: flags["micro: units standing still under fire"].append(minute)
    # the yardstick: the winners of top-player 1v1 games, minute by minute (CHECKLIST.md header)
    print("  vs top 1v1 winners (Anarva / winners):  min  extractors  constructors  factories  energy/s  army")
    behind = {"extractors": [], "constructors": [], "factories": [], "energy": [], "army": []}
    for minute in sorted(checks):
        c = checks[minute]
        top = curve.get(minute)
        if not top:
            continue
        mex = int(c.get("mex", 0) or 0)
        ib = c.get("idleBuilders", "0/0").split("/")
        ifac = c.get("idleFactories", "0/0").split("/")
        cons, facs = int(ib[1] or 0), int(ifac[1] or 0)
        try:
            einc = float(c.get("eInc", 0))
        except ValueError:
            einc = 0.0
        army = int(c.get("army", 0))
        print(f"  {'':38s}{minute:4d}  {mex:4d}/{top[1]:5.1f}  {cons:5d}/{top[2]:5.1f}  {facs:4d}/{top[3]:4.1f}  {einc:6.0f}/{top[4]:5.0f}  {army:5d}/{top[0]:5.0f}")
        for k, mine, theirs in (("extractors", mex, top[1]), ("constructors", cons, top[2]), ("factories", facs, top[3]),
                                ("energy", einc, top[4]), ("army", army, top[0])):
            if mine < theirs:
                behind[k].append(minute)
    for k, v in behind.items():
        flags[f"behind the winners: {k}"] = v
    print("  checklist:")
    for k, v in flags.items():
        print(f"    [{'FAIL' if v else ' ok '}] {k}" + (f": minutes {','.join(map(str, v))}" if v else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+")
    ap.add_argument("--db", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "runs", "replays.db"))
    a = ap.parse_args()
    curve = winners_curve(a.db)
    for g in a.games:
        report(g, curve)


if __name__ == "__main__":
    main()
