#!/usr/bin/env python3
"""
Win-probability model from the 1v1 replays (measurement only - the AI never reads it).

For each minute 2..16 a logistic regression predicts whether a player wins from their own state that minute:
extractors, metal income, energy income, army value, factories, constructors (log-scaled). The regularisation is
chosen by cross-validation; the held-out AUC says how far each minute's model can be trusted.

    python tools/winprob.py fit            fit and save runs/winprob.json, print the held-out AUC per minute
    python tools/winprob.py gaps STATE     (used by check_game.py) win chance and what each gap costs

check_game.py uses it to rank our gaps by the win chance they cost: for each feature, how much P(win) would rise
if that one value were the winners' median at that minute.
"""
import json
import math
import os
import sqlite3
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "runs", "replays.db")
MODEL = os.path.join(ROOT, "runs", "winprob.json")
FEATURES = ["mex", "m_inc", "e_inc", "army", "facs", "builders"]
# relative model: features both the replays and our test harness record for both players every minute
REL = ["m_inc", "e_inc", "army"]
REL_MODEL = os.path.join(ROOT, "runs", "winprob_rel.json")
LABELS = {"mex": "extractors", "m_inc": "metal income", "e_inc": "energy income", "army": "army", "facs": "factories",
          "builders": "constructors"}
MINUTES = range(2, 17)


def load():
    db = sqlite3.connect(DB)
    won = {(r, t): w for r, t, w in db.execute(
        "select t.replay_id, t.team, t.won from teams t join replays r on r.id=t.replay_id "
        "where r.format='1v1' and r.status='done'")}
    rows = {}
    for rid, team, minute, *vals in db.execute(
            "select s.replay_id, s.team, s.minute, " + ", ".join("s." + f for f in FEATURES) +
            " from stats s join replays r on r.id=s.replay_id where r.format='1v1' and r.status='done'"):
        w = won.get((rid, team))
        if w in (0, 1) and minute in MINUTES and all(v is not None for v in vals):
            rows.setdefault(minute, []).append((rid, [float(v) for v in vals], w))
    return rows


def transform(v):
    return [math.log1p(max(0.0, x)) for x in v]


def fit():
    from sklearn.linear_model import LogisticRegressionCV
    from sklearn.model_selection import GroupKFold, cross_val_score
    from sklearn.linear_model import LogisticRegression
    rows = load()
    out = {}
    print("minute  games  held-out AUC   strongest features")
    for m in MINUTES:
        data = rows.get(m, [])
        if len(data) < 40:
            continue
        X = np.array([transform(v) for _, v, _ in data])
        y = np.array([w for _, _, w in data])
        groups = np.array([g for g, _, _ in data])  # both players of a game stay in the same fold
        mu, sd = X.mean(0), X.std(0) + 1e-9
        Z = (X - mu) / sd
        cv = GroupKFold(n_splits=5)
        clf = LogisticRegressionCV(Cs=10, cv=list(cv.split(Z, y, groups)), scoring="roc_auc", max_iter=2000).fit(Z, y)
        C = float(clf.C_[0])
        auc = cross_val_score(LogisticRegression(C=C, max_iter=2000), Z, y, cv=list(cv.split(Z, y, groups)), scoring="roc_auc").mean()
        winners = np.array([v for _, v, w in data if w == 1])
        out[str(m)] = {"mu": mu.tolist(), "sd": sd.tolist(), "coef": clf.coef_[0].tolist(), "b": float(clf.intercept_[0]),
                       "C": C, "auc": float(auc), "n": int(len(data)),
                       "winner_median": np.median(winners, axis=0).tolist()}
        order = np.argsort(-np.abs(clf.coef_[0]))[:3]
        print(f"{m:6d}  {len(data):5d}  {auc:12.2f}   " + ", ".join(f"{LABELS[FEATURES[i]]} {clf.coef_[0][i]:+.2f}" for i in order))
    os.makedirs(os.path.dirname(MODEL), exist_ok=True)
    json.dump({"features": FEATURES, "minutes": out}, open(MODEL, "w"), indent=1)
    print("saved", MODEL)


def prob(model, raw):
    z = (np.array(transform(raw)) - np.array(model["mu"])) / np.array(model["sd"])
    return 1.0 / (1.0 + math.exp(-(float(np.dot(model["coef"], z)) + model["b"])))


def gaps(minute, raw):
    """Win chance at this minute and, per feature, the rise if it matched the winners' median."""
    if not os.path.exists(MODEL):
        return None
    m = json.load(open(MODEL))["minutes"].get(str(minute))
    if m is None:
        return None
    p = prob(m, raw)
    costs = []
    for i, f in enumerate(FEATURES):
        alt = list(raw)
        alt[i] = max(raw[i], m["winner_median"][i])
        costs.append((prob(m, alt) - p, f, raw[i], m["winner_median"][i]))
    costs.sort(reverse=True)
    return p, m["auc"], costs


def fit_relative():
    """Win chance from the difference to the opponent (log-scaled), per minute; AUC 0.73-0.87 from minute 3 with all six
    features - here the three the harness also logs for BARb."""
    from sklearn.linear_model import LogisticRegressionCV, LogisticRegression
    from sklearn.model_selection import GroupKFold, cross_val_score
    db = sqlite3.connect(DB)
    won = {(r, t): w for r, t, w in db.execute(
        "select t.replay_id, t.team, t.won from teams t join replays r on r.id=t.replay_id where r.format='1v1' and r.status='done'")}
    st = {}
    for rid, team, m, *v in db.execute("select s.replay_id, s.team, s.minute, " + ", ".join("s." + f for f in REL) +
                                         " from stats s join replays r on r.id=s.replay_id where r.format='1v1' and r.status='done'"):
        if all(x is not None for x in v):
            st.setdefault((rid, m), {})[team] = transform([float(x) for x in v])
    out = {}
    print("minute  games  held-out AUC (relative: " + ", ".join(REL) + ")")
    for m in MINUTES:
        X, y, g = [], [], []
        for (rid, mm), teams in st.items():
            if mm != m or len(teams) != 2:
                continue
            a, b = list(teams.keys())
            if won.get((rid, a)) not in (0, 1):
                continue
            for p_, q_ in ((a, b), (b, a)):
                X.append(np.array(teams[p_]) - np.array(teams[q_])); y.append(won[(rid, p_)]); g.append(rid)
        if len(X) < 40 or len(set(y)) < 2:
            continue
        X, y, g = np.array(X), np.array(y), np.array(g)
        cv = list(GroupKFold(n_splits=5).split(X, y, g))
        clf = LogisticRegressionCV(Cs=10, cv=cv, scoring="roc_auc", max_iter=2000).fit(X, y)
        auc = cross_val_score(LogisticRegression(C=clf.C_[0], max_iter=2000), X, y, cv=cv, scoring="roc_auc").mean()
        # informative unless cross-validation fell back to the strongest regularisation on its grid (the prior)
        informative = bool(clf.C_[0] > min(clf.Cs_))
        out[str(m)] = {"coef": clf.coef_[0].tolist(), "b": float(clf.intercept_[0]), "auc": float(auc), "n": int(len(X) // 2),
                       "C": float(clf.C_[0]), "informative": informative}
        print(f"{m:6d}  {len(X) // 2:5d}  {auc:12.2f}   " + ", ".join(f"{f} {c:+.2f}" for f, c in zip(REL, clf.coef_[0])))
    json.dump({"features": REL, "minutes": out}, open(REL_MODEL, "w"), indent=1)
    print("saved", REL_MODEL)


def relative_gaps(minute, ours, theirs):
    """Our win chance against this opponent at this minute, and per feature the rise if we matched them on it."""
    if not os.path.exists(REL_MODEL):
        return None
    m = json.load(open(REL_MODEL))["minutes"].get(str(minute))
    if m is None:
        return None

    def p(a):
        d = np.array(transform(a)) - np.array(transform(theirs))
        return 1.0 / (1.0 + math.exp(-(float(np.dot(m["coef"], d)) + m["b"])))
    base = p(ours)
    costs = []
    for i, f in enumerate(REL):
        alt = list(ours)
        alt[i] = max(ours[i], theirs[i])
        costs.append((p(alt) - base, f, ours[i], theirs[i]))
    costs.sort(reverse=True)
    return base, m["auc"], costs


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "fit":
        fit()
        fit_relative()
    else:
        print(__doc__)


def plot(game_dir, out=None):
    """docs/winprob.png: held-out AUC by minute (own state vs relative to the opponent), and one game's win chance."""
    from PIL import Image, ImageDraw, ImageFont
    import re as _re
    SURFACE, INK, INK2, GRID = (252, 252, 251), (11, 11, 11), (82, 81, 78), (229, 228, 223)
    BLUE, ORANGE = (42, 120, 214), (235, 104, 52)

    def font(size, bold=False):
        for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), ("arialbd.ttf" if bold else "arial.ttf"), "DejaVuSans.ttf"):
            try:
                return ImageFont.truetype(name, size)
            except OSError:
                continue
        return ImageFont.load_default()
    own = {int(k): v["auc"] for k, v in json.load(open(MODEL))["minutes"].items()}
    rel = {int(k): v["auc"] for k, v in json.load(open(REL_MODEL))["minutes"].items()}
    relm = json.load(open(REL_MODEL))["minutes"]
    # the game's win chance by minute
    log = open(os.path.join(game_dir, "infolog.txt"), encoding="utf-8", errors="replace").read()
    me = None
    sc = os.path.join(game_dir, "script.txt")
    if os.path.exists(sc):
        body = open(sc, encoding="utf-8", errors="replace").read()
        parts = _re.split(r"(?=\[(?:ai|team|player|allyteam)\d+\])", body)
        for part in parts:
            if part.startswith("[ai") and _re.search(r"shortname=Anarva", part, _re.I):
                t = _re.search(r"team=(\d+);", part)
                me = int(t.group(1)) if t else None
    per = {}
    for m in _re.finditer(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d+) [^\n]*?army_m=([\d.]+)[^\n]*?m_inc=([\d.]+) e_inc=([\d.]+)", log):
        f, team = int(m.group(1)), int(m.group(2))
        if f % 1800 == 0:
            per.setdefault(f // 1800, {})[team] = [float(m.group(4)), float(m.group(5)), float(m.group(3))]
    game = []
    for minute in sorted(per):
        t = per[minute]
        if me in t and len(t) == 2 and str(minute) in relm and relm[str(minute)].get("informative", True):
            other = [k for k in t if k != me][0]
            g = relative_gaps(minute, t[me], t[other])
            if g:
                game.append((minute, g[0], g[2][0]))
    W, H = 1200, 470
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    d.text((40, 22), "A win-probability model from the replays (measurement only; the AI never reads it)", font=font(24, True), fill=INK)
    d.text((40, 56), "Logistic regression per minute on 107 top-player 1v1 games, regularisation by cross-validation. "
                     "AUC 0.5 = a coin flip, 1.0 = always right.", font=font(15), fill=INK2)
    pw, ph = 520, 300
    # left: AUC by minute
    cx, cy = 40, 110
    ax_l, ax_r, ax_t, ax_b = cx + 44, cx + pw, cy + 30, cy + ph
    d.text((cx, cy), "How well it predicts the winner (held-out AUC)", font=font(15, True), fill=INK)
    for t in range(6):
        v = 0.5 + 0.1 * t
        y = ax_b - (ax_b - ax_t) * (v - 0.5) / 0.5
        d.line([ax_l, y, ax_r, y], fill=GRID, width=1)
        d.text((cx, y - 8), f"{v:.1f}", font=font(12), fill=INK2)
    for mm in range(2, 17, 2):
        d.text((ax_l + (ax_r - ax_l) * (mm - 2) / 14 - 5, ax_b + 4), str(mm), font=font(12), fill=INK2)
    for series, col in ((own, ORANGE), (rel, BLUE)):
        pts = [(ax_l + (ax_r - ax_l) * (mm - 2) / 14, ax_b - (ax_b - ax_t) * (series[mm] - 0.5) / 0.5) for mm in sorted(series)]
        d.line(pts, fill=col, width=3, joint="curve")
    d.rectangle([ax_l, ax_b + 26, ax_l + 22, ax_b + 33], fill=BLUE)
    d.text((ax_l + 28, ax_b + 21), "relative to the opponent (income, energy, army)", font=font(12), fill=INK2)
    d.rectangle([ax_l + 300, ax_b + 26, ax_l + 322, ax_b + 33], fill=ORANGE)
    d.text((ax_l + 328, ax_b + 21), "own state only", font=font(12), fill=INK2)
    # right: one game's win chance
    cx = 40 + pw + 80
    ax_l, ax_r = cx + 44, cx + pw
    d.text((cx, cy), "Anarvā vs BARb hard, one game: win chance by minute", font=font(15, True), fill=INK)
    for t in range(5):
        y = ax_b - (ax_b - ax_t) * t / 4
        d.line([ax_l, y, ax_r, y], fill=GRID, width=1)
        d.text((cx, y - 8), f"{25 * t}%", font=font(12), fill=INK2)
    for mm in range(2, 17, 2):
        d.text((ax_l + (ax_r - ax_l) * (mm - 2) / 14 - 5, ax_b + 4), str(mm), font=font(12), fill=INK2)
    if game:
        pts = [(ax_l + (ax_r - ax_l) * (mm - 2) / 14, ax_b - (ax_b - ax_t) * p_) for mm, p_, _ in game if 2 <= mm <= 16]
        if len(pts) >= 2:
            d.line(pts, fill=BLUE, width=3)
        for (mm, p_, (dp, f, ours, theirs)), (x, y) in zip([g for g in game if 2 <= g[0] <= 16], pts):
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=BLUE, outline=SURFACE, width=2)
        names = {"m_inc": "metal income", "e_inc": "energy", "army": "army"}
        first = next((g for g in game if g[2][0] > 0.1), None)
        if first:
            mm, p_, (dp, f, ours, theirs) = first
            x = ax_l + (ax_r - ax_l) * (mm - 2) / 14
            y = ax_b - (ax_b - ax_t) * p_
            d.text((x + 8, y - 30), f"min {mm}: {names[f]} {ours:,.0f} vs {theirs:,.0f}", font=font(12), fill=INK)
            d.text((x + 8, y - 16), f"costs {dp * 100:.0f} points of win chance", font=font(12), fill=INK2)
    img.save(out or os.path.join(ROOT, "docs", "winprob.png"))
    print("wrote docs/winprob.png")


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "plot":
    plot(sys.argv[2])
