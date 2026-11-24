#!/usr/bin/env python3
"""
Commander study from replays played by tools/run_replay.py (analyzer widget [REPLAY] COMM/CBUILD/CDEATH lines).

usage: python tools/analyze_comm.py runs/comm_study [--json out.json]

Per player kind (human vs AI), aggregated over replays:
  - distance of the commander from its start, minute by minute (median and quartiles)
  - what it is doing by phase (share of 5 s samples per command)
  - what it builds, and how far from its start
  - contact: share of samples with enemy armed metal within 600, and our/their armed metal when in contact
  - deaths: when and how far out
"""
import argparse, glob, json, os, re, statistics as st
from collections import Counter, defaultdict

TEAM = re.compile(r"\[REPLAY\] TEAM team=(\d+) ally=(-?\d+) side=\S+ name=(.*)$")
COMM = re.compile(r"\[REPLAY\] COMM f=(\d+) team=(\d+) x=-?\d+ z=-?\d+ fromStart=(\d+) hp=([\d.]+) cmd=(\S+) own600=(\d+) enemy600=(\d+) nearestEnemy=(\d+)")
CBUILD = re.compile(r"\[REPLAY\] CBUILD f=(\d+) team=(\d+) (\S+) fromStart=(\d+)")
CDEATH = re.compile(r"\[REPLAY\] CDEATH f=(\d+) team=(\d+) fromStart=(\d+)")
PHASES = ((0, 3), (3, 8), (8, 14), (14, 999))


def kind_of(name):
    return "ai" if name.startswith("AI:") else "human"


def q(xs):
    if not xs:
        return None
    xs = sorted(xs)
    pick = lambda p: xs[min(len(xs) - 1, int(p * (len(xs) - 1) + 0.5))]
    return [pick(0.25), pick(0.5), pick(0.75)]


def cmd_class(c):
    c = c.split("#")[0]
    if c.startswith("build:"):
        return "build"
    return {"RECLAIM": "reclaim", "CAPTURE": "reclaim?", "REPAIR": "repair", "GUARD": "assist", "MOVE": "move",
            "FIGHT": "fight", "ATTACK": "attack", "MANUALFIRE": "dgun", "DGUN": "dgun", "PATROL": "patrol",
            "idle": "idle", "RESURRECT": "resurrect"}.get(c, c.lower())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--json")
    ap.add_argument("--only", help="file listing replay paths; analyse only those (by file name)")
    a = ap.parse_args()
    dist = defaultdict(lambda: defaultdict(list))          # kind -> minute -> [fromStart]
    mix = defaultdict(lambda: defaultdict(Counter))        # kind -> phase -> cmd counts
    builds = defaultdict(Counter)                           # kind -> def name -> count
    bdist = defaultdict(lambda: defaultdict(list))         # kind -> def -> [fromStart]
    contact = defaultdict(lambda: defaultdict(lambda: [0, 0]))  # kind -> phase -> [contact, samples]
    ratio = defaultdict(lambda: defaultdict(list))          # kind -> phase -> [own/enemy] in contact
    deaths = defaultdict(list)
    leave = defaultdict(list)                               # kind -> first minute the commander is beyond its start area
    players = Counter()
    only = None
    if a.only:
        only = {os.path.splitext(os.path.basename(l.strip()))[0] for l in open(a.only) if l.strip()}
    for f in glob.glob(os.path.join(a.root, "*", "stdout.txt")):
        if only is not None and os.path.basename(os.path.dirname(f)) not in only:
            continue
        teams = {}
        rows = []
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = TEAM.search(line)
            if m:
                teams[int(m.group(1))] = kind_of(m.group(3).strip())
                continue
            m = COMM.search(line)
            if m:
                rows.append(m.groups())
                continue
            m = CBUILD.search(line)
            if m:
                t = int(m.group(2))
                k = teams.get(t, "?")
                builds[k][m.group(3)] += 1
                bdist[k][m.group(3)].append(int(m.group(4)))
                continue
            m = CDEATH.search(line)
            if m:
                k = teams.get(int(m.group(2)), "?")
                deaths[k].append((round(int(m.group(1)) / 1800, 1), int(m.group(3))))
        seen = set()
        first_out = {}
        for fr, t, fs, hp, cmd, own, en, near in rows:
            t, fr, fs, own, en = int(t), int(fr), int(fs), int(own), int(en)
            k = teams.get(t, "?")
            if t not in seen:
                seen.add(t)
                players[k] += 1
            minute = fr // 1800
            dist[k][minute].append(fs)
            ph = next(i for i, (lo, hi) in enumerate(PHASES) if lo <= fr / 1800 < hi)
            mix[k][ph][cmd_class(cmd)] += 1
            c = contact[k][ph]
            c[1] += 1
            if en > 0:
                c[0] += 1
                ratio[k][ph].append(own / en)
            # "out": farther than a commander's own build reach from where it started (~ its build distance x 2)
            if fs > 400 and t not in first_out:
                first_out[t] = round(fr / 1800, 2)
        for t, m in first_out.items():
            leave[teams.get(t, "?")].append(m)

    rep = {"players": dict(players)}
    for k in sorted(players):
        r = rep[k] = {}
        r["fromStart_by_minute_q25_med_q75"] = {m: q(v) for m, v in sorted(dist[k].items())}
        r["first_minute_beyond_400"] = q(leave[k])
        r["command_mix_by_phase"] = {f"{PHASES[p][0]}-{PHASES[p][1]}m": {c: round(n / sum(cnt.values()), 2) for c, n in cnt.most_common(8)}
                                     for p, cnt in sorted(mix[k].items())}
        r["contact_share_by_phase"] = {f"{PHASES[p][0]}-{PHASES[p][1]}m": round(c[0] / max(1, c[1]), 2) for p, c in sorted(contact[k].items())}
        r["own_over_enemy_in_contact_q"] = {f"{PHASES[p][0]}-{PHASES[p][1]}m": q(v) for p, v in sorted(ratio[k].items())}
        r["builds_top"] = [(d, n, q(bdist[k][d])[1]) for d, n in builds[k].most_common(15)]
        r["deaths_min_fromStart"] = sorted(deaths[k])
    txt = json.dumps(rep, indent=1)
    print(txt)
    if a.json:
        open(a.json, "w").write(txt)


if __name__ == "__main__":
    main()
