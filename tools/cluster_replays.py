#!/usr/bin/env python3
"""
Discover gameplay categories in the replay library: no labels are written in advance.

Every player-game becomes a vector of measured features from the analyzer output ([REPLAY] lines written by
tools/replay_harness during tools/run_replay.py playback). Features are standardised; a Gaussian mixture is
fitted for a range of cluster counts and the count with the lowest BIC wins. Each cluster is then described
by the features that set it apart (largest standardised centroid differences), with its member replays,
formats and win rate, so a finding can cite the replays it rests on.

usage: python tools/cluster_replays.py runs/lib_play [--index ref/lib/index.json] [--out runs/clusters.json] [--md CLUSTERS.md]
"""
import argparse, glob, json, math, os, re
from collections import defaultdict, Counter

import numpy as np
from sklearn.mixture import GaussianMixture
from sklearn.preprocessing import StandardScaler

TEAM = re.compile(r"\[REPLAY\] TEAM team=(\d+) ally=(-?\d+) side=(\S+) name=(.*)$")
MAP = re.compile(r"\[REPLAY\] MAP (.*) (\d+)x(\d+)$")
STAT = re.compile(r"\[REPLAY\] STAT min=(\d+) team=(\d+) m_inc=([\d.]+) e_inc=([\d.]+) army=(\d+) def=(\d+) eco=(\d+) units=(\d+)")
BUILT = re.compile(r"\[REPLAY\] BUILT f=(\d+) team=(\d+) (\S+) m=(\d+) tl=(\d+) air=(\d) sea=(\d) static=(\d) builder=(\d) armed=(\d) range=(\d+) fac=(\d)")
COMM = re.compile(r"\[REPLAY\] COMM f=(\d+) team=(\d+) .*fromStart=(\d+) hp=[\d.]+ cmd=\S+ own600=(\d+) enemy600=(\d+)")
HIT = re.compile(r"\[REPLAY\] FIRSTHIT f=(\d+) team=(\d+)")
MINUTES = (3, 6, 9, 12, 15, 20, 25)


def player_games(path):
    teams, mapinfo = {}, None
    stat = defaultdict(dict)
    built = defaultdict(list)
    comm = defaultdict(list)
    hit = {}
    for line in open(path, encoding="utf-8", errors="ignore"):
        m = TEAM.search(line)
        if m:
            teams[int(m.group(1))] = (int(m.group(2)), m.group(4).strip())
            continue
        m = MAP.search(line)
        if m:
            mapinfo = (m.group(1), int(m.group(2)), int(m.group(3)))
            continue
        m = STAT.search(line)
        if m:
            stat[int(m.group(2))][int(m.group(1))] = tuple(float(x) for x in m.groups()[2:])
            continue
        m = BUILT.search(line)
        if m:
            g = m.groups()
            built[int(g[1])].append((int(g[0]) / 1800.0, g[2], int(g[3]), *[int(x) for x in g[4:]]))
            continue
        m = COMM.search(line)
        if m:
            comm[int(m.group(2))].append((int(m.group(1)) / 1800.0, int(m.group(3)), int(m.group(5)) > 0))
            continue
        m = HIT.search(line)
        if m:
            hit[int(m.group(2))] = int(m.group(1)) / 1800.0
    if not teams:
        return []
    allies = Counter(a for a, _ in teams.values())
    out = []
    for t, (ally, name) in teams.items():
        if name.startswith("AI:") or t not in stat:
            continue
        f = {}
        st = stat[t]
        for mi in MINUTES:
            s = st.get(mi)
            f[f"m_inc@{mi}"] = s[0] if s else math.nan
            f[f"e_inc@{mi}"] = s[1] if s else math.nan
            if mi in (6, 12, 20):
                f[f"army@{mi}"] = s[2] if s else math.nan
                f[f"def@{mi}"] = s[3] if s else math.nan
                f[f"eco@{mi}"] = s[4] if s else math.nan
        b = built[t]
        # tuple: (minute, name, metal, tl, air, sea, static, builder, armed, range, fac)
        TL, AIR, SEA, STATIC, BUILDER, ARMED, RANGE, FAC = 3, 4, 5, 6, 7, 8, 9, 10
        mob = [x for x in b if x[ARMED] == 1 and x[STATIC] == 0 and x[BUILDER] == 0]
        mm = sum(x[2] for x in mob) or math.nan
        f["air_share"] = sum(x[2] for x in mob if x[AIR]) / mm if mob else math.nan
        f["sea_share"] = sum(x[2] for x in mob if x[SEA]) / mm if mob else math.nan
        f["t2_share"] = sum(x[2] for x in mob if x[TL] >= 2) / mm if mob else math.nan
        f["army_range"] = sum(x[2] * x[RANGE] for x in mob) / mm if mob else math.nan
        t2 = [x[0] for x in b if x[FAC] == 1 and x[TL] >= 2]
        t3 = [x[0] for x in b if x[FAC] == 1 and x[TL] >= 3]
        f["t2_lab_min"] = min(t2) if t2 else 26.0  # not within the 25-minute window
        f["t3_lab_min"] = min(t3) if t3 else 26.0
        for mi in (6, 12, 20):
            f[f"mex_by@{mi}"] = sum(1 for x in b if x[0] <= mi and ("mex" in x[1] or "moho" in x[1]))
        f["cons_by@10"] = sum(1 for x in b if x[0] <= 10 and x[BUILDER] == 1 and x[STATIC] == 0)
        statm = sum(x[2] for x in b if x[STATIC] == 1 and x[ARMED] == 1)
        f["def_built_share"] = statm / ((statm + sum(x[2] for x in mob)) or math.nan)
        c = comm[t]
        early = [d for (m_, d, _) in c if 3 <= m_ < 8]
        mid = [d for (m_, d, _) in c if 8 <= m_ < 14]
        f["comm_dist_3_8"] = float(np.median(early)) if early else math.nan
        f["comm_dist_8_14"] = float(np.median(mid)) if mid else math.nan
        cc = [k for (m_, _, k) in c if 3 <= m_ < 14]
        f["comm_contact"] = sum(cc) / len(cc) if cc else math.nan
        f["first_hit_min"] = hit.get(t, 26.0)
        f["team_size"] = float(allies[ally])
        f["n_teams"] = float(len(allies))
        f["map_area"] = float(mapinfo[1] * mapinfo[2]) / 1e6 if mapinfo else math.nan
        out.append({"team": t, "name": name, "ally": ally, "map": mapinfo[0] if mapinfo else "?", "f": f})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--index", default="ref/lib/index.json")
    ap.add_argument("--out", default="runs/clusters.json")
    ap.add_argument("--md")
    ap.add_argument("--kmax", type=int, default=12)
    a = ap.parse_args()
    index = {}
    if os.path.exists(a.index):
        for r in json.load(open(a.index)):
            index[os.path.splitext(os.path.basename(r["file"]))[0]] = r
    rows = []
    for p in glob.glob(os.path.join(a.root, "*", "stdout.txt")):
        demo = os.path.basename(os.path.dirname(p))
        meta = index.get(demo, {})
        if index and not meta:
            continue  # not in the library (e.g. an older playback)
        top = set(meta.get("top_players", [])) if meta else None
        for pg in player_games(p):
            if top is not None and "top_players" in meta and pg["name"] not in top:
                continue  # only the best players overall are analysed
            pg["replay"] = demo
            pg["id"] = meta.get("id")
            pg["format"] = meta.get("format", "?")
            pg["won"] = pg["name"] in meta.get("winners", [])
            pg["skill"] = next((s for n, s, _ in meta.get("players", []) if n == pg["name"]), None)
            rows.append(pg)
    if len(rows) < 10:
        raise SystemExit(f"only {len(rows)} player-games: play more replays first")
    names = sorted(rows[0]["f"])
    X = np.array([[r["f"][k] for k in names] for r in rows], dtype=float)
    # drop features with no data or no variation in this set
    keep = [j for j in range(X.shape[1]) if np.isfinite(X[:, j]).any() and np.nanstd(X[:, j]) > 0]
    names = [names[j] for j in keep]
    X = X[:, keep]
    med = np.nanmedian(X, axis=0)
    idx = np.where(np.isnan(X))
    X[idx] = np.take(med, idx[1])
    Z = StandardScaler().fit_transform(X)
    best = None
    bics = {}
    for k in range(1, min(a.kmax, len(rows) // 5) + 1):
        gm = GaussianMixture(k, covariance_type="diag", n_init=4, random_state=0).fit(Z)
        bics[k] = gm.bic(Z)
        if best is None or bics[k] < bics[best[0]]:
            best = (k, gm)
    k, gm = best
    lab = gm.predict(Z)
    clusters = []
    for c in range(k):
        mem = [i for i in range(len(rows)) if lab[i] == c]
        if not mem:
            continue
        cen = Z[mem].mean(axis=0)
        order = np.argsort(-np.abs(cen))[:6]
        raw = X[mem].mean(axis=0)
        desc = [(names[j], round(float(cen[j]), 2), round(float(raw[j]), 2), round(float(med[j]), 2)) for j in order]
        fmts = Counter(rows[i]["format"] for i in mem)
        wins = [rows[i]["won"] for i in mem]
        clusters.append({"cluster": c, "size": len(mem), "win_rate": round(sum(wins) / len(wins), 2),
                         "formats": dict(fmts.most_common()), "distinct": desc,
                         "members": [{"replay": rows[i]["replay"], "id": rows[i]["id"], "player": rows[i]["name"],
                                      "format": rows[i]["format"], "won": rows[i]["won"]} for i in mem]})
    clusters.sort(key=lambda c: -c["size"])
    res = {"player_games": len(rows), "features": names, "bic": {str(kk): round(v, 1) for kk, v in bics.items()},
           "k": k, "clusters": clusters}
    json.dump(res, open(a.out, "w"), indent=1)
    print(f"{len(rows)} player-games, {len(names)} features, k={k} by BIC {dict((kk, round(v)) for kk, v in bics.items())}")
    for c in clusters:
        print(f"\ncluster {c['cluster']}: {c['size']} player-games, win {c['win_rate']}, formats {c['formats']}")
        for n, z, mean, md in c["distinct"]:
            print(f"   {n:16s} z={z:+.2f}  mean {mean} (all {md})")
        print("   e.g.", ", ".join(f"{m['replay'][:40]} ({m['player']})" for m in c["members"][:3]))
    if a.md:
        lines = ["# Replay clusters", "", f"Generated by `tools/cluster_replays.py` from {len(rows)} player-games "
                 f"({len(set(r['replay'] for r in rows))} replays). Cluster count k={k} chosen by BIC. "
                 "Each cluster is described by its most distinctive features (z = standardised centroid; mean vs all).", ""]
        for c in clusters:
            lines += [f"## Cluster {c['cluster']} ({c['size']} player-games, win rate {c['win_rate']})", "",
                      "Formats: " + ", ".join(f"{f} {n}" for f, n in c["formats"].items()), "",
                      "| Feature | z | mean | all |", "|---|---|---|---|"]
            lines += [f"| {n} | {z:+.2f} | {mean} | {md} |" for n, z, mean, md in c["distinct"]]
            lines += ["", "Examples: " + "; ".join(f"`{m['replay']}` ({m['player']}, {'won' if m['won'] else 'lost'})" for m in c["members"][:5]), ""]
        open(a.md, "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
