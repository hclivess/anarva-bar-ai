#!/usr/bin/env python3
"""
Animated GIF of the replay research: what 1v1 winners have by each minute (median and middle half, from
runs/replays.db) next to one Anarva game (its [ANV-CHECK] lines), plus the winners' milestones.

    python tools/viz_replays.py [--game runs/<batch>/gNN] [--out docs/replay_research.gif]

Pillow + numpy only (no matplotlib). Palette: the dataviz reference instance, light surface.
"""
import argparse
import os
import re
import sqlite3
import statistics as st

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "runs", "replays.db")

SURFACE = (252, 252, 251)
INK = (11, 11, 11)
INK2 = (82, 81, 78)
GRID = (229, 228, 223)
WIN = (42, 120, 214)        # series 1 (blue): winners
WIN_BAND = (42, 120, 214, 46)
ANV = (235, 104, 52)        # series 2 (orange): Anarva

MEASURES = [  # (title, db column, check-line key, unit)
    ("Metal extractors", "mex", "mex", ""),
    ("Energy income", "e_inc", "eInc", " E/s"),
    ("Army value", "army", "army", " metal"),
    ("Factories", "facs", "fac", ""),
]
MILESTONES = [  # (label, unit names): first appearance per winner, from the built table
    ("lab", ["armlab", "corlab", "armvp", "corvp", "armap", "corap", "armhp", "corhp"]),
    ("construction turret", ["armnanotc", "cornanotc"]),
    ("T2 factory", ["armalab", "coralab", "armavp", "coravp", "armaap", "coraap", "armasy", "corasy"]),
    ("fusion", ["armfus", "corfus", "armckfus"]),
]
MAX_MIN = 16


def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), ("arialbd.ttf" if bold else "arial.ttf"), "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def winners():
    db = sqlite3.connect(DB)
    wins = db.execute("select t.replay_id, t.team from teams t join replays r on r.id=t.replay_id "
                      "where r.format='1v1' and r.status='done' and t.won=1").fetchall()
    W = set(wins)
    per = {m[1]: {k: [] for k in range(MAX_MIN + 1)} for m in MEASURES}
    for rid, team, minute, mex, einc, army, facs in db.execute(
            "select replay_id, team, minute, mex, e_inc, army, facs from stats"):
        if (rid, team) in W and minute <= MAX_MIN:
            for col, v in (("mex", mex), ("e_inc", einc), ("army", army), ("facs", facs)):
                if v is not None:
                    per[col][minute].append(v)
    curves = {}
    for col, mins in per.items():
        med, lo, hi = [], [], []
        for k in range(MAX_MIN + 1):
            xs = sorted(mins[k])
            if len(xs) >= 4:
                med.append(st.median(xs)); lo.append(xs[len(xs) // 4]); hi.append(xs[3 * len(xs) // 4])
            else:
                med.append(None); lo.append(None); hi.append(None)
        curves[col] = (med, lo, hi)
    first = {}
    for rid, team, unit, frame in db.execute("select replay_id, team, unit, frame from built order by frame"):
        if (rid, team) in W:
            first.setdefault((rid, team), {}).setdefault(unit, frame)
    ms = []
    for label, units in MILESTONES:
        ts = [min(f[u] for u in units if u in f) / 1800.0 for f in first.values() if any(u in f for u in units)]
        if ts:
            ms.append((label, st.median(ts), len(ts)))
    return curves, ms, len(W)


def anarva(game_dir):
    text = open(os.path.join(game_dir, "infolog.txt"), encoding="utf-8", errors="replace").read()
    out = {m[2]: [None] * (MAX_MIN + 1) for m in MEASURES}
    for m in re.finditer(r"\[ANV-CHECK\] t=(\d+)m ([^\n]*)", text):
        k = int(m.group(1))
        if k > MAX_MIN:
            continue
        line = m.group(2)
        for key in ("mex", "eInc", "army"):
            mm = re.search(r"\b" + key + r"=([0-9.]+)", line)
            if mm:
                out[key][k] = float(mm.group(1))
        mf = re.search(r"idleFactories=\d+/(\d+)", line)
        if mf:
            out["fac"][k] = float(mf.group(1))
    mapname = None
    sc = os.path.join(game_dir, "script.txt")
    if os.path.exists(sc):
        mm = re.search(r"mapname=([^;]+);", open(sc, encoding="utf-8", errors="replace").read())
        mapname = mm.group(1).strip() if mm else None
    return out, mapname


def nice_step(v):
    """A round tick step (1, 2 or 5 x 10^k) so that four steps cover v."""
    raw = max(v, 1e-9) / 4.0
    e = 10 ** int(np.floor(np.log10(raw)))
    for s in (1, 2, 5, 10):
        if raw <= s * e:
            return max(1.0, s * e) if v >= 4 else s * e
    return 10 * e


def draw_frame(curves, ours, ms, n, mapname, upto, W=1200, H=820):
    img = Image.new("RGBA", (W, H), SURFACE + (255,))
    band = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    db = ImageDraw.Draw(band)
    f_title, f_sub, f_lab, f_small = font(26, True), font(16), font(15, True), font(13)
    d.text((40, 22), "What 1v1 winners have by each minute, and where Anarvā stands", font=f_title, fill=INK)
    d.text((40, 58), f"Median and middle half of {n} winning players (top-player 1v1 replays, runs/replays.db) "
                     f"vs one Anarvā game against BARb hard{(' on ' + mapname) if mapname else ''}", font=f_sub, fill=INK2)
    # legend (always present for >= 2 series)
    lx, ly = 40, 88
    d.rectangle([lx, ly + 6, lx + 26, ly + 14], fill=WIN)
    d.text((lx + 34, ly), "1v1 winners (median; band = middle half)", font=f_small, fill=INK2)
    lx2 = lx + 330
    d.line([lx2, ly + 10, lx2 + 26, ly + 10], fill=ANV, width=3)
    d.text((lx2 + 34, ly), "Anarvā (latest test game)", font=f_small, fill=INK2)
    d.text((W - 160, 22), f"minute {upto}", font=f_title, fill=INK)

    cols, rows = 2, 2
    px0, py0, pw, ph, gx, gy = 40, 128, (W - 120) // 2, 250, 40, 60
    for i, (title, col, key, unit) in enumerate(MEASURES):
        cx = px0 + (i % cols) * (pw + gx)
        cy = py0 + (i // cols) * (ph + gy)
        med, lo, hi = curves[col]
        ourv = ours[key]
        step = nice_step(max([v for v in hi if v is not None] + [v for v in ourv if v is not None] + [1]))
        vmax = step * 4
        ax_l, ax_r, ax_t, ax_b = cx + 56, cx + pw, cy + 28, cy + ph
        d.text((cx, cy), title, font=f_lab, fill=INK)

        def X(m):
            return ax_l + (ax_r - ax_l) * m / MAX_MIN

        def Y(v):
            return ax_b - (ax_b - ax_t) * min(v, vmax) / vmax

        for t in range(5):  # recessive grid + y labels
            v = vmax * t / 4
            y = Y(v)
            d.line([ax_l, y, ax_r, y], fill=GRID, width=1)
            lab = f"{v:,.0f}"
            d.text((cx + 2, y - 8), lab, font=f_small, fill=INK2)
        for m in range(0, MAX_MIN + 1, 4):
            d.text((X(m) - 6, ax_b + 4), str(m), font=f_small, fill=INK2)
        # winners band + median up to the current minute
        pts_band = [(X(m), Y(hi[m])) for m in range(upto + 1) if hi[m] is not None] + \
                   [(X(m), Y(lo[m])) for m in range(upto, -1, -1) if lo[m] is not None]
        if len(pts_band) >= 4:
            db.polygon(pts_band, fill=WIN_BAND)
        pts = [(X(m), Y(med[m])) for m in range(upto + 1) if med[m] is not None]
        if len(pts) >= 2:
            d.line(pts, fill=WIN, width=3, joint="curve")
        pa = [(X(m), Y(ourv[m])) for m in range(upto + 1) if ourv[m] is not None]
        if len(pa) >= 2:
            d.line(pa, fill=ANV, width=3, joint="curve")
        for p, c in ((pts[-1] if pts else None, WIN), (pa[-1] if pa else None, ANV)):
            if p:
                d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=c, outline=SURFACE, width=2)
        # direct labels with the current values (text in ink, mark carries identity)
        wv = med[upto] if med[upto] is not None else None
        av = ourv[upto] if ourv[upto] is not None else None
        tx = ax_r - 230
        d.text((tx, ax_t - 26), (f"winners {wv:,.0f}{unit}" if wv is not None else ""), font=f_small, fill=INK2)
        d.text((tx + 125, ax_t - 26), (f"Anarvā {av:,.0f}{unit}" if av is not None else "Anarvā -"), font=f_small, fill=INK2)
    img = Image.alpha_composite(img, band)
    d = ImageDraw.Draw(img)
    # milestone strip
    sy = H - 40
    sx0, sx1 = 96, W - 40
    d.text((40, sy - 58), "Winners' milestones (median first appearance; games that reach it)", font=f_lab, fill=INK)
    d.line([sx0, sy, sx1, sy], fill=GRID, width=2)
    for m in range(0, MAX_MIN + 1, 2):
        x = sx0 + (sx1 - sx0) * m / MAX_MIN
        d.line([x, sy - 4, x, sy + 4], fill=GRID, width=1)
        d.text((x - 5, sy + 6), str(m), font=f_small, fill=INK2)
    for k, (label, t, cnt) in enumerate(ms):
        if t > MAX_MIN:
            continue
        x = sx0 + (sx1 - sx0) * t / MAX_MIN
        reached = t <= upto
        c = WIN if reached else GRID
        d.ellipse([x - 6, sy - 6, x + 6, sy + 6], fill=c, outline=SURFACE, width=2)
        d.text((x + 10, sy - 24), f"{label} {t:.1f} min ({cnt}/{n})", font=f_small, fill=INK if reached else INK2)
    return img.convert("P", palette=Image.ADAPTIVE, colors=128)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=os.path.join(ROOT, "runs", "cmd_r33b", "g00"))
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "replay_research.gif"))
    a = ap.parse_args()
    curves, ms, n = winners()
    ours, mapname = anarva(a.game)
    frames = [draw_frame(curves, ours, ms, n, mapname, m) for m in range(1, MAX_MIN + 1)]
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    durations = [500] * (len(frames) - 1) + [3500]
    frames[0].save(a.out, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
    frames[-1].convert("RGB").save(a.out.replace(".gif", "_final.png"))
    print("wrote", a.out, len(frames), "frames;", os.path.getsize(a.out) // 1024, "KB")


if __name__ == "__main__":
    main()
