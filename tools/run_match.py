"""Run a headless AI-vs-AI BAR match and keep its infolog.

usage: python run_match.py <out_dir> [--ai0 Anarva:anarva] [--ai1 BARb:hard]
                           [--map "Avalanche 3.4"] [--minutes 20] [--speed 0]
Each AI is "<shortName>:<profile>". Team 0 starts top-left, team 1 bottom-right.
"""
import argparse
import os
import shutil
import subprocess
import time

BAR_DATA = r"C:\Hry\Beyond-All-Reason\data"
ENGINE = os.path.join(BAR_DATA, "engine", "recoil_2026.09.03", "spring-headless.exe")
GAME = "byar:test"


def ai_block(idx, spec, ally=None):
    short, profile = spec.split(":")
    opts = f"profile={profile};"
    if short == "BARb":
        opts += "game_config=1;"
    return f"""
[ai{idx}]
{{
[options]
{{
{opts}
}}
shortname={short};
version=stable;
team={idx};
host=0;
name={short}{idx};
}}
[team{idx}]
{{
allyteam={idx if ally is None else ally};
teamleader=0;
side=Random;
handicap=0;
}}
"""


def replay_boxes(map_name):
    """The start boxes top players had on this map in 1v1 (the most frequent pair in the replay library), as
    startrect fractions; None when no 1v1 replay of the map exists. A comparison with players holds only under their
    conditions (owner, 2026-11-25)."""
    import gzip, re, sqlite3, collections
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    db_path = os.path.join(root, "runs", "replays.db")
    if not os.path.exists(db_path):
        return None
    seen = collections.Counter()
    for (f,) in sqlite3.connect(db_path).execute("select file from replays where format='1v1' and map=?", (map_name,)):
        path = os.path.join(root, "ref", "lib", f)
        if not os.path.exists(path):
            continue
        raw = gzip.open(path).read(300000)
        i = raw.find(b"[game]")
        st = raw[i:i + 80000].decode("latin-1")
        boxes = []
        for a, body in sorted(re.findall(r"\[allyteam(\d+)\]\s*\{([^}]*)\}", st)):
            g = dict(re.findall(r"startrect(left|right|top|bottom)=([\d.]+)", body))
            if len(g) == 4:
                boxes.append(tuple(g[k] for k in ("left", "right", "top", "bottom")))
        if len(boxes) == 2:
            seen[tuple(boxes)] += 1
    return seen.most_common(1)[0][0] if seen else None


def make_script(args):
    boxes = replay_boxes(args.map) or (("0", "0.25", "0", "0.25"), ("0.75", "1", "0.75", "1"))
    b0, b1 = boxes
    return f"""[game]
{{
[allyteam0]
{{
startrectleft={b0[0]}; startrectright={b0[1]}; startrecttop={b0[2]}; startrectbottom={b0[3]}; numallies=0;
}}
[allyteam1]
{{
startrectleft={b1[0]}; startrectright={b1[1]}; startrecttop={b1[2]}; startrectbottom={b1[3]}; numallies=0;
}}
{ai_block(0, args.ai0)}
{"".join(ai_block(1 + k, args.ai1, 1) for k in range(args.n1))}
[player0]
{{
name=Observer;
spectator=1;
team=0;
}}
[modoptions]
{{
deathmode=com;
draft_mode=disabled;
}}
ishost=1;
hostip=127.0.0.1;
hostport=0;
numplayers=1;
numusers={2 + args.n1};
startpostype={args.startpostype};
gametype={GAME};
mapname={args.map};
myplayername=Observer;
gamestartdelay=0;
nohelperais=0;
}}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--ai0", default="Anarva:anarva")
    ap.add_argument("--ai1", default="BARb:hard")
    ap.add_argument("--map", default="Avalanche 3.4")
    ap.add_argument("--n1", type=int, default=1, help="number of ai1 copies (all allied)")
    ap.add_argument("--minutes", type=float, default=20.0, help="wall-clock limit")
    ap.add_argument("--game-minutes", type=float, default=30.0, help="game-time cap (harness widget)")
    ap.add_argument("--startpostype", type=int, default=2, help="0 fixed, 2 choose in game (every 1v1 replay)")
    args = ap.parse_args()
    args.out = os.path.abspath(args.out)  # the engine runs inside out/, so a relative script path breaks

    os.makedirs(args.out, exist_ok=True)
    harness = os.path.join(os.path.dirname(os.path.abspath(__file__)), "harness")
    shutil.copytree(harness, args.out, dirs_exist_ok=True)
    with open(os.path.join(args.out, "springsettings.cfg"), "a") as f:
        f.write("HarnessMaxFrames = %d\n" % int(args.game_minutes * 60 * 30))
    script = os.path.join(args.out, "script.txt")
    with open(script, "w") as f:
        f.write(make_script(args))
    env = dict(os.environ, SPRING_DATADIR=BAR_DATA)
    log = open(os.path.join(args.out, "stdout.txt"), "w")
    t0 = time.time()
    p = subprocess.Popen([ENGINE, "--write-dir", os.path.abspath(args.out), script],
                         env=env, stdout=log, stderr=subprocess.STDOUT, cwd=args.out)
    try:
        p.wait(timeout=args.minutes * 60)
    except subprocess.TimeoutExpired:
        p.kill()
        print("timeout, killed")
    print(f"exit={p.returncode} wall={time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
