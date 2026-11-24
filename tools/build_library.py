#!/usr/bin/env python3
"""
Build the replay library from the games of the best players overall: the official BAR leaderboard.

1. Players: ref/leaderboard.json (tools/fetch_leaderboard.py: Small Team, Large Team, Duel, FFA, top 100 each),
   ranked by each player's best position on any board.
2. Games: the replay API filters by player (`players=<name>`). Round-robin over the ranking: each pass takes
   the next most recent playable game (local engine + game package, ended normally, >= 8 min of play) of every
   player, best ranked first, until the library holds --want games. Every top player is represented and the
   best come first; the sample size, not a skill bar, decides how deep each player's history goes.
3. Every replay records which of its players are on the leaderboard ("top_players"); analysis uses only theirs.
   Details are cached in <out>/scan_cache.json, so a rerun resumes.

usage: python tools/build_library.py [--out ref/lib] [--want 500] [--leaderboard ref/leaderboard.json]
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_replays as F  # noqa: E402


def fmt_of(sizes):
    if len(sizes) > 2:
        return "ffa" if max(sizes) == 1 else "teamffa"
    if len(sizes) == 2 and sizes[0] == sizes[1]:
        return {1: "1v1", 2: "2v2", 3: "3v3", 4: "4v4"}.get(sizes[0], "big")
    return "uneven"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ref/lib")
    ap.add_argument("--want", type=int, default=500)
    ap.add_argument("--leaderboard", default="ref/leaderboard.json")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    engines, games = F.local_versions()
    lb = json.load(open(a.leaderboard, encoding="utf-8"))
    pos = {}
    for b in lb["boards"]:
        for i, p in enumerate(b["players"]):
            pos[p["name"]] = min(pos.get(p["name"], 10 ** 9), i)
    ranking = sorted(pos, key=lambda n: pos[n])
    top = set(ranking)
    print(f"leaderboard season {lb['season']}: {len(ranking)} distinct players on 4 boards", flush=True)

    cache_path = os.path.join(a.out, "scan_cache.json")
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    queues = {n: [] for n in ranking}      # per player: candidate game ids, most recent first
    pages = {n: 0 for n in ranking}
    exhausted = set()
    chosen = []

    def detail(gid):
        if gid not in cache:
            d = F.get_json(f"{F.API}/{gid}")
            time.sleep(0.15)
            cache[gid] = {
                "file": d.get("fileName"), "map": d.get("Map", {}).get("scriptName"),
                "minutes": round(d.get("durationMs", 0) / 60000, 1), "start": d.get("startTime"),
                "playable": d.get("engineVersion") in engines and d.get("gameVersion") in games,
                "teams": [len(t.get("Players", [])) for t in d.get("AllyTeams", [])],
                "players": [(p["name"], F.skill(p), p.get("faction")) for p in (pl for t in d.get("AllyTeams", []) for pl in t.get("Players", []))],
                "winners": [p["name"] for t in d.get("AllyTeams", []) if t.get("winningTeam") for p in t.get("Players", [])],
            }
        return cache[gid]

    def next_game(name):
        while True:
            while not queues[name]:
                if name in exhausted:
                    return None
                pages[name] += 1
                q = urllib.parse.urlencode({"page": pages[name], "limit": 50, "players": name, "hasBots": "false", "endedNormally": "true"})
                try:
                    items = F.get_json(f"{F.API}?{q}").get("data", [])
                except Exception as e:
                    print("list error", name, e, flush=True); time.sleep(5); return None
                if not items or pages[name] > 6:  # the most recent ~300 games of a player are plenty
                    exhausted.add(name)
                    if not items:
                        return None
                queues[name] += [it["id"] for it in items if it.get("durationMs", 0) >= 8 * 60 * 1000]
            gid = queues[name].pop(0)
            if gid in chosen:
                continue
            try:
                g = detail(gid)
            except Exception as e:
                print("detail error", e, flush=True); time.sleep(5); continue
            if g["playable"] and name in [p[0] for p in g["players"]]:
                return gid

    passes = 0
    while len(chosen) < a.want and len(exhausted) < len(ranking):
        passes += 1
        for name in ranking:
            if len(chosen) >= a.want:
                break
            gid = next_game(name)
            if gid:
                chosen.append(gid)
        json.dump(cache, open(cache_path, "w"))
        print(f"pass {passes}: {len(chosen)} games", flush=True)

    index = []
    for gid in chosen:
        g = cache[gid]
        fmt = fmt_of(g["teams"])
        dst_dir = os.path.join(a.out, fmt)
        os.makedirs(dst_dir, exist_ok=True)
        dst = os.path.join(dst_dir, g["file"])
        if not os.path.exists(dst):
            try:
                req = urllib.request.Request(F.STORE + urllib.parse.quote(g["file"]), headers=F.UA)
                with urllib.request.urlopen(req, timeout=180) as r, open(dst, "wb") as f:
                    f.write(r.read())
            except Exception as e:
                print("download error", g["file"], e, flush=True)
                continue
        index.append({"id": gid, "file": f"{fmt}/{g['file']}", "format": fmt, "teams": g["teams"], "map": g["map"],
                      "minutes": g["minutes"], "start": g["start"], "players": g["players"], "winners": g["winners"],
                      "top_players": [n for n, _, _ in g["players"] if n in top]})
        if len(index) % 25 == 0:
            json.dump(index, open(os.path.join(a.out, "index.json"), "w"), indent=1)
            print(f"downloaded {len(index)}/{len(chosen)}", flush=True)
    json.dump(index, open(os.path.join(a.out, "index.json"), "w"), indent=1)
    print("formats", dict(Counter(r["format"] for r in index)), "total", len(index), flush=True)


if __name__ == "__main__":
    main()
