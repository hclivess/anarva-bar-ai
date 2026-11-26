"""Iterative method (owner, 2026-11-26): "monitor every stat - energy, metal, army, damage taken vs dealt. the moment it
swings to the enemy player, you should resign and rework yourself".

Runs one game against BARb (tools/batch.py), reads the harness's true stats for both teams as they are written, and stops
the game the first time a stat favours the enemy in two consecutive samples. Prints the moment, the stat, both sides'
values, and our decision lines from the half minute before it - the thing to fix next.

usage: python tools/swing.py runs/<out> [--map "Canis River v1.4"] [--side0 Armada --side1 Cortex] [--minutes 20]
"""
import argparse
import os
import re
import subprocess
import sys
import time

STAT = re.compile(r"\[HARNESS\] stats f=(\d+) dead=\w+ team=(\d) units=\d+ army_m=(\d+) static_m=(\d+) m_inc=([\d.]+) "
                  r"e_inc=(\d+) m=[\d/]+ e=(\d+)/(\d+) killed_m=(\d+) lost_m=(\d+) dmg_out=(\d+) dmg_in=(\d+)")
# stat -> how ours is compared with theirs (bigger is better for all; damage and kills as a share of the exchange)
STATS = ["metal income", "energy short", "army", "buildings", "army+buildings", "damage share", "kill share"]


def values(t):
    f, team, army, static, minc, einc, ecur, esto, killed, lost, dout, din = t
    return {
        "energy short": 1.0 if int(ecur) * 10 < int(esto) else 0.0,  # bank under a tenth: production waits
        "metal income": float(minc), "energy income": float(einc), "army": int(army), "buildings": int(static),
        "army+buildings": int(army) + int(static),
        "damage share": int(dout) / max(1, int(dout) + int(din)),
        "kill share": int(killed) / max(1, int(killed) + int(lost)),
    }


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--map", default="Canis River v1.4")
    ap.add_argument("--side0", default="Armada")
    ap.add_argument("--side1", default="Cortex")
    ap.add_argument("--minutes", type=float, default=20.0)
    ap.add_argument("--yardstick", choices=["barb", "winners"], default="barb",
                    help="winners: stop when we fall below 0.9 x the median 1v1 winner at that minute (replays.db, the "
                         "Armada bot-lab wins) on metal income, energy income or army - CLAUDE.md: compare with the best "
                         "players, not BARb")
    a = ap.parse_args()
    win = {}
    if a.yardstick == "winners":
        import sqlite3, statistics
        db = sqlite3.connect(os.path.join("runs", "replays.db")); c = db.cursor()
        q = ("select t.replay_id,t.team from teams t where t.won=1 and (select count(*) from teams t2 where t2.replay_id=t.replay_id)=2 "
             "and exists(select 1 from built b where b.replay_id=t.replay_id and b.team=t.team and b.unit='armcom') "
             "and exists(select 1 from built b where b.replay_id=t.replay_id and b.team=t.team and b.unit='armlab' and b.frame<3600)")
        ws = c.execute(q).fetchall()
        for m in range(1, 31):
            r = [c.execute("select m_inc,e_inc,army from stats where replay_id=? and team=? and minute=?", (x, y, m)).fetchone() for x, y in ws]
            r = [v for v in r if v]
            if len(r) >= len(ws) // 2:  # a minute most winners' games still reach
                win[m] = {"metal income": statistics.median(v[0] for v in r), "energy income": statistics.median(v[1] for v in r),
                          "army": statistics.median(v[2] for v in r)}
        print(f"yardstick: median of {len(ws)} Armada bot-lab 1v1 winners, minutes {min(win)}-{max(win)}")
    cmd = [sys.executable, "tools/batch.py", a.out, "--games", "1", "--par", "1", "--me", "Anarva:anarva", "--opp", "BARb:hard",
           "--side0", a.side0, "--side1", a.side1, "--maps", a.map, "--game-minutes", str(a.minutes), "--minutes", str(a.minutes + 15)]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log = os.path.join(a.out, "g00", "infolog.txt")
    seen = 0
    samples = {}  # frame -> {team: values}
    behind = {s: 0 for s in STATS + ["energy income"]}
    swing = None
    while proc.poll() is None and swing is None:
        time.sleep(5)
        if not os.path.exists(log):
            continue
        with open(log, encoding="utf-8", errors="replace") as fh:
            fh.seek(seen)
            chunk = fh.read()
            seen = fh.tell()
        for m in STAT.finditer(chunk):
            fr, team = int(m.group(1)), int(m.group(2))
            samples.setdefault(fr, {})[team] = values(m.groups())
        for fr in sorted(samples):
            pair = samples[fr]
            if 0 not in pair or 1 not in pair or pair.get("done"):
                continue
            pair["done"] = True
            if fr < 30 * 30:  # the first half minute: both sides start equal
                continue
            if win:
                m = fr // 1800
                if fr % 1800 == 0 and m in win:
                    for s2 in ("metal income", "energy income", "army"):
                        ours = pair[0][s2]
                        worse = ours < win[m][s2] * 0.9
                        behind[s2] = behind[s2] + 1 if worse else 0
                        if behind[s2] >= 2 and swing is None:
                            swing = (fr, s2 + " vs winners", ours, win[m][s2])
                continue
            for s in STATS:
                ours, theirs = pair[0][s], pair[1][s]
                if s == "energy short":
                    # energy matters when it runs out: ours short while theirs isn't (more income spent is no gap)
                    worse = pair[0][s] > 0 and pair[1][s] == 0
                elif s in ("damage share", "kill share"):
                    worse = (pair[0]["damage share" if s == "damage share" else "kill share"] < 0.5) and (ours > 0 or theirs > 0)
                    if s == "damage share" and (pair[0]["damage share"] == 0 and pair[1]["damage share"] == 0):
                        worse = False
                else:
                    # a swing is a real gap, not a build finishing a few seconds later: behind by more than a tenth
                    worse = ours < theirs * 0.9
                behind[s] = behind[s] + 1 if worse else 0
                if behind[s] >= 2 and swing is None:
                    swing = (fr, s, ours, theirs)
    if swing is not None:
        # only our own game: the harness's process tree (never a spring the owner is playing)
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            proc.kill()
        fr, s, ours, theirs = swing
        print(f"SWING at {fr // 1800}:{fr // 30 % 60:02d} (frame {fr}): {s} - ours {ours:.2f} vs {'winners median' if win else 'BARb'} {theirs:.2f}")
        last = samples[fr]
        for k in STATS:
            print(f"   {k:15} ours {last[0][k]:9.2f}  BARb {last[1][k]:9.2f}")
        # our decision lines from the half minute before
        txt = open(log, encoding="utf-8", errors="replace").read()
        lines = [l for l in txt.splitlines() if "[ANV" in l]
        sel = []
        for l in lines:
            mm = re.search(r"\]\[f=0*(\d+)\]", l)
            if mm and fr - 900 <= int(mm.group(1)) <= fr:
                sel.append(l.split("> ", 1)[-1][:220])
        print(f"--- our decision lines {fr // 1800}:{(fr - 900) // 30 % 60:02d}-{fr // 1800}:{fr // 30 % 60:02d} ({len(sel)}; last 40):")
        for l in sel[-40:]:
            print("   " + l)
    else:
        print("no swing: the game ended with every stat even or ours")


if __name__ == "__main__":
    main()
