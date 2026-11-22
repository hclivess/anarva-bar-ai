"""Index BAR replays: map, players with skill, AI presence. Writes CSV and prints the top games.

usage: python index_replays.py <demos_dir> <out.csv> [--top 25]
"""
import argparse
import csv
import glob
import gzip
import os
import re


def read_script(path):
    try:
        with gzip.open(path) as f:
            head = f.read(400000).decode("latin1")
    except Exception:
        return None
    i = head.find("[game]")
    return head[i:] if i >= 0 else None


def parse(script):
    players, ais = [], 0
    for m in re.finditer(r"\[player\d+\]\s*\{(.*?)\}", script, re.S):
        body = m.group(1)
        if re.search(r"spectator\s*=\s*1", body):
            continue
        name = re.search(r"name=([^;]*);", body)
        skill = re.search(r"skill=\[?([\d.]+)", body)
        players.append((name.group(1) if name else "?", float(skill.group(1)) if skill else 0.0))
    ais = len(re.findall(r"\[ai\d+\]", script))
    mapname = re.search(r"mapname=([^;]*);", script)
    return players, ais, mapname.group(1) if mapname else "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("demos")
    ap.add_argument("out")
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()
    rows = []
    for path in glob.glob(os.path.join(args.demos, "*.sdfz")):
        if os.path.getsize(path) < 300_000:  # too short to learn from
            continue
        s = read_script(path)
        if not s:
            continue
        players, ais, mapname = parse(s)
        if not players:
            continue
        skills = [p[1] for p in players]
        rows.append({"file": os.path.basename(path), "map": mapname, "humans": len(players), "ais": ais,
                     "avg_skill": round(sum(skills) / len(skills), 1), "max_skill": max(skills),
                     "mb": round(os.path.getsize(path) / 1e6, 1),
                     "players": " | ".join(f"{n}:{s:.0f}" for n, s in players)})
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} replays indexed")
    for kind, flt in (("1v1 (no AI)", lambda r: r["humans"] == 2 and r["ais"] == 0),
                      ("small teams <=8 (no AI)", lambda r: 2 < r["humans"] <= 8 and r["ais"] == 0),
                      ("big teams", lambda r: r["humans"] > 8 and r["ais"] == 0)):
        sel = sorted(filter(flt, rows), key=lambda r: -r["avg_skill"])
        print(f"\n== {kind}: {len(sel)} games; top by avg skill")
        for r in sel[:args.top]:
            print(f"{r['avg_skill']:5.1f} {r['mb']:5.1f}MB {r['map'][:28]:28s} {r['file'][:40]}  {r['players'][:90]}")


if __name__ == "__main__":
    main()
