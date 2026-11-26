#!/bin/bash
# Builds and runs the terrain field checks, then the cost measurement.
# Needs only a C++17 compiler -- no engine, no CircuitAI checkout, no game (see README.md).
#   bash core/anarva/test/run.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build"
mkdir -p "$OUT"

CXX="${CXX:-g++}"
FLAGS="-std=c++17 -Wall -Wextra -Wno-unused-parameter -I $HERE/stub -I $HERE/.."

echo "== checks =="
$CXX $FLAGS -O1 "$HERE/test_terrain.cpp" -o "$OUT/test_terrain"
"$OUT/test_terrain"

echo
echo "== cost =="
$CXX $FLAGS -O2 "$HERE/bench_terrain.cpp" -o "$OUT/bench_terrain"
"$OUT/bench_terrain"
