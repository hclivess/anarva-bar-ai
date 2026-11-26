#!/usr/bin/env python3
"""
Figures from the replay database (runs/replays.db), 1v1 games:
  docs/units_timeline.png   - which units winners build in each minute (a unit x minute time map)
  docs/top_killers.png      - metal killed per attacking unit type (all players, 1v1)
  docs/heatmap_<map>.gif    - where winners place extractors, energy and defences, minute by minute

    python tools/viz_units.py [--map "Feast of Hades 1.0.1"]

Pillow + numpy only. Sequential colour = one hue (blue), light to dark; text in ink colours.
"""
import argparse
import collections
import os
import sqlite3

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "runs", "replays.db")
OUT = os.path.join(ROOT, "docs")

SURFACE = (252, 252, 251)
INK = (11, 11, 11)
INK2 = (82, 81, 78)
GRID = (229, 228, 223)
BLUE = (42, 120, 214)
# sequential blue ramp, light to dark (surface-adjacent first)
RAMP = [(235, 242, 251), (196, 219, 245), (148, 189, 236), (96, 152, 224), (42, 120, 214), (24, 84, 160), (13, 52, 104)]


def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), ("arialbd.ttf" if bold else "arial.ttf"), "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def ramp(t):
    """t in [0,1] -> colour on the sequential ramp (interpolated)."""
    t = max(0.0, min(1.0, t))
    x = t * (len(RAMP) - 1)
    i = int(x)
    if i >= len(RAMP) - 1:
        return RAMP[-1]
    f = x - i
    a, b = RAMP[i], RAMP[i + 1]
    return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))


def winners(db):
    return set(db.execute("select t.replay_id, t.team from teams t join replays r on r.id=t.replay_id "
                          "where r.format='1v1' and r.status='done' and t.won=1").fetchall())


def units_timeline(db, W_):
    MAXM = 20
    n = len(W_)
    counts = collections.defaultdict(lambda: np.zeros(MAXM + 1))
    for rid, team, unit, frame in db.execute("select replay_id, team, unit, frame from built"):
        if (rid, team) in W_ and not unit.endswith("com"):
            m = int(frame // 1800)
            if m <= MAXM:
                counts[unit][m] += 1
    top = sorted(counts, key=lambda u: -counts[u].sum())[:24]
    W, H = 1200, 160 + 28 * len(top)
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    d.text((40, 22), "What 1v1 winners build, minute by minute", font=font(26, True), fill=INK)
    d.text((40, 58), f"Units built per game in each minute, {n} winning players (top-player 1v1 replays). "
                     "The 24 most-built units; darker = more.", font=font(16), fill=INK2)
    x0, y0, cw, ch = 170, 100, (W - 290) / (MAXM + 1), 28
    vmax = max(counts[u].max() for u in top) / n
    for m in range(MAXM + 1):
        if m % 2 == 0:
            d.text((x0 + m * cw + cw / 2 - 6, y0 - 22), str(m), font=font(13), fill=INK2)
    d.text((x0 + (MAXM + 1) * cw + 8, y0 - 22), "min", font=font(13), fill=INK2)
    for r, u in enumerate(top):
        y = y0 + r * ch
        d.text((40, y + 5), u, font=font(14), fill=INK)
        for m in range(MAXM + 1):
            v = counts[u][m] / n
            if v <= 0:
                c = SURFACE
            else:
                c = ramp(v / vmax)
            d.rectangle([x0 + m * cw + 1, y + 1, x0 + (m + 1) * cw - 1, y + ch - 1], fill=c)
        tot = counts[u].sum() / n
        d.text((x0 + (MAXM + 1) * cw + 8, y + 5), f"{tot:.1f}/game", font=font(13), fill=INK2)
    # scale
    sy = y0 + len(top) * ch + 18
    d.text((40, sy), "per game per minute:", font=font(13), fill=INK2)
    for k in range(7):
        d.rectangle([200 + k * 46, sy, 200 + k * 46 + 44, sy + 16], fill=ramp(k / 6))
        d.text((200 + k * 46 + 6, sy + 18), f"{vmax * k / 6:.1f}", font=font(12), fill=INK2)
    img.save(os.path.join(OUT, "units_timeline.png"))
    return top


def top_killers(db):
    kills = collections.Counter()
    for att, vic, dmg, km in db.execute("select d.att, d.vic, d.dmg, d.kill_m from dmg d join replays r on r.id=d.replay_id "
                                        "where r.format='1v1' and r.status='done'"):
        kills[att] += km or 0.0
    top = kills.most_common(20)
    W, H = 1200, 150 + 30 * len(top)
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    d.text((40, 22), "Which units kill the most in 1v1", font=font(26, True), fill=INK)
    d.text((40, 58), "Metal value of enemy units killed, by the attacking unit type, all top-player 1v1 replays "
                     "(both players).", font=font(16), fill=INK2)
    x0, y0, bw, bh = 200, 100, W - 380, 30
    raw = (top[0][1] if top else 1) / 4.0
    e = 10 ** int(np.floor(np.log10(raw)))
    step = next(s_ * e for s_ in (1, 2, 5, 10) if raw <= s_ * e)
    vmax = step * 4
    for t in range(5):
        x = x0 + bw * t / 4
        d.line([x, y0 - 6, x, y0 + bh * len(top)], fill=GRID, width=1)
        d.text((x - 12, y0 + bh * len(top) + 6), f"{vmax * t / 4 / 1000:,.0f}k", font=font(12), fill=INK2)
    for r, (u, v) in enumerate(top):
        y = y0 + r * bh
        d.text((40, y + 6), u, font=font(14), fill=INK)
        w = bw * v / vmax
        d.rounded_rectangle([x0, y + 5, x0 + max(4, w), y + bh - 5], radius=4, fill=BLUE)
        d.text((x0 + w + 8, y + 6), f"{v / 1000:,.1f}k metal", font=font(13), fill=INK2)
    img.save(os.path.join(OUT, "top_killers.png"))


CATS = [  # (title, test on the built row)
    ("Extractors", lambda u, st, ar, bd: "mex" in u or "moho" in u),
    ("Energy", lambda u, st, ar, bd: any(k in u for k in ("win", "solar", "geo", "fus", "tide"))),
    ("Defences", lambda u, st, ar, bd: st == 1 and ar == 1),
]


def heatmap(db, W_, mapname):
    rows = db.execute("select b.replay_id, b.team, b.unit, b.frame, b.x, b.z, b.static, b.armed, b.builder from built b "
                      "join replays r on r.id=b.replay_id where r.map=? and r.format='1v1' and r.status='done'",
                      (mapname,)).fetchall()
    rows = [r for r in rows if (r[0], r[1]) in W_]
    if not rows:
        return None
    games = len({(r[0], r[1]) for r in rows})
    mx = max(r[4] for r in rows) + 1
    mz = max(r[5] for r in rows) + 1
    side = max(mx, mz)
    G = 48  # grid cells per side (display resolution, not a decision)
    MAXM = 16
    frames = []
    W, H = 1200, 560
    P = 340  # panel size in pixels
    for upto in range(1, MAXM + 1):
        img = Image.new("RGB", (W, H), SURFACE)
        d = ImageDraw.Draw(img)
        d.text((40, 22), f"Where 1v1 winners build on {mapname}", font=font(26, True), fill=INK)
        d.text((40, 58), f"{games} winning players, all their buildings up to minute {upto} (both start sides overlaid). "
                         "Darker = more buildings there.", font=font(16), fill=INK2)
        d.text((W - 160, 22), f"minute {upto}", font=font(26, True), fill=INK)
        for k, (title, test) in enumerate(CATS):
            grid = np.zeros((G, G))
            for rid, team, u, f, x, z, st_, ar, bd in rows:
                if f <= upto * 1800 and test(u, st_, ar, bd):
                    gx = min(G - 1, int(x / side * G))
                    gz = min(G - 1, int(z / side * G))
                    grid[gz, gx] += 1
            px, py = 40 + k * (P + 40), 120
            d.text((px, py - 26), title, font=font(16, True), fill=INK)
            d.rectangle([px, py, px + P, py + P], fill=SURFACE, outline=GRID)
            vmax = grid.max() if grid.max() > 0 else 1
            cell = P / G
            for gz in range(G):
                for gx in range(G):
                    v = grid[gz, gx]
                    if v > 0:
                        d.rectangle([px + gx * cell, py + gz * cell, px + (gx + 1) * cell, py + (gz + 1) * cell],
                                    fill=ramp(0.15 + 0.85 * np.sqrt(v / vmax)))
            d.text((px, py + P + 8), f"{int(grid.sum()):,} buildings ({grid.sum() / games:.1f} per player)",
                   font=font(13), fill=INK2)
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=96))
    slug = mapname.split(" ")[0].lower() + "_" + (mapname.split(" ")[1].lower() if len(mapname.split(" ")) > 1 else "")
    out = os.path.join(OUT, f"heatmap_{slug.strip('_')}.gif")
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=[450] * (len(frames) - 1) + [3000], loop=0, optimize=True)
    frames[-1].convert("RGB").save(out.replace(".gif", "_final.png"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="Feast of Hades 1.0.1")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    db = sqlite3.connect(DB)
    W_ = winners(db)
    units_timeline(db, W_)
    top_killers(db)
    hm = heatmap(db, W_, a.map)
    print("wrote units_timeline.png, top_killers.png,", hm)


if __name__ == "__main__":
    main()


def winners_vs_losers(db, out=None):
    """Median extractors, metal income and army by minute: 1v1 winners against losers."""
    won = {(r, t): w for r, t, w in db.execute("select t.replay_id, t.team, t.won from teams t join replays r on r.id=t.replay_id "
                                                "where r.format='1v1' and r.status='done'")}
    MAXM = 16
    series = {}
    for key in ("mex", "m_inc", "army"):
        series[key] = {1: [[] for _ in range(MAXM + 1)], 0: [[] for _ in range(MAXM + 1)]}
    for rid, team, minute, mex, minc, army in db.execute(
            "select s.replay_id, s.team, s.minute, s.mex, s.m_inc, s.army from stats s join replays r on r.id=s.replay_id "
            "where r.format='1v1' and r.status='done'"):
        w = won.get((rid, team))
        if w in (0, 1) and minute <= MAXM:
            for key, v in (("mex", mex), ("m_inc", minc), ("army", army)):
                if v is not None:
                    series[key][w][minute].append(v)
    W, H = 1200, 460
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    LOSE = (235, 104, 52)
    d.text((40, 22), "1v1 winners and losers: level at minute 5, apart by minute 10", font=font(26, True), fill=INK)
    d.text((40, 58), "Median by minute over all top-player 1v1 replays. Winners pull ahead by out-expanding, not by the opening.",
           font=font(16), fill=INK2)
    d.rectangle([40, 92, 66, 100], fill=BLUE); d.text((74, 86), "winners", font=font(13), fill=INK2)
    d.rectangle([160, 92, 186, 100], fill=LOSE); d.text((194, 86), "losers", font=font(13), fill=INK2)
    titles = [("mex", "Metal extractors"), ("m_inc", "Metal income (per s)"), ("army", "Army value (metal)")]
    pw, ph = (W - 120) // 3, 280
    for i, (key, title) in enumerate(titles):
        cx, cy = 40 + i * (pw + 20), 130
        ax_l, ax_r, ax_t, ax_b = cx + 50, cx + pw, cy + 26, cy + ph
        d.text((cx, cy), title, font=font(15, True), fill=INK)
        med = {w: [(st_median(series[key][w][m]) if len(series[key][w][m]) >= 4 else None) for m in range(MAXM + 1)] for w in (1, 0)}
        top = max(v for w in (1, 0) for v in med[w] if v is not None)
        raw = top / 4.0
        e = 10 ** int(np.floor(np.log10(raw)))
        step = next(s_ * e for s_ in (1, 2, 5, 10) if raw <= s_ * e)
        vmax = step * 4
        for t in range(5):
            y = ax_b - (ax_b - ax_t) * t / 4
            d.line([ax_l, y, ax_r, y], fill=GRID, width=1)
            d.text((cx, y - 8), f"{vmax * t / 4:,.0f}", font=font(12), fill=INK2)
        for m in range(0, MAXM + 1, 4):
            d.text((ax_l + (ax_r - ax_l) * m / MAXM - 5, ax_b + 4), str(m), font=font(12), fill=INK2)
        for w, col in ((0, LOSE), (1, BLUE)):
            pts = [(ax_l + (ax_r - ax_l) * m / MAXM, ax_b - (ax_b - ax_t) * med[w][m] / vmax) for m in range(MAXM + 1) if med[w][m] is not None]
            if len(pts) >= 2:
                d.line(pts, fill=col, width=3, joint="curve")
        for m in (5, 10):
            x = ax_l + (ax_r - ax_l) * m / MAXM
            d.line([x, ax_t, x, ax_b], fill=(200, 199, 194), width=1)
    img.save(out or os.path.join(OUT, "winners_vs_losers.png"))


def st_median(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


if __name__ == "__main__" and os.environ.get("ANARVA_WVL"):
    winners_vs_losers(sqlite3.connect(DB))
    print("wrote winners_vs_losers.png")
