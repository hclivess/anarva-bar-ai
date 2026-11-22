"""Run a batch of headless Anarva-vs-opponent matches in parallel and print a scoreboard.

usage: python batch.py <out_root> [--games 8] [--par 6] [--opp BARb:hard] [--maps "A,B"] [--minutes 9]
Anarva alternates between team 0 and team 1. Results also go to <out_root>/results.json.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
MAP_POOLS = {
    "open": ["Avalanche 3.4", "Comet Catcher Remake 1.8", "Tabula_Remake 1.5.1"],
    "choke": ["Throne_V8", "Seths Ravine Remake 1.3.1", "Glacier Pass 1.2", "Isidis crack 1.1"],
    "mixed": ["Eye Of Horus 1.7.1", "Quicksilver Remake 1.24", "Red Comet Remake 1.8"],
    "water": ["Altair_Crossing_V4.1", "Supreme Isthmus v2.1"],
}
DEFAULT_MAPS = [m for pool in MAP_POOLS.values() for m in pool]
MAP_KIND = {m: k for k, pool in MAP_POOLS.items() for m in pool}
STAT = re.compile(r"\[HARNESS\] (final|timeout|stats) f=(\d+) dead=(\w+) team=(\d) units=(\d+) army_m=(\d+) static_m=(\d+) "
                  r"m_inc=([\d.]+) e_inc=(\d+) .* killed_m=(\d+) lost_m=(\d+)")


def parse(out, tac_team, n1=1):
    log = os.path.join(out, "infolog.txt")
    if not os.path.exists(log):
        return {"result": "crash"}
    text = open(log, encoding="utf-8", errors="replace").read()
    teams = {}
    for m in STAT.finditer(text):
        teams[int(m.group(4))] = {"frame": int(m.group(2)), "army": int(m.group(6)), "static": int(m.group(7)),
                                 "m_inc": float(m.group(8)), "killed": int(m.group(10)), "lost": int(m.group(11))}
    res = {"teams": teams, "script_errors": len(re.findall(r"Anarva\w*-stable>.*(?:rror|xception)", text))}
    w = re.search(r"\[HARNESS\] RESULT winners=([\d,]*)", text)
    if w:
        winners = [int(x) for x in w.group(1).split(",") if x]
        res["result"] = "win" if tac_team in winners else ("draw" if not winners else "loss")
    elif len(teams) >= 2:  # timeout or killed by the wall-clock limit: judge on last stats
        me = teams[tac_team]
        op = {k: sum(v[k] for t, v in teams.items() if t != tac_team) for k in ("army", "static", "killed", "lost", "frame")}
        op["frame"] = me["frame"]
        mv, ov = me["army"] + me["static"], op["army"] + op["static"]
        if me["frame"] < 25 * 60 * 30:
            res["result"] = "incomplete"  # cut by the wall-clock limit too early to judge
        else:
            res["result"] = "pts_win" if mv > 1.25 * ov else ("pts_loss" if ov > 1.25 * mv else "pts_draw")
    else:
        res["result"] = "crash"
    return res


def run_one(args, i):
    m = args.maps[i % len(args.maps)]
    tac_team = 0 if args.n1 > 1 else ((i // len(args.maps)) % 2 if args.games > len(args.maps) else i % 2)
    out = os.path.join(args.out, f"g{i:02d}")
    ai = [args.me, args.opp]
    if tac_team == 1:
        ai.reverse()
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "run_match.py"), out, "--ai0", ai[0], "--ai1", ai[1],
                    "--map", m, "--minutes", str(args.minutes), "--n1", str(args.n1 if tac_team == 0 else 1)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    r = parse(out, tac_team, args.n1)
    r.update({"game": i, "map": m, "tac_team": tac_team})
    t = r.get("teams", {})
    me = t.get(tac_team, {})
    op = {k: sum(v.get(k, 0) for tt, v in t.items() if tt != tac_team) for k in ("army", "static", "killed")}
    print(f"g{i:02d} {MAP_KIND.get(m, '?'):5s} {m:26s} T{tac_team} {r['result']:9s} min={me.get('frame', 0) // 1800:3d} "
          f"army {me.get('army', 0):6d}/{op.get('army', 0):6d} static {me.get('static', 0):6d}/{op.get('static', 0):6d} "
          f"kills {me.get('killed', 0):4d}/{op.get('killed', 0):4d} err={r.get('script_errors', 0)}", flush=True)
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--games", type=int, default=8)
    ap.add_argument("--par", type=int, default=4)
    ap.add_argument("--me", default="Anarva:anarva", help="AI under test, shortName:profile")
    ap.add_argument("--opp", default="BARb:hard")
    ap.add_argument("--maps", default=",".join(DEFAULT_MAPS))
    ap.add_argument("--minutes", type=float, default=30.0)
    args = ap.parse_args()
    args.maps = [x.strip() for x in args.maps.split(",") if x.strip()]
    os.makedirs(args.out, exist_ok=True)
    with ThreadPoolExecutor(args.par) as ex:
        results = list(ex.map(lambda i: run_one(args, i), range(args.games)))
    json.dump(results, open(os.path.join(args.out, "results.json"), "w"), indent=1)
    c = {}
    for r in results:
        c[r["result"]] = c.get(r["result"], 0) + 1
    wins = c.get("win", 0) + c.get("pts_win", 0)
    losses = c.get("loss", 0) + c.get("pts_loss", 0)
    kinds = {}
    for r in results:
        k = kinds.setdefault(MAP_KIND.get(r["map"], "?"), [0, 0])
        k[0] += r["result"] in ("win", "pts_win")
        k[1] += r["result"] in ("loss", "pts_loss")
    print("BY MAP TYPE (wins, losses):", kinds)
    print("SUMMARY", c, f"wins={wins} losses={losses} ratio={wins / max(1, losses):.2f}")


if __name__ == "__main__":
    main()
