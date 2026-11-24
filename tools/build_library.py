#!/usr/bin/env python3
"""
Build the replay library around the best players overall (not the strongest player of each game).

1. Scan recent games of every format through the public API (list + details), caching every detail
   in <out>/scan_cache.json. The details carry each player's rating, which gives a leaderboard of everyone
   seen: a player's rating is the best one they hold across game types (the site's own leaderboard is
   not machine-readable).
2. Walk that leaderboard from the top and collect the playable games each player appears in (local engine
   and game package, ended normally, >= 8 minutes) until the library holds --want games. The sample size
   sets how far down the ranking we go; there is no skill bar.
3. Every replay records which of its players are in that top group ("top_players"). Analysis uses only
   their player-games.

usage: python tools/build_library.py [--out ref/lib] [--want 500] [--scan-pages 60]
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_replays as F  # noqa: E402

PRESETS = ("duel", "team", "ffa", "teamffa")


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
    ap.add_argument("--scan-pages", type=int, default=60, help="list pages (50 games each) scanned per preset")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    engines, games = F.local_versions()
    cache_path = os.path.join(a.out, "scan_cache.json")
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}

    # 1. scan
    for preset in PRESETS:
        added = 0
        for page in range(1, a.scan_pages + 1):
            q = urllib.parse.urlencode({"page": page, "limit": 50, "preset": preset, "hasBots": "false", "endedNormally": "true"})
            try:
                items = F.get_json(f"{F.API}?{q}").get("data", [])
            except Exception as e:
                print("list error", e, flush=True); time.sleep(5); continue
            if not items:
                break
            for it in items:
                if it["id"] in cache or it.get("durationMs", 0) < 8 * 60 * 1000:
                    continue
                try:
                    d = F.get_json(f"{F.API}/{it['id']}")
                except Exception as e:
                    print("detail error", e, flush=True); time.sleep(5); continue
                time.sleep(0.15)
                players = [p for t in d.get("AllyTeams", []) for p in t.get("Players", [])]
                cache[it["id"]] = {
                    "file": d.get("fileName"), "map": d.get("Map", {}).get("scriptName"),
                    "minutes": round(d.get("durationMs", 0) / 60000, 1), "start": d.get("startTime"),
                    "playable": d.get("engineVersion") in engines and d.get("gameVersion") in games,
                    "teams": [len(t.get("Players", [])) for t in d.get("AllyTeams", [])],
                    "players": [(p["name"], F.skill(p), p.get("faction")) for p in players],
                    "winners": [p["name"] for t in d.get("AllyTeams", []) if t.get("winningTeam") for p in t.get("Players", [])],
                }
                added += 1
            if page % 5 == 0:
                json.dump(cache, open(cache_path, "w"))
                print(f"{preset}: page {page}, cached {len(cache)} (+{added})", flush=True)
        json.dump(cache, open(cache_path, "w"))

    # 2. leaderboard: best rating each player holds across what we've seen
    best = {}
    for g in cache.values():
        for name, sk, _ in g["players"]:
            if sk is not None and sk > best.get(name, -1e9):
                best[name] = sk
    ranking = sorted(best, key=lambda n: -best[n])
    by_player = {}
    for gid, g in cache.items():
        if g["playable"]:
            for name, _, _ in g["players"]:
                by_player.setdefault(name, []).append(gid)
    chosen, top = [], set()
    for name in ranking:
        if len(chosen) >= a.want:
            break
        top.add(name)
        for gid in by_player.get(name, []):
            if gid not in chosen and len(chosen) < a.want:
                chosen.append(gid)
    print(f"leaderboard: {len(ranking)} players seen; top {len(top)} cover {len(chosen)} games; "
          f"rating range of the top group {best[ranking[len(top) - 1]]:.1f}..{best[ranking[0]]:.1f}", flush=True)

    # 3. download and index
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
    from collections import Counter
    print("formats", dict(Counter(r["format"] for r in index)), "total", len(index), flush=True)


if __name__ == "__main__":
    main()
