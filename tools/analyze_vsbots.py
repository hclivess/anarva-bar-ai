"""How does one human beat several BARbs? Per replay: the human's curve vs the enemy bots (each and
combined), and what the human built when. Reads run_replay.py output dirs.

usage: python analyze_vsbots.py <replay_out_root>
"""
import glob
import os
import re
import sys
from collections import Counter, defaultdict

MINUTES = (3, 5, 8, 10, 12, 15, 20, 25)
FACT = re.compile(r"(lab|vp|ap|sy|hp|gant|shltx|plat|amsub|fhp)$")
DEF = re.compile(r"(llt|hlt|hllt|beamer|claw|maw|rl|cir|madsam|flak|ferret|erad|pb|vipe|toast|amb|doom|guard|punisher|"
                 r"atl|tl|lht|mg|hive|bastion|cluster|perdition|drag|fort|gate|deflector|amd|fmd|abm|annihilator|anni)$")
ECO = re.compile(r"(solar|win|tide|fus|geo|makr|mmkr|estor|mstor|nanotc|eyes|rad|jamt)")
MEX = re.compile(r"(mex|moho|mexp)")
CON = re.compile(r"(ck|cv|ca|cs|ack|acv|aca|acsub|rectr|necro|rezbot|com)$")


def cat(name):
    if MEX.search(name):
        return "mex"
    if FACT.search(name):
        return "factory"
    if CON.search(name):
        return "builder"
    if DEF.search(name):
        return "defence"
    if ECO.search(name):
        return "eco"
    return "unit"


def main():
    root = sys.argv[1]
    agg = defaultdict(list)
    builds = Counter()
    units = Counter()
    n = 0
    for log in sorted(glob.glob(os.path.join(root, "*", "infolog.txt"))):
        text = open(log, encoding="utf-8", errors="replace").read()
        teams = {int(m.group(1)): (int(m.group(2)), m.group(4).strip()) for m in
                 re.finditer(r"\[REPLAY\] TEAM team=(\d+) ally=(-?\d+) side=(\S+) name=(.*)", text)}
        humans = [t for t, (a, nm) in teams.items() if not nm.startswith("AI:")]
        if len(humans) != 1:
            continue
        h = humans[0]
        hally = teams[h][0]
        enemies = [t for t, (a, nm) in teams.items() if a != hally and nm.startswith("AI:")]
        allies = [t for t, (a, nm) in teams.items() if a == hally and t != h]
        if not enemies:
            continue
        stats = defaultdict(dict)
        for m in re.finditer(r"\[REPLAY\] STAT min=(\d+) team=(\d+) m_inc=([\d.]+) e_inc=(\d+) army=(\d+) def=(\d+) eco=(\d+)", text):
            stats[int(m.group(2))][int(m.group(1))] = tuple(float(x) for x in m.groups()[2:])
        win = re.search(r"\[REPLAY\] WINNERS ally=([\d,]*)", text)
        won = win and str(hally) in win.group(1).split(",")
        n += 1
        last = max(stats[h]) if stats[h] else 0
        print(f"\n== {os.path.basename(os.path.dirname(log))[:55]}  human={teams[h][1]} vs {len(enemies)} enemy bots"
              f" (+{len(allies)} allies) won={bool(won)} recorded_to={last}m")
        print("   min | human m/s  army   def    eco | enemy-avg m/s  army   def   | enemy-sum army")
        for mm in MINUTES:
            if mm not in stats[h]:
                continue
            hs = stats[h][mm]
            es = [stats[e][mm] for e in enemies if mm in stats[e]]
            if not es:
                continue
            avg = [sum(x[i] for x in es) / len(es) for i in range(5)]
            ssum = sum(x[2] for x in es)
            print(f"   {mm:3d} | {hs[0]:7.1f} {hs[2]:6.0f} {hs[3]:6.0f} {hs[4]:6.0f} | {avg[0]:7.1f} {avg[2]:6.0f} {avg[3]:6.0f} | {ssum:7.0f}")
            agg[mm].append((hs[0] / max(1, avg[0]), hs[2] / max(1, ssum), hs[3], hs[4]))
        for m in re.finditer(r"\[REPLAY\] BUILT f=(\d+) team=(\d+) (\S+) m=(\d+)", text):
            if int(m.group(2)) == h and int(m.group(1)) <= 15 * 1800:
                c = cat(m.group(3))
                builds[c] += 1
                if c == "unit":
                    units[m.group(3)] += 1
    print(f"\n==== {n} human-vs-bots games")
    for mm in MINUTES:
        if agg[mm]:
            r = agg[mm]
            print(f"min {mm:2d}: human income = {sum(x[0] for x in r)/len(r):.1f}x one bot; human army = {sum(x[1] for x in r)/len(r):.2f}x ALL enemy bots;"
                  f" human def {sum(x[2] for x in r)/len(r):.0f} eco {sum(x[3] for x in r)/len(r):.0f}  (n={len(r)})")
    print("first 15 min, human builds by kind:", dict(builds.most_common()))
    print("most built combat units:", ", ".join(f"{k}x{v}" for k, v in units.most_common(15)))


if __name__ == "__main__":
    main()
