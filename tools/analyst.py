"""Offline analyst (owner's diagram, 2026-11-26: "gradient boost feedback"): which of our measured states predict losing
ground in the next minute.

Reads every game log under runs/ (harness stats for both teams + our [ANV-CHECK] / [ANV-AWARE] lines), builds one row
per game-minute of OUR side's state, and as the label the change of our share of the total value (army + buildings)
over the next minute. A gradient-boosted model is fitted (cross-validated) and its permutation importance ranks the
features: where to work next. It is a diagnostic for us, never loaded by the AI (CLAUDE.md: no fitted weights or
replay/log-derived tables in decisions).

usage: python tools/analyst.py [--runs runs] [--top 15]
"""
import argparse
import glob
import os
import re
import sys

STAT = re.compile(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d) units=(\d+) army_m=(\d+) static_m=(\d+) m_inc=([\d.]+) "
                  r"e_inc=(\d+) m=(\d+)/(\d+) e=(\d+)/(\d+) killed_m=(\d+) lost_m=(\d+) dmg_out=(\d+) dmg_in=(\d+)")
TECH = re.compile(r"\[HARNESS\] tech f=(\d+) team=0 lab=(\d+)/\d+/\d+ mex=(\d+)/\d+ conv=\d+/\d+ fus=\d+ nano=(\d+) con=(\d+)")
AWARE = re.compile(r"\[ANV-AWARE\] t=(\d+)s army (\d+)(?: \((\d+) metal, strength (\d+)\) at \(-?\d+,-?\d+\) spread (\d+) forward ([\d.]+))?"
                   r" \| ops (\d+) \[[^\]]*\] pickets (\d+) \| commander (\d+) from base \| spots (\d+) ours (\d+) theirs seen (\d+) other"
                   r" \| seen last minute ([\d.]+) of the map, radars (\d+) \| enemy armed (\d+) strength (\d+) groups (\d+)")


def rows_of(log):
    t = open(log, encoding="utf-8", errors="replace").read()
    st = {}
    for m in STAT.finditer(t):
        f, team = int(m.group(1)), int(m.group(2))
        if f % 1800:
            continue
        g = [float(x) for x in m.groups()]
        st.setdefault(f // 1800, {})[team] = {
            "units": g[2], "army": g[3], "static": g[4], "m_inc": g[5], "e_inc": g[6], "m_bank": g[7], "m_sto": g[8],
            "e_bank": g[9], "e_sto": g[10], "killed": g[11], "lost": g[12], "dmg_out": g[13], "dmg_in": g[14]}
    tech = {}
    for m in TECH.finditer(t):
        f = int(m.group(1))
        if f % 1800 == 0:
            tech[f // 1800] = {"labs": float(m.group(2)), "mex": float(m.group(3)), "nanos": float(m.group(4)), "cons": float(m.group(5))}
    aware = {}
    for m in AWARE.finditer(t):
        sec = int(m.group(1))
        g = m.groups()
        aware[sec // 60] = {
            "army_spread": float(g[4] or 0), "army_forward": float(g[5] or 0), "ops": float(g[6]), "pickets": float(g[7]),
            "comm_from_base": float(g[8]), "spots_ours": float(g[10]), "spots_theirs_seen": float(g[11]),
            "seen_share": float(g[12]), "radars": float(g[13]), "enemy_armed_seen": float(g[14]), "enemy_strength_seen": float(g[15]),
            "enemy_groups": float(g[16])}
    rows = []
    for mi in sorted(st):
        if mi + 1 not in st or 0 not in st[mi] or 1 not in st[mi] or 0 not in st[mi + 1] or 1 not in st[mi + 1]:
            continue
        a, b = st[mi][0], st[mi][1]
        a2, b2 = st[mi + 1][0], st[mi + 1][1]
        share = (a["army"] + a["static"]) / max(1.0, a["army"] + a["static"] + b["army"] + b["static"])
        share2 = (a2["army"] + a2["static"]) / max(1.0, a2["army"] + a2["static"] + b2["army"] + b2["static"])
        x = {"minute": mi, "m_inc": a["m_inc"], "e_inc": a["e_inc"], "m_bank_share": a["m_bank"] / max(1.0, a["m_sto"]),
             "e_bank_share": a["e_bank"] / max(1.0, a["e_sto"]), "army": a["army"], "static": a["static"],
             "army_share_of_ours": a["army"] / max(1.0, a["army"] + a["static"]), "share": share}
        x.update(tech.get(mi, {}))
        x.update(aware.get(mi, {}))
        rows.append((x, share2 - share))
    return rows


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", default="runs")
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()
    data = []
    games = 0
    for log in glob.glob(os.path.join(a.runs, "*", "g00", "infolog.txt")):
        r = rows_of(log)
        if r:
            games += 1
            data += [(x, d, games) for x, d in r]
    if len(data) < 30:
        print(f"only {len(data)} game-minutes in {games} games: not enough to fit")
        return
    import numpy as np
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.inspection import permutation_importance
    from sklearn.model_selection import cross_val_score
    from sklearn.model_selection import GroupKFold
    names = sorted({k for x, _, _ in data for k in x})
    # a feature most game-minutes have (newer log lines exist only in recent games: fitted on a few, they mislead)
    names = [k for k in names if sum(1 for x, _, _ in data if k in x) >= 0.8 * len(data)]
    X = np.array([[x.get(k, np.nan) for k in names] for x, _, _ in data])
    y = np.array([d for _, d, _ in data])
    groups = np.array([g for _, _, g in data])
    model = HistGradientBoostingRegressor(random_state=0)  # a fixed seed: the same logs give the same ranking
    # folds by game: minutes of one game on both sides of a fold would score the model on what it memorised
    cv = cross_val_score(model, X, y, cv=GroupKFold(n_splits=5), groups=groups, scoring="r2")
    model.fit(X, y)
    imp = permutation_importance(model, X, y, n_repeats=10, random_state=0)
    print(f"{len(data)} game-minutes from {games} games; label: change of our share of army+buildings over the next minute")
    print(f"cross-validated R2 {cv.mean():.2f} (+/- {cv.std():.2f}) - below 0 the model explains nothing yet: read the ranking as a lead only")
    order = np.argsort(-imp.importances_mean)
    print("feature                 importance   mean (minutes we gained / lost ground)")
    gain = y > 0
    print("features kept (in >= 80% of game-minutes):", ", ".join(names))
    for i in order[:a.top]:
        col = X[:, i]
        g_mean = np.nanmean(col[gain]) if gain.any() else float("nan")
        l_mean = np.nanmean(col[~gain]) if (~gain).any() else float("nan")
        print(f"  {names[i]:22} {imp.importances_mean[i]:9.4f}   {g_mean:9.2f} / {l_mean:9.2f}")


if __name__ == "__main__":
    main()
