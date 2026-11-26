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


GAME_FEATURES = ("dstart", "ownspots", "water", "wind")


def game_features(start_me, start_them, mapf):
    """What a player faces in one game: the distance between the two actual starts, the extractor spots that are his
    (nearer to him than to the opponent and within that distance of his start), the map's water and mean wind.
    (Map-wide features described the 8v8 layout: a 1v1 on Supreme Isthmus started 3700 apart, ours on Throne 10569.)"""
    import math
    d = math.dist(start_me, start_them)
    own = sum(1 for sp in mapf.get("spots") or []
              if math.dist(sp, start_me) < math.dist(sp, start_them) and math.dist(sp, start_me) <= d)
    return {"dstart": d, "ownspots": own, "water": mapf.get("water"), "wind": mapf.get("wind")}


def _games(db, feats):
    """Every 1v1 winner game with its own features and its curve rows."""
    starts = {}
    for rid, team, x, z in db.execute(
            "select replay_id, team, x, z from comm c where frame = "
            "(select min(frame) from comm c2 where c2.replay_id=c.replay_id and c2.team=c.team)"):
        starts.setdefault(rid, {})[team] = (x, z)
    side = {}
    for rid, team, unit in db.execute("select replay_id, team, unit from built b where frame = (select min(frame) from built b2 "
                                      "where b2.replay_id=b.replay_id and b2.team=b.team)"):
        side[(rid, team)] = unit[:3]
    games = []
    q = ("select r.id, r.map, t.team from replays r join teams t on t.replay_id=r.id "
         "where r.format='1v1' and r.status='done' and t.won=1")
    for rid, mp, team in db.execute(q).fetchall():
        st = starts.get(rid, {})
        other = [t for t in st if t != team]
        if team not in st or not other or mp not in feats or not feats[mp].get("spots"):
            continue
        f = game_features(st[team], st[other[0]], feats[mp])
        f["side"] = (side.get((rid, team)), side.get((rid, other[0])))
        if any(f[k] is None for k in GAME_FEATURES):
            continue
        rows = {}
        for minute, army, mex, builders, facs, e_inc in db.execute(
                "select minute, army, mex, builders, facs, e_inc from stats where replay_id=? and team=?", (rid, team)):
            rows[minute] = [(army, mex, builders, facs, e_inc)]
        games.append({"map": mp, "f": f, "rows": rows})
    return games


def _gpool(games, weights):
    """Weighted winner per minute over games; also the effective number of games and the weighted spread."""
    acc = {}
    for g, w in zip(games, weights):
        if w <= 0:
            continue
        for minute, rs in g["rows"].items():
            for r in rs:
                acc.setdefault(minute, []).append((w, r))
    out = {}
    for minute, wr in acc.items():
        sw = sum(w for w, _ in wr)
        sw2 = sum(w * w for w, _ in wr)
        mean = [sum(w * r[i] for w, r in wr) / sw for i in range(5)]
        sd = [(sum(w * (r[i] - mean[i]) ** 2 for w, r in wr) / sw) ** 0.5 for i in range(5)]
        out[minute] = tuple(mean) + (sw * sw / sw2, sd)
    return out


def winners_curve(db_path, map_name=None, maps_json=None, starts=None, sides=None):
    """The winners' curve for this game. Every 1v1 winner game counts, weighted by how alike the game it was is to
    ours: w = exp(-d^2 / 2h^2), d the distance in standardized game features (start distance, own extractor spots,
    water, wind). The width h is chosen by fit: each map's games are held out and predicted from the other maps'; the
    h with the smallest error wins. `starts` = (ours, theirs) as actually played."""
    import math
    if not os.path.exists(db_path):
        return {}, "no replay database"
    db = sqlite3.connect(db_path)
    feats = {}
    if maps_json and os.path.exists(maps_json):
        import json
        for r in json.load(open(maps_json)):
            w = r.get("wind")
            feats[r["name"]] = {"water": r.get("water"), "wind": (w[0] + w[1]) / 2 if w else None, "spots": r.get("spots")}
    games = _games(db, feats)
    if not games:
        return {}, "no replay games with starts"
    ours = None
    if map_name in feats and starts and feats[map_name].get("spots"):
        ours = game_features(starts[0], starts[1], feats[map_name])
        ours["side"] = sides
    if ours is None or any(ours[k] is None for k in GAME_FEATURES):
        return _gpool(games, [1.0] * len(games)), f"all {len(games)} winner games alike (no starts or spots for {map_name!r})"
    mu = {k: sum(g["f"][k] for g in games) / len(games) for k in GAME_FEATURES}
    sd = {k: (sum((g["f"][k] - mu[k]) ** 2 for g in games) / len(games)) ** 0.5 or 1.0 for k in GAME_FEATURES}
    z = lambda f: [(f[k] - mu[k]) / sd[k] for k in GAME_FEATURES]
    zs = [z(g["f"]) + [g["f"].get("side")] for g in games]

    def dist(x, y):
        d2 = sum((p - q) ** 2 for p, q in zip(x[:-1], y[:-1]))
        if x[-1] and y[-1]:  # the faction matchup: each side that differs counts one standard unit
            d2 += sum(1.0 for a, b in zip(x[-1], y[-1]) if a and b and a != b)
        return d2 ** 0.5
    rows = [r for g in games for rs in g["rows"].values() for r in rs]
    msd = [(sum((r[i] - sum(x[i] for x in rows) / len(rows)) ** 2 for r in rows) / len(rows)) ** 0.5 or 1.0 for i in range(5)]
    pair = sorted({round(dist(zs[i], zs[j]), 3) for i in range(len(games)) for j in range(i + 1, len(games))})
    pair = [x for x in pair if x > 0] or [1.0]
    # candidate widths: the deciles of the distances that occur between games (the error is smooth in h)
    cands = sorted({pair[int(q * (len(pair) - 1) / 10)] for q in range(11)})
    maps = sorted({g["map"] for g in games})

    def err(h):
        e, n = 0.0, 0
        for hm in maps:
            for i, g in enumerate(games):
                if g["map"] != hm:
                    continue
                w = [0.0 if games[j]["map"] == hm else math.exp(-dist(zs[j], zs[i]) ** 2 / (2 * h * h))
                     for j in range(len(games))]
                if sum(w) <= 0:  # nothing alike: predicted from every other map's games, its error counts in full
                    w = [0.0 if games[j]["map"] == hm else 1.0 for j in range(len(games))]
                pred = _gpool(games, w)
                for minute, rs in g["rows"].items():
                    if minute in pred:
                        for k in METRICS:
                            e += ((pred[minute][k] - rs[0][k]) / msd[k]) ** 2
                            n += 1
        return e / max(1, n)
    h = min(cands, key=err)
    zo = z(ours) + [ours.get("side")]
    w = [math.exp(-dist(zg, zo) ** 2 / (2 * h * h)) for zg in zs]
    curve = _gpool(games, w)
    top = sorted(zip(w, range(len(games))), key=lambda t: -t[0])[:4]
    n8 = curve.get(8, (0,) * 5 + (0, None))[5]
    return curve, (f"{len(games)} winner games weighted by likeness to ours (start distance {ours['dstart']:.0f}, "
                   f"own spots {ours['ownspots']}, water {ours['water']}, wind {ours['wind']}; width {h:.2f} by held-out "
                   f"fit; ~{n8:.1f} effective games at minute 8); most alike: "
                   + ", ".join(f"{games[i]['map']} (start distance {games[i]['f']['dstart']:.0f}, own spots "
                               f"{games[i]['f']['ownspots']}, w {x:.2f})" for x, i in top))



def _box_of(script_text, ally, size):
    """A start box from a game script ([allyteamN] startrect*, fractions of the map size)."""
    for a, body in re.findall(r'\[allyteam(\d+)\]\s*\{([^}]*)\}', script_text):
        if int(a) != ally:
            continue
        g = {k: float(v) for k, v in re.findall(r'startrect(left|right|top|bottom)=([\d.]+)', body)}
        if len(g) == 4:
            return (g['left'] * size[0], g['right'] * size[0], g['top'] * size[1], g['bottom'] * size[1])
    return None


def start_features(pos, box, enemy_box, spots):
    """Where a start sits: 0 at the back edge of its box .. 1 at the front (toward the enemy box), and the distance
    to its 3rd-nearest extractor spot (what the commander reaches without walking)."""
    import math
    L, R, T, B = box
    cx, cz = (L + R) / 2, (T + B) / 2
    ex, ez = (enemy_box[0] + enemy_box[1]) / 2, (enemy_box[2] + enemy_box[3]) / 2
    n = math.hypot(ex - cx, ez - cz) or 1.0
    ux, uz = (ex - cx) / n, (ez - cz) / n
    proj = [x * ux + z * uz for x, z in ((L, T), (L, B), (R, T), (R, B))]
    fwd = (pos[0] * ux + pos[1] * uz - min(proj)) / ((max(proj) - min(proj)) or 1.0)
    near = sorted(math.dist(pos, sp) for sp in spots)
    return fwd, (near[2] if len(near) > 2 else None)


def winners_starts(db_path, maps_json, cache):
    """Forward position and 3rd-nearest spot of every 1v1 winner's start (replay scripts + commander at frame 0)."""
    import gzip, json
    if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(db_path):
        return json.load(open(cache))
    db = sqlite3.connect(db_path)
    maps = {x['name']: x for x in json.load(open(maps_json))}
    starts = {}
    for rid, team, x, z in db.execute("select replay_id, team, x, z from comm c where frame = (select min(frame) from comm c2 "
                                      "where c2.replay_id=c.replay_id and c2.team=c.team)"):
        starts.setdefault(rid, {})[team] = (x, z)
    out = []
    lib = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'ref', 'lib')
    for rid, f, mp in db.execute("select id, file, map from replays where format='1v1' and status='done'").fetchall():
        path = os.path.join(lib, f)
        if not os.path.exists(path) or rid not in starts or mp not in maps or not maps[mp].get('spots'):
            continue
        raw = gzip.open(path).read(300000)
        i = raw.find(b'[game]')
        st = raw[i:i + 80000].decode('latin-1')
        team_ally = {int(t): int(a) for t, a in re.findall(r'\[team(\d+)\]\s*\{[^}]*?allyteam=(\d+)', st)}
        for team, won in db.execute("select team, won from teams where replay_id=?", (rid,)).fetchall():
            if won != 1 or team not in starts[rid] or team not in team_ally:
                continue
            a = team_ally[team]
            box = _box_of(st, a, maps[mp]['size'])
            other = [x for x in set(team_ally.values()) if x != a]
            ebox = _box_of(st, other[0], maps[mp]['size']) if other else None
            if box and ebox:
                fwd, third = start_features(starts[rid][team], box, ebox, maps[mp]['spots'])
                out.append([fwd, third])
    json.dump(out, open(cache, 'w'))
    return out

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
    starts = {}
    coms = {}
    for m in re.finditer(r"\[HARNESS\] start team=(\d+) x=(-?\d+) z=(-?\d+)(?: com=(\w+))?", text):
        starts[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
        if m.group(4):
            coms[int(m.group(1))] = m.group(4)[:3]
    starts["_coms"] = coms
    return checks, truth, me, mapname, starts


def opening_vs_winners(game_dir, db_path, mapname, until_s=180):
    """What we built by 3:00 next to what the 1v1 winners on this map built (replays.db; owner, 2026-11-25: real
    players and the parsed replays are the main cross-reference, not BARb)."""
    import collections
    import sqlite3
    log = os.path.join(game_dir, "infolog.txt")
    if not os.path.exists(log) or not os.path.exists(db_path):
        return
    ours = collections.Counter()
    for m in re.finditer(r"\[ANV\] built ([a-z]+) t=(\d+)", open(log, encoding="utf-8", errors="replace").read()):
        if int(m.group(2)) <= until_s and not m.group(1)[3:].startswith("com"):
            ours[m.group(1)[3:]] += 1
    db = sqlite3.connect(db_path)
    key = (mapname or "").split(" ")[0] + "%"
    rows = db.execute("""select b.replay_id, b.team, b.unit from built b join replays r on r.id=b.replay_id
        join teams t on t.replay_id=b.replay_id and t.team=b.team
        where r.format='1v1' and r.status='done' and t.won=1 and b.frame<=? and r.map like ?""", (until_s * 30, key)).fetchall()
    games = collections.defaultdict(collections.Counter)
    for rid, team, u in rows:
        games[(rid, team)][u[3:]] += 1
    n = len(games)
    if n == 0:
        print(f"  opening by {until_s // 60}:{until_s % 60:02d}: no winner replays on {mapname}")
        return
    theirs = collections.Counter()
    for c in games.values():
        theirs.update(c)
    units = sorted(set(ours) | {u for u, c in theirs.items() if c / n >= 0.2}, key=lambda u: -(theirs[u] / n + ours[u]))
    print(f"  opening by {until_s // 60}:{until_s % 60:02d}, ours/winners on this map ({n} games, replays.db):")
    print("    " + "  ".join(f"{u}={ours[u]}/{theirs[u] / n:.1f}" for u in units if u != "com"))


def win_chance_report(game_dir, me):
    """Win chance against this opponent by minute, from the replay model (tools/winprob.py; relative to the opponent:
    metal income, energy income, army - what the harness logs for both teams), and the gap that costs the most."""
    import importlib.util
    log = os.path.join(game_dir, "infolog.txt")
    spec_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "winprob.py")
    if me is None or not os.path.exists(log) or not os.path.exists(spec_path):
        return
    spec = importlib.util.spec_from_file_location("winprob", spec_path)
    wp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wp)
    per = {}
    for m in re.finditer(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d+) [^\n]*?army_m=([\d.]+)[^\n]*?m_inc=([\d.]+) e_inc=([\d.]+)",
                         open(log, encoding="utf-8", errors="replace").read()):
        f, team = int(m.group(1)), int(m.group(2))
        if f % 1800 == 0:
            per.setdefault(f // 1800, {})[team] = [float(m.group(4)), float(m.group(5)), float(m.group(3))]
    rows = []
    for minute in sorted(per):
        teams = per[minute]
        if me not in teams or len(teams) != 2:
            continue
        other = [t for t in teams if t != me][0]
        g = wp.relative_gaps(minute, teams[me], teams[other])
        if g is None:
            continue
        p, auc, costs = g
        informative = json_info(wp, minute)
        best = costs[0]
        rows.append((minute, p, auc, informative, best))
    if not rows:
        return
    print("  win chance vs this opponent (replay model, relative metal income / energy income / army; AUC = trust):")
    names = {"m_inc": "metal income", "e_inc": "energy income", "army": "army"}
    for minute, p, auc, informative, (dp, f, ours, theirs) in rows:
        if not informative:
            print(f"    min {minute:2d}: model has no information at this minute")
            continue
        gap = f"biggest cost: {names[f]} {ours:,.0f} vs {theirs:,.0f} (+{dp * 100:.0f} points if matched)" if dp > 0.005 else "no gap that costs"
        print(f"    min {minute:2d}: {p * 100:3.0f}%  (AUC {auc:.2f})  {gap}")


def json_info(wp, minute):
    import json as _json
    try:
        return bool(_json.load(open(wp.REL_MODEL))["minutes"][str(minute)].get("informative", True))
    except (OSError, KeyError):
        return False


def json_coef(wp, minute):
    import json as _json
    try:
        return _json.load(open(wp.REL_MODEL))["minutes"][str(minute)]["coef"]
    except (OSError, KeyError):
        return []


def frac(a, b):
    try:
        return int(a) / max(1, int(b))
    except ValueError:
        return 0.0


def report(game_dir, db_path, maps_json):
    checks, truth, me, mapname, starts = parse(game_dir)
    coms = starts.pop("_coms", {})
    pair, sides = None, None
    if me is not None and me in starts:
        other = [t for t in starts if t != me]
        if other:
            pair = (starts[me], starts[other[0]])
            sides = (coms.get(me), coms.get(other[0]))
    curve, basis = winners_curve(db_path, mapname, maps_json, pair, sides)
    print(f"\n=== {game_dir}  (Anarva team {me})")
    opening_vs_winners(game_dir, db_path, mapname)
    win_chance_report(game_dir, me)
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
    # the start, against where winners start (a fixed start is judged the same way: it is what we had to play)
    try:
        import json, statistics as stt
        script = open(os.path.join(game_dir, "_script.txt"), encoding="utf-8", errors="replace").read()
        spt = re.search(r"startpostype=(\d+)", script)
        maps = {x['name']: x for x in json.load(open(maps_json))}
        if pair and mapname in maps and maps[mapname].get('spots'):
            allies = {int(t): int(a) for t, a in re.findall(r'\[team(\d+)\]\s*\{[^}]*?allyteam=(\d+)', script)}
            ourA = allies.get(me)
            box = _box_of(script, ourA, maps[mapname]['size']) if ourA is not None else None
            ebox = _box_of(script, [a for a in set(allies.values()) if a != ourA][0], maps[mapname]['size']) if box else None
            if box and ebox:
                fwd, third = start_features(pair[0], box, ebox, maps[mapname]['spots'])
                ws = winners_starts(db_path, maps_json, os.path.join(os.path.dirname(db_path), "winners_starts.json"))
                q = stt.quantiles([w[0] for w in ws], n=4)
                q3 = stt.quantiles([w[1] for w in ws if w[1] is not None], n=4)
                print(f"  start ({'chosen' if spt and spt.group(1) == '2' else 'given'}): forward {fwd:.2f} (winners {q[0]:.2f}-{q[2]:.2f}), "
                      f"3rd-nearest spot {third:.0f} (winners {q3[0]:.0f}-{q3[2]:.0f})")
    except Exception as e:
        print(f"  start: not assessed ({e})")
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
    # PROCESS.md step 3: every gap in the winners' own spread, largest first (the next job is the top one)
    gaps = []
    for minute in sorted(checks):
        c = checks[minute]
        top = curve.get(minute)
        if not top or len(top) < 7 or not top[6]:
            continue
        ib = c.get("idleBuilders", "0/0").split("/")
        ifac = c.get("idleFactories", "0/0").split("/")
        try:
            einc = float(c.get("eInc", 0))
        except ValueError:
            einc = 0.0
        mine = {"extractors": int(c.get("mex", 0) or 0), "constructors": int(ib[1] or 0), "factories": int(ifac[1] or 0),
                "energy": einc, "army": int(c.get("army", 0))}
        idx = {"army": 0, "extractors": 1, "constructors": 2, "factories": 3, "energy": 4}
        for k, i in idx.items():
            sdv = top[6][i]
            if sdv > 0:
                gaps.append(((mine[k] - top[i]) / sdv, k, minute, mine[k], top[i]))
    worst = {}
    for zv, k, minute, a, b in gaps:
        if k not in worst or zv < worst[k][0]:
            worst[k] = (zv, minute, a, b)
    # where it started going wrong: late gaps are the consequences of losing; the earliest minute a metric falls more
    # than one winners' spread behind is where the causes are
    first = {}
    for zv, k, minute, a, b in sorted(gaps, key=lambda g: g[2]):
        if zv < -1.0 and k not in first:
            first[k] = (minute, zv, a, b)
    print("  where it started going wrong (first minute more than one winners' spread behind; PROCESS.md step 3):")
    for k, (minute, zv, a, b) in sorted(first.items(), key=lambda kv: (kv[1][0], kv[1][1])):
        print(f"    minute {minute:2d}  {k:12s} {a:.0f} vs {b:.1f} ({zv:+.1f} spreads)")
    if first:
        k, (minute, zv, a, b) = min(first.items(), key=lambda kv: (kv[1][0], kv[1][1]))
        print(f"  NEXT JOB: {k} at minute {minute} - find in the replays why the winners have {b:.0f} by then, and why we have {a:.0f}")
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
