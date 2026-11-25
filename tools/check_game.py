#!/usr/bin/env python3
"""
Per-game checklist (owner #92, CHECKLIST.md): read a game's infolog and answer, minute by minute:
  - Am I wasting (overflowing) or stalling metal? Energy?
  - Is my army value too low (vs the enemy's real army, vs top players at that minute)?
  - Is my army value too high for what it does (stronger than the enemy, yet nobody attacking or raiding)?
  - Is my army moving at all? Fighting? Killing?
  - Are builders or factories idle while resources pile up?

usage: python tools/check_game.py runs/<batch>/g00 [runs/<batch>/g01 ...] [--db runs/replays.db]
Reads [ANV-CHECK] lines (the AI's own per-minute assessment) and [HARNESS] stats (the truth for both teams).
"""
import argparse
import os
import re
import sqlite3

CHECK = re.compile(r"\[ANV-CHECK\] t=(\d+)m (.*)")
STAT = re.compile(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d) units=\d+ army_m=(\d+) static_m=(\d+) m_inc=([\d.]+)")
KV = re.compile(r"(\w+)=([^ ]+(?: [\d.]+/s(?: short)?)?)")


FEATURES = ("area", "mex", "water", "straight", "wind")  # measured per map by tools/analyze_maps.py
METRICS = (1, 2, 3, 4, 0)  # curve columns used to choose k: extractors, constructors, factories, energy, army


def map_features(maps_json):
    """Measured features per map name: area, extractor spots, water share, start distance, mean wind."""
    import json
    if not os.path.exists(maps_json):
        return {}
    out = {}
    for r in json.load(open(maps_json)):
        w = r.get("wind")
        out[r["name"]] = {"area": r["size"][0] * r["size"][1], "mex": r["mex"], "water": r["water"],
                          "straight": r.get("base_straight"), "wind": (w[0] + w[1]) / 2 if w else None}
    return out


def _curves(db):
    """Per map: per minute, the winners' rows (army, mex, builders, facs, e_inc)."""
    q = """select r.map, s.minute, s.army, s.mex, s.builders, s.facs, s.e_inc
           from stats s join teams t on t.replay_id=s.replay_id and t.team=s.team join replays r on r.id=s.replay_id
           where r.format='1v1' and r.status='done' and t.won=1"""
    per = {}
    for m, minute, *v in db.execute(q):
        per.setdefault(m, {}).setdefault(minute, []).append(v)
    return per


def _pool(per, maps):
    """Average winner per minute over the replays of these maps."""
    acc = {}
    for m in maps:
        for minute, rows in per.get(m, {}).items():
            acc.setdefault(minute, []).extend(rows)
    return {minute: tuple(sum(r[i] for r in rows) / len(rows) for i in range(5)) + (len(rows),) for minute, rows in acc.items()}


def _wpool(per, weights):
    """Weighted average winner per minute: each map's games weighted by the map's similarity. Also returns, per
    minute, the effective number of games n = (sum w)^2 / sum w^2 and the weighted spread (sd) of each metric."""
    acc = {}
    for m, w in weights.items():
        if w <= 0:
            continue
        for minute, rows in per.get(m, {}).items():
            for r in rows:
                acc.setdefault(minute, []).append((w, r))
    out = {}
    for minute, wr in acc.items():
        sw = sum(w for w, _ in wr)
        sw2 = sum(w * w for w, _ in wr)
        mean = [sum(w * r[i] for w, r in wr) / sw for i in range(5)]
        sd = [(sum(w * (r[i] - mean[i]) ** 2 for w, r in wr) / sw) ** 0.5 for i in range(5)]
        out[minute] = tuple(mean) + (sw * sw / sw2, sd)
    return out


def winners_curve(db_path, map_name=None, maps_json=None):
    """The winners' curve for this map. Every 1v1 winner game counts, weighted by how alike its map is to this one:
    w = exp(-d^2 / 2h^2), d the distance in standardized map features (area, extractor spots, water, start distance,
    mean wind). The width h is chosen by fit: each replay map is held out (with its games) and predicted from the
    others; the h with the smallest error wins. (k whole nearest maps let one 1-game neighbour become 'the top
    players' on Throne.) Returns the curve, a description, and per minute the effective number of games."""
    if not os.path.exists(db_path):
        return {}, "no replay database"
    db = sqlite3.connect(db_path)
    per = _curves(db)
    feats = map_features(maps_json) if maps_json else {}
    for m, v in db.execute("select r.map, e.value from events e join replays r on r.id=e.replay_id where e.kind='WIND'"):
        lo, hi, _ = (float(x) for x in v.split(","))
        if m in feats and lo >= 0 and hi >= 0:
            feats[m]["wind"] = (lo + hi) / 2
    known = [m for m in per if m in feats and all(feats[m][f] is not None for f in FEATURES)]
    if not map_name or map_name not in feats or len(known) < 2 or any(feats[map_name][f] is None for f in FEATURES):
        return _wpool(per, {m: 1.0 for m in per}), f"all {len(per)} replay maps alike (no features for {map_name!r})"
    mu = {f: sum(feats[m][f] for m in known) / len(known) for f in FEATURES}
    sd = {f: (sum((feats[m][f] - mu[f]) ** 2 for m in known) / len(known)) ** 0.5 or 1.0 for f in FEATURES}
    z = lambda m: [(feats[m][f] - mu[f]) / sd[f] for f in FEATURES]
    dist = lambda x, y: sum((p - q) ** 2 for p, q in zip(x, y)) ** 0.5
    zk = {m: z(m) for m in known}
    rows = [r for m in known for rs in per[m].values() for r in rs]
    msd = [(sum((r[i] - sum(x[i] for x in rows) / len(rows)) ** 2 for r in rows) / len(rows)) ** 0.5 or 1.0 for i in range(5)]
    # candidate widths: the distances that occur between replay maps (data, not picked numbers)
    pair = sorted({round(dist(zk[a], zk[b]), 3) for a in known for b in known if a < b})
    cands = [h for h in pair if h > 0] or [1.0]
    import math

    def weights(target_z, h, exclude=None):
        return {m: math.exp(-dist(zk[m], target_z) ** 2 / (2 * h * h)) for m in known if m != exclude}

    def err(h):
        e, n = 0.0, 0
        for hm in known:
            pred, true = _wpool(per, weights(zk[hm], h, hm)), _wpool(per, {hm: 1.0})
            for minute, t in true.items():
                if minute in pred:
                    for i in METRICS:
                        e += ((pred[minute][i] - t[i]) / msd[i]) ** 2
                        n += 1
        return e / max(1, n)
    h = min(cands, key=err)
    w = weights(z(map_name), h)
    curve = _wpool(per, w)
    top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    n8 = curve.get(8, (0,) * 5 + (0, None))[5]
    return curve, (f"all {len(known)} replay maps weighted by likeness (width {h:.2f} by held-out fit; ~{n8:.1f} effective games at minute 8); "
                   "most alike: " + ", ".join(f"{m} (w {x:.2f})" for m, x in top))


def parse(game_dir):
    log = os.path.join(game_dir, "infolog.txt")
    text = open(log, encoding="utf-8", errors="replace").read()
    checks = {}
    for m in CHECK.finditer(text):
        kv = dict(KV.findall(m.group(2)))
        checks[int(m.group(1))] = kv
    truth = {}  # minute -> {team: (army, static, m_inc)}
    for m in STAT.finditer(text):
        minute = int(m.group(1)) // 1800
        truth.setdefault(minute, {})[int(m.group(2))] = (int(m.group(3)), int(m.group(4)), float(m.group(5)))
    me = None
    script = os.path.join(game_dir, "_script.txt")
    if os.path.exists(script):  # our team: the one whose AI shortName starts with Anarva
        s = open(script, encoding="utf-8", errors="replace").read()
        # an [aiN] block nests an [options]{...} block, so take everything up to the next top-level [section]
        for blk in re.split(r"\n\s*\[(?=ai\d+\])", s, flags=re.I)[1:]:
            body = blk.split("\n[", 1)[0] if not blk.lower().startswith("ai") else blk
            if re.search(r"shortname=Anarva", body, re.I):
                t = re.search(r"^\s*team=(\d+);", body, re.M)
                me = int(t.group(1)) if t else None
                break
    mapname = None
    if os.path.exists(script):
        mm = re.search(r"^\s*mapname=([^;]+);", open(script, encoding="utf-8", errors="replace").read(), re.M | re.I)
        mapname = mm.group(1).strip() if mm else None
    return checks, truth, me, mapname


def frac(a, b):
    try:
        return int(a) / max(1, int(b))
    except ValueError:
        return 0.0


def report(game_dir, db_path, maps_json):
    checks, truth, me, mapname = parse(game_dir)
    curve, basis = winners_curve(db_path, mapname, maps_json)
    print(f"\n=== {game_dir}  (Anarva team {me})")
    if not checks:
        print("  no [ANV-CHECK] lines: the AI build predates the self-assessment")
        return
    print("  min  metal        energy       army  enemy  top1v1  ratio  moving  atk/raid/def/none  killed lost  idleB  idleF")
    flags = {"metal waste": [], "metal stall": [], "energy waste": [], "energy stall": [], "army idle while stronger": [],
             "army did not move": [], "below top players' army": [], "builders idle while wasting": [], "factory idle": [],
             "micro: more units idle with a target in reach than firing": [],
             "micro: more units hit without replying than firing": [],
             "micro: more outranged hits than shots fired": [], "micro: units standing still under fire": []}
    for minute in sorted(checks):
        c = checks[minute]
        t = truth.get(minute, {})
        enemy_true = sum(v[0] for k, v in t.items() if k != me) if (t and me is not None) else None
        top = curve.get(minute)
        army = int(c.get("army", 0))
        mv = c.get("moving", "0/0").split("/")
        moving = frac(mv[0], mv[1])
        atk, raid = int(c.get("attack", 0)), int(c.get("raid", 0))
        ib = c.get("idleBuilders", "0/0").split("/")
        ifac = c.get("idleFactories", "0/0").split("/")
        print(f"  {minute:3d}  {c.get('metal', '?')[:11]:11s}  {c.get('energy', '?')[:11]:11s}  {army:5d}  "
              f"{(enemy_true if enemy_true is not None else -1):5d}  {(int(top[0]) if top else -1):6d}  {c.get('ratio', '?'):>5s}  "
              f"{c.get('moving', '?'):>6s}  {atk}/{raid}/{c.get('defend', 0)}/{c.get('none', 0):>4}  "
              f"{c.get('killed', 0):>6s} {c.get('lost', 0):>4s}  {c.get('idleBuilders', '?'):>5s}  {c.get('idleFactories', '?'):>5s}")
        if c.get("metal", "").startswith("WASTE"): flags["metal waste"].append(minute)
        if c.get("metal", "").startswith("STALL"): flags["metal stall"].append(minute)
        if c.get("energy", "").startswith("WASTE"): flags["energy waste"].append(minute)
        if c.get("energy", "").startswith("STALL"): flags["energy stall"].append(minute)
        try:
            ratio = float(c.get("ratio", 0))
        except ValueError:
            ratio = 0.0
        if army > 0 and enemy_true is not None and army > enemy_true and atk + raid == 0:
            flags["army idle while stronger"].append(minute)
        if int(mv[1] or 0) > 0 and int(mv[0] or 0) == 0:  # not one army unit moved a second's worth all minute
            flags["army did not move"].append(minute)
        if top and army < top[0]:
            flags["below top players' army"].append(minute)
        if c.get("metal", "").startswith("WASTE") and int(ib[0] or 0) > 0:
            flags["builders idle while wasting"].append(minute)
        if int(ifac[0] or 0) > 0:
            flags["factory idle"].append(minute)
        mc = {k: int(c.get(k, 0) or 0) for k in ("microContact", "microFired", "microNoReply", "microOutranged", "microIdleInRange", "microStillHit")}
        if mc["microContact"] > 0:
            print(f"        micro (unit-seconds): contact {mc['microContact']} fired {mc['microFired']} noReply {mc['microNoReply']} "
                  f"outranged {mc['microOutranged']} idleInRange {mc['microIdleInRange']} stillHit {mc['microStillHit']}")
            if mc["microIdleInRange"] > mc["microFired"]: flags["micro: more units idle with a target in reach than firing"].append(minute)
            if mc["microNoReply"] > mc["microFired"]: flags["micro: more units hit without replying than firing"].append(minute)
            if mc["microOutranged"] > mc["microFired"]: flags["micro: more outranged hits than shots fired"].append(minute)
            if mc["microStillHit"] > 0: flags["micro: units standing still under fire"].append(minute)
    # the yardstick: the winners of top-player 1v1 games, minute by minute (CHECKLIST.md header)
    print(f"  yardstick for {mapname}: winners on {basis}")
    print("  vs top 1v1 winners (Anarva / winners +- spread, n = effective games):  min  extractors  constructors  factories  energy/s  army  n")
    behind = {"extractors": [], "constructors": [], "factories": [], "energy": [], "army": []}
    for minute in sorted(checks):
        c = checks[minute]
        top = curve.get(minute)
        if not top:
            continue
        mex = int(c.get("mex", 0) or 0)
        ib = c.get("idleBuilders", "0/0").split("/")
        ifac = c.get("idleFactories", "0/0").split("/")
        cons, facs = int(ib[1] or 0), int(ifac[1] or 0)
        try:
            einc = float(c.get("eInc", 0))
        except ValueError:
            einc = 0.0
        army = int(c.get("army", 0))
        sdv = top[6] if len(top) > 6 and top[6] else [0.0] * 5
        print(f"  {'':38s}{minute:4d}  {mex:4d}/{top[1]:5.1f}+-{sdv[1]:4.1f}  {cons:5d}/{top[2]:5.1f}+-{sdv[2]:4.1f}  {facs:4d}/{top[3]:4.1f}"
              f"  {einc:6.0f}/{top[4]:5.0f}+-{sdv[4]:4.0f}  {army:5d}/{top[0]:5.0f}+-{sdv[0]:5.0f}  {top[5]:4.1f}")
        for k, mine, theirs in (("extractors", mex, top[1]), ("constructors", cons, top[2]), ("factories", facs, top[3]),
                                ("energy", einc, top[4]), ("army", army, top[0])):
            if mine < theirs:
                behind[k].append(minute)
    for k, v in behind.items():
        flags[f"behind the winners: {k}"] = v
    print("  checklist:")
    for k, v in flags.items():
        print(f"    [{'FAIL' if v else ' ok '}] {k}" + (f": minutes {','.join(map(str, v))}" if v else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+")
    ap.add_argument("--db", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "runs", "replays.db"))
    ap.add_argument("--maps", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ref", "maps.json"))
    a = ap.parse_args()
    for g in a.games:
        report(g, a.db, a.maps)


if __name__ == "__main__":
    main()
