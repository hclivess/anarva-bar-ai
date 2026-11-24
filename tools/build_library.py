#!/usr/bin/env python3
"""
Build the replay library: recent games of top players across formats, ranked, not filtered by a fixed bar.

For each format, scan recent games from the public API, read every candidate's players and skill, and keep
the games with the highest mean player skill (rank within that format: "top players" = the best of what is
being played, no cutoff). Only games this install can play back (local engine + game package) and that
ended normally after >= 8 min of play are candidates.

usage: python tools/build_library.py [--out ref/lib] [--scan-factor 4] [--only 1v1,2v2]
Writes <out>/<format>/<file>.sdfz and <out>/index.json (one record per replay, with format and mean skill).
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

# format -> (api preset, players per team or 0 for any, ally teams: 2 or 0 for 3+, how many to keep)
QUOTAS = {
    "1v1": ("duel", 1, 2, 150),
    "2v2": ("team", 2, 2, 80),
    "3v3": ("team", 3, 2, 50),
    "4v4": ("team", 4, 2, 60),
    "big": ("team", 0, 2, 100),   # 5v5 .. 8v8
    "ffa": ("ffa", 1, 0, 40),
    "teamffa": ("teamffa", 0, 0, 20),
}


def fmt_of(sizes):
    if len(sizes) > 2:
        return "ffa" if max(sizes) == 1 else "teamffa"
    if len(sizes) == 2 and sizes[0] == sizes[1]:
        return {1: "1v1", 2: "2v2", 3: "3v3", 4: "4v4"}.get(sizes[0], "big" if sizes[0] >= 5 else "other")
    return "other"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ref/lib")
    ap.add_argument("--scan-factor", type=int, default=4, help="candidates scanned per replay kept")
    ap.add_argument("--only", default="")
    ap.add_argument("--max-pages", type=int, default=80)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    engines, games = F.local_versions()
    idx_path = os.path.join(a.out, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else []
    have = {r["id"] for r in index}
    only = set(x for x in a.only.split(",") if x)
    for fmt, (preset, size, teams, keep) in QUOTAS.items():
        if only and fmt not in only:
            continue
        kept_now = sum(1 for r in index if r.get("format") == fmt)
        if kept_now >= keep:
            print(f"{fmt}: already {kept_now}/{keep}")
            continue
        want_scan = (keep - kept_now) * a.scan_factor
        cands = []
        seen = 0
        for page in range(1, a.max_pages + 1):
            q = urllib.parse.urlencode({"page": page, "limit": 50, "preset": preset, "hasBots": "false", "endedNormally": "true"})
            try:
                items = F.get_json(f"{F.API}?{q}").get("data", [])
            except Exception as e:
                print("list error", e); time.sleep(5); continue
            if not items:
                break
            for it in items:
                if it["id"] in have or it.get("durationMs", 0) < 8 * 60 * 1000:
                    continue
                sizes = [len(t.get("Players", [])) for t in it.get("AllyTeams", [])]
                if fmt_of(sizes) != fmt:
                    continue
                seen += 1
                try:
                    d = F.get_json(f"{F.API}/{it['id']}")
                except Exception as e:
                    print("detail error", e); time.sleep(5); continue
                time.sleep(0.2)
                if d.get("engineVersion") not in engines or d.get("gameVersion") not in games:
                    continue
                players = [p for t in d.get("AllyTeams", []) for p in t.get("Players", [])]
                if not players:
                    continue
                sk = [F.skill(p) for p in players]
                cands.append((sum(sk) / len(sk), d))
            print(f"{fmt}: page {page} scanned {seen} playable {len(cands)}", flush=True)
            if len(cands) >= want_scan:
                break
        cands.sort(key=lambda c: -c[0])
        for mean, d in cands[:keep - kept_now]:
            dst_dir = os.path.join(a.out, fmt)
            os.makedirs(dst_dir, exist_ok=True)
            dst = os.path.join(dst_dir, d["fileName"])
            if not os.path.exists(dst):
                try:
                    req = urllib.request.Request(F.STORE + urllib.parse.quote(d["fileName"]), headers=F.UA)
                    with urllib.request.urlopen(req, timeout=180) as r, open(dst, "wb") as f:
                        f.write(r.read())
                except Exception as e:
                    print("download error", d["fileName"], e)
                    continue
            players = [p for t in d["AllyTeams"] for p in t["Players"]]
            winners = [p["name"] for t in d["AllyTeams"] if t.get("winningTeam") for p in t["Players"]]
            index.append({"id": d["id"], "file": os.path.join(fmt, d["fileName"]).replace("\\", "/"), "format": fmt,
                          "teams": [len(t["Players"]) for t in d["AllyTeams"]], "map": d["Map"]["scriptName"],
                          "minutes": round(d["durationMs"] / 60000, 1), "start": d.get("startTime"),
                          "mean_skill": round(mean, 2), "players": [(p["name"], F.skill(p), p.get("faction")) for p in players],
                          "winners": winners})
            have.add(d["id"])
            json.dump(index, open(idx_path, "w"), indent=1)
        got = sum(1 for r in index if r.get("format") == fmt)
        sel = [r["mean_skill"] for r in index if r.get("format") == fmt]
        print(f"{fmt}: kept {got}/{keep}, mean skill of kept {min(sel) if sel else 0:.1f}..{max(sel) if sel else 0:.1f}", flush=True)
    print("total", len(index))


if __name__ == "__main__":
    main()
