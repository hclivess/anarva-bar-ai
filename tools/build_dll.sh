#!/bin/bash
# Builds Anarva's SkirmishAI.dll: BARb's CircuitAI core (barbarian @ f4a6ca3, the commit the engine pins) + core/circuitai.patch.
# Windows: run inside MSYS2 MINGW64 (pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja gawk).
# Output: ref/build/AI/Skirmish/BARb/data/SkirmishAI.dll  -> tools/install.ps1 -Dll <that path>
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/ref"; mkdir -p "$REF"; cd "$REF"
[ -d recoil ] || git clone --depth 1 --branch 2026.09.03 https://github.com/beyond-all-reason/RecoilEngine.git recoil
[ -d mingwlibs64 ] || git clone --depth 1 https://github.com/beyond-all-reason/mingwlibs64.git
if [ ! -d circuitai ]; then
  git clone https://github.com/rlcevg/CircuitAI.git circuitai
  (cd circuitai && git checkout -q f4a6ca3 && git checkout -q -b anarva && git apply "$ROOT/core/circuitai.patch")
fi
(cd recoil && git submodule update --init --recursive --depth 1 rts/lib tools/pr-downloader)
if [ ! -e recoil/AI/Skirmish/BARb/CMakeLists.txt ]; then
  rmdir recoil/AI/Skirmish/BARb 2>/dev/null || true
  cmd //c mklink //J "$(cygpath -w recoil/AI/Skirmish/BARb)" "$(cygpath -w circuitai)" 2>/dev/null || ln -s "$REF/circuitai" recoil/AI/Skirmish/BARb
fi
[ -f build/build.ninja ] || cmake -S recoil -B build -G Ninja -Wno-dev \
  -DCMAKE_IGNORE_PREFIX_PATH='C:/msys64/mingw64;/mingw64' -DMINGWLIBS="$REF/mingwlibs64" \
  -DAI_TYPES=NATIVE -DAI_EXCLUDE_REGEX='^(CppTestAI|CircuitAI|NullAI)$' -DBUILD_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=RELWITHDEBINFO -DCMAKE_CXX_FLAGS_INIT='-static-libstdc++ -static-libgcc' -DCMAKE_C_FLAGS_INIT='-static-libgcc' \
  -DCMAKE_CXX_FLAGS_RELWITHDEBINFO='-O3 -DNDEBUG' -DCMAKE_C_FLAGS_RELWITHDEBINFO='-O3 -DNDEBUG'
ninja -C build BARb
strip -o build/SkirmishAI.dll build/AI/Skirmish/BARb/data/SkirmishAI.dll
echo "built $REF/build/SkirmishAI.dll"
