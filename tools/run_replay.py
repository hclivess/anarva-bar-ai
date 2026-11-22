"""Play BAR replays headless with the analyzer widget and keep their logs.

usage: python run_replay.py <out_root> <demo.sdfz> [more.sdfz ...] [--par 4] [--minutes 12]
Each replay gets <out_root>/<demo name>/infolog.txt with [REPLAY] lines.
"""
import argparse
import os
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

BAR_DATA = r"C:\Hry\Beyond-All-Reason\data"
ENGINE_DIR = os.path.join(BAR_DATA, "engine")


def engine_for(demo):
    """Replays need the exact engine they were recorded with; its version ends the file name."""
    m = re.search(r"_(\d{4}\.\d{2}\.\d{2})\.sdfz$", demo)
    exe = os.path.join(ENGINE_DIR, f"recoil_{m.group(1)}", "spring-headless.exe") if m else ""
    return exe if os.path.exists(exe) else None
HERE = os.path.dirname(os.path.abspath(__file__))


def play(args, demo):
    out = os.path.join(args.out, os.path.splitext(os.path.basename(demo))[0])
    if os.path.exists(os.path.join(out, "done")):
        return out
    engine = engine_for(demo)
    if engine is None:
        print("no engine for", demo)
        return out
    os.makedirs(out, exist_ok=True)
    shutil.copytree(os.path.join(HERE, "replay_harness"), out, dirs_exist_ok=True)
    # parallel replays each need their own local server port
    port = 20000 + (abs(hash(demo)) % 20000)
    with open(os.path.join(out, "springsettings.cfg"), "a") as cfg:
        cfg.write(f"HostPortDefault = {port}\nHostPort = {port}\n")
    env = dict(os.environ, SPRING_DATADIR=BAR_DATA)
    with open(os.path.join(out, "stdout.txt"), "w") as log:
        p = subprocess.Popen([engine, "--write-dir", out, os.path.abspath(demo)], env=env, stdout=log,
                             stderr=subprocess.STDOUT, cwd=out)
        try:
            p.wait(timeout=args.minutes * 60)
        except subprocess.TimeoutExpired:
            p.kill()
    open(os.path.join(out, "done"), "w").close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("demos", nargs="+")
    ap.add_argument("--par", type=int, default=4)
    ap.add_argument("--minutes", type=float, default=12.0)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    with ThreadPoolExecutor(args.par) as ex:
        for out in ex.map(lambda d: play(args, d), args.demos):
            print(out, flush=True)


if __name__ == "__main__":
    main()
