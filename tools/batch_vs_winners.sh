#!/bin/bash
# 5 games per change (owner, 2026-11-27): one at a time, swing stop, spectator notes per game
cd /c/Users/cyphernormie/bar
for g in "$@"; do
  # our own headless engine from the last game may still be closing: wait for it; the owner's client is spring.exe
  for w in $(seq 1 60); do tasklist | grep -qi "spring-headless" || break; sleep 5; done
  if tasklist | grep -iE "^spring\.exe" >/dev/null; then echo "BAR client running - stop before swe$g"; exit 1; fi
  rm -rf runs/swe$g
  timeout 4800 python tools/swing.py runs/swe$g --map "Comet Catcher Remake 1.8" --minutes 60 > runs/swe$g.swing.txt 2>&1
  echo "swe$g done: $(head -1 runs/swe$g.swing.txt)"
done
# the batch against the 1v1 winners, gaps ranked (tools/vs_winners.py) - the next change targets the first line
dirs=""; for g in "$@"; do dirs="$dirs runs/swe$g"; done
python tools/vs_winners.py $dirs > runs/vs_winners_$1-${@: -1}.txt 2>&1
tail -10 runs/vs_winners_$1-${@: -1}.txt
