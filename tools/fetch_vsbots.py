"""Find public replays where ONE human beats SEVERAL BARb bots, and download the playable ones.

usage: python fetch_vsbots.py <out_dir> [--min-bots 2] [--want 15] [--pages 80]
Keeps: exactly one human on the winning ally team, no other humans in the game, >= --min-bots BARb AIs
on the losing side(s), engine and game version available locally. Writes <out_dir>/index.json.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request

from fetch_replays import API, STORE, UA, get_json, local_versions, skill


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--min-bots", type=int, default=2)
    ap.add_argument("--want", type=int, default=15)
    ap.add_argument("--pages", type=int, default=80)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    engines, games = local_versions()
    idx_path = os.path.join(args.out, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else []
    have = {r["id"] for r in index}
    checked = 0
    for page in range(1, args.pages + 1):
        q = urllib.parse.urlencode({"page": page, "limit": 50, "hasBots": "true", "endedNormally": "true"})
        items = get_json(f"{API}?{q}").get("data", [])
        if not items:
            break
        for it in items:
            if it["id"] in have or it.get("durationMs", 0) < 10 * 60 * 1000:
                continue
            teams = it.get("AllyTeams", [])
            humans = sum(len(a.get("Players", [])) for a in teams)
            bots = sum(len(a.get("AIs", [])) for a in teams)
            if humans != 1 or bots < args.min_bots:
                continue
            win = [a for a in teams if a.get("winningTeam")]
            if not win or len(win[0].get("Players", [])) != 1:
                continue  # the human must be the winner
            checked += 1
            d = get_json(f"{API}/{it['id']}")
            time.sleep(0.25)
            ais = [ai for a in d.get("AllyTeams", []) for ai in a.get("AIs", [])]
            shorts = {str(ai.get("shortName", "")) for ai in ais}
            if not any("BARb" in s for s in shorts):
                continue
            if d.get("engineVersion") not in engines or d.get("gameVersion") not in games:
                continue
            dst = os.path.join(args.out, d["fileName"])
            if not os.path.exists(dst):
                req = urllib.request.Request(STORE + urllib.parse.quote(d["fileName"]), headers=UA)
                with urllib.request.urlopen(req, timeout=120) as r, open(dst, "wb") as f:
                    f.write(r.read())
            human = [p for a in d["AllyTeams"] for p in a.get("Players", [])][0]
            rec = {"id": d["id"], "file": d["fileName"], "map": d["Map"]["scriptName"],
                   "minutes": round(d["durationMs"] / 60000, 1), "human": human["name"], "skill": skill(human),
                   "bots": len(ais), "ai": sorted(shorts)}
            index.append(rec)
            have.add(d["id"])
            json.dump(index, open(idx_path, "w"), indent=1)
            print(f"+ {rec['map'][:24]:24s} {rec['minutes']:5.1f}m {rec['human']} ({rec['skill']:.0f}) vs {rec['bots']} bots {rec['ai']}", flush=True)
            if len(index) >= args.want:
                print(f"done: {len(index)}")
                return
        print(f"page {page}: candidates checked {checked}, kept {len(index)}", flush=True)
    print(f"finished: {len(index)}")


if __name__ == "__main__":
    main()
