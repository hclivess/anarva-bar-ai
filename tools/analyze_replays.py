"""Aggregate [REPLAY] logs into per-player development curves and milestone timings.

usage: python analyze_replays.py <replay_out_root> [--json out.json]
Reads every <root>/*/infolog.txt produced by run_replay.py.
"""
import argparse
import glob
import json
import os
import re
from collections import Counter, defaultdict

T2_LABS = {"armalab", "armavp", "armaap", "armasy", "coralab", "coravp", "coraap", "corasy",
           "legalab", "legavp", "legaap", "legadvshipyard"}
FUSION = {"armfus", "corfus", "legfus", "armckfus", "armuwfus", "coruwfus"}
AFUS = {"armafus", "corafus", "legafus"}
NUKE = {"armsilo", "corsilo", "legsilo"}
T3 = {"armshltx", "corgant", "leggant"}
MINUTES = (3, 5, 8, 10, 12, 15, 20, 25, 30)


def parse(log):
    text = open(log, encoding="utf-8", errors="replace").read()
    teams, stats, built = {}, defaultdict(dict), defaultdict(list)
    for m in re.finditer(r"\[REPLAY\] TEAM team=(\d+) ally=(-?\d+) side=(\S+) name=(.*)", text):
        teams[int(m.group(1))] = {"ally": int(m.group(2)), "side": m.group(3), "name": m.group(4).strip()}
    for m in re.finditer(r"\[REPLAY\] STAT min=(\d+) team=(\d+) m_inc=([\d.]+) e_inc=(\d+) army=(\d+) def=(\d+) eco=(\d+)", text):
        stats[int(m.group(2))][int(m.group(1))] = tuple(float(x) for x in m.groups()[2:])
    for m in re.finditer(r"\[REPLAY\] BUILT f=(\d+) team=(\d+) (\S+) m=(\d+)", text):
        built[int(m.group(2))].append((int(m.group(1)) / 1800.0, m.group(3), int(m.group(4))))
    w = re.search(r"\[REPLAY\] WINNERS ally=([\d,]*)", text)
    winners = {int(x) for x in w.group(1).split(",") if x} if w else None
    skills = {}
    script = os.path.join(os.path.dirname(log), "_script.txt")
    if os.path.exists(script):
        s = open(script, encoding="latin1").read()
        for pm in re.finditer(r"\[player\d+\]\s*\{(.*?)\}", s, re.S):
            n = re.search(r"name=([^;]*);", pm.group(1))
            k = re.search(r"skill=\[?([\d.]+)", pm.group(1))
            if n and k:
                skills[n.group(1)] = float(k.group(1))
    return teams, stats, built, winners, skills


def first(blist, names):
    t = [b[0] for b in blist if b[1] in names]
    return round(min(t), 1) if t else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--json")
    args = ap.parse_args()
    players = []
    for log in glob.glob(os.path.join(args.root, "*", "infolog.txt")):
        teams, stats, built, winners, skills = parse(log)
        n_players = len(teams)
        fmt = "1v1" if n_players <= 2 else ("team<=4v4" if n_players <= 8 else "team>4v4")
        for t, info in teams.items():
            if t not in stats:
                continue
            b = built[t]
            early = Counter(n for (mm, n, _) in b if mm <= 10)
            players.append({
                "replay": os.path.basename(os.path.dirname(log))[:60], "team": t, "format": fmt, **info,
                "skill": skills.get(info["name"]),
                "won": (info["ally"] in winners) if winners is not None else None,
                "curve": {mm: stats[t][mm] for mm in MINUTES if mm in stats[t]},
                "t2_lab": first(b, T2_LABS), "fusion": first(b, FUSION), "afus": first(b, AFUS),
                "t3": first(b, T3), "nuke": first(b, NUKE),
                "early_top": early.most_common(8),
            })
    if args.json:
        json.dump(players, open(args.json, "w"), indent=1)

    def avg(rows, key_fn):
        vals = [v for v in (key_fn(r) for r in rows) if v is not None]
        return (sum(vals) / len(vals), len(vals)) if vals else (None, 0)

    groups = {}
    for fmt in ("1v1", "team<=4v4", "team>4v4"):
        rows = [p for p in players if p["format"] == fmt]
        groups[f"{fmt} | top (skill>=35)"] = [p for p in rows if (p["skill"] or 0) >= 35 and not p["name"].startswith("AI:")]
        groups[f"{fmt} | winners"] = [p for p in rows if p["won"] and not p["name"].startswith("AI:")]
        groups[f"{fmt} | losers"] = [p for p in rows if p["won"] is False and not p["name"].startswith("AI:")]
    groups["AI (any format)"] = [p for p in players if p["name"].startswith("AI:")]
    for g, rows in groups.items():
        if not rows:
            continue
        print(f"\n=== {g}: {len(rows)} player-games")
        for mm in MINUTES:
            m_inc, n = avg(rows, lambda r: r["curve"].get(mm, (None,))[0])
            if not n:
                continue
            e_inc, _ = avg(rows, lambda r: r["curve"].get(mm, (0, None))[1])
            army, _ = avg(rows, lambda r: r["curve"].get(mm, (0, 0, None))[2])
            dfn, _ = avg(rows, lambda r: r["curve"].get(mm, (0, 0, 0, None))[3])
            eco, _ = avg(rows, lambda r: r["curve"].get(mm, (0, 0, 0, 0, None))[4])
            print(f"  min {mm:2d}: m_inc {m_inc:6.1f}  e_inc {e_inc:6.0f}  army {army:7.0f}  def {dfn:6.0f}  eco {eco:7.0f}  (n={n})")
        for k in ("t2_lab", "fusion", "afus", "t3", "nuke"):
            v, n = avg(rows, lambda r: r[k])
            print(f"  first {k:6s}: " + (f"{v:5.1f} min (n={n}/{len(rows)})" if n else "never"))
        c = Counter()
        for r in rows:
            for name, cnt in r["early_top"]:
                c[name] += cnt
        print("  first-10-min builds:", ", ".join(f"{n}x{k}" for k, n in c.most_common(14)))


if __name__ == "__main__":
    main()
