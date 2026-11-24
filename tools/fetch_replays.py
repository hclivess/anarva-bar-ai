"""Find and download high-skill public BAR replays that this install can play back.

usage: python fetch_replays.py <out_dir> [--preset duel|team|ffa|teamffa] [--team-size N] [--min-skill 40] [--want 20] [--pages 60]
Keeps replays whose engine is installed locally and whose game version has a local rapid package,
with every player's OpenSkill >= --min-skill. Writes <out_dir>/index.json.
"""
import argparse
import gzip
import json
import os
import re
import time
import urllib.parse
import urllib.request

API = "https://api.bar-rts.com/replays"
STORE = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
BAR_DATA = r"C:\Hry\Beyond-All-Reason\data"
UA = {"User-Agent": "replay-research-script/1.0"}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def local_versions():
    engines = {d[len("recoil_"):] for d in os.listdir(os.path.join(BAR_DATA, "engine")) if d.startswith("recoil_")}
    games = set()
    vfile = os.path.join(BAR_DATA, "rapid", "repos-cdn.beyondallreason.dev", "byar", "versions.gz")
    for line in gzip.open(vfile).read().decode("utf-8", "replace").splitlines():
        parts = line.split(",")
        if len(parts) >= 4 and os.path.exists(os.path.join(BAR_DATA, "packages", parts[1] + ".sdp")):
            games.add(parts[3])
    return engines, games


def skill(p):
    m = re.search(r"[\d.]+", str(p.get("skill") or ""))
    return float(m.group()) if m else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--preset", default="duel")
    ap.add_argument("--min-skill", type=float, default=40.0)
    ap.add_argument("--want", type=int, default=20)
    ap.add_argument("--pages", type=int, default=60)
    ap.add_argument("--team-size", type=int, default=0, help="players per ally team (2 = 2v2, 8 = 8v8); 0 = any")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    engines, games = local_versions()
    print(f"local engines={sorted(engines)} games={len(games)}")
    idx_path = os.path.join(args.out, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else []
    have = {r["id"] for r in index}
    checked = 0
    for page in range(1, args.pages + 1):
        q = urllib.parse.urlencode({"page": page, "limit": 50, "preset": args.preset,
                                    "hasBots": "false", "endedNormally": "true"})
        items = get_json(f"{API}?{q}").get("data", [])
        if not items:
            break
        for it in items:
            if it["id"] in have or it.get("durationMs", 0) < 8 * 60 * 1000:
                continue
            if args.team_size and any(len(a.get("Players", [])) != args.team_size for a in it.get("AllyTeams", [])):
                continue  # the list already carries the teams: skip other sizes without a detail request
            checked += 1
            d = get_json(f"{API}/{it['id']}")
            time.sleep(0.25)
            players = [p for a in d.get("AllyTeams", []) for p in a.get("Players", [])]
            if not players or min(skill(p) for p in players) < args.min_skill:
                continue
            if d.get("engineVersion") not in engines or d.get("gameVersion") not in games:
                continue
            dst = os.path.join(args.out, d["fileName"])
            if not os.path.exists(dst):
                req = urllib.request.Request(STORE + urllib.parse.quote(d["fileName"]), headers=UA)
                with urllib.request.urlopen(req, timeout=120) as r, open(dst, "wb") as f:
                    f.write(r.read())
            winners = [p["name"] for a in d["AllyTeams"] if a.get("winningTeam") for p in a["Players"]]
            sizes = [len(a.get("Players", [])) for a in d.get("AllyTeams", [])]
            fmt = ("ffa" if len(sizes) > 2 else "v".join(str(x) for x in sizes)) if sizes else "?"
            rec = {"id": d["id"], "file": d["fileName"], "format": fmt, "map": d["Map"]["scriptName"], "minutes": round(d["durationMs"] / 60000, 1),
                   "players": [(p["name"], skill(p), p.get("faction")) for p in players], "winners": winners}
            index.append(rec)
            have.add(d["id"])
            json.dump(index, open(idx_path, "w"), indent=1)
            print(f"+ {rec['map'][:24]:24s} {rec['minutes']:5.1f}m {rec['players']} win={winners}", flush=True)
            if len(index) >= args.want:
                print(f"done: {len(index)} replays (checked {checked})")
                return
        print(f"page {page}: checked {checked}, kept {len(index)}", flush=True)
    print(f"finished: {len(index)} replays (checked {checked})")


if __name__ == "__main__":
    main()
