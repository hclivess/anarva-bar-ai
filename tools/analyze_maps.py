"""Pre-match map analysis, like a player studying the map: reads BAR map archives (.sd7) and
computes, per map: size, start positions, extractor spots (from the metal map), base-to-base path
distance and the narrowest corridor on it (chokes), water share and geo vents.
Writes a JSON report and an AngelScript facts file the AI loads at game start.

usage: python analyze_maps.py <maps_dir> <out.json> <out.as> [map file names...]
       python analyze_maps.py --wind <maps_dir> <maps.json>   (adds the wind range to an existing report)
Requires py7zr (dev only).
"""
import heapq
import io
import json
import math
import os
import re
import struct
import sys

import py7zr

SQUARE = 8           # elmos per heightmap square
CELL = 4             # analysis cell = 4 heightmap squares = 32 elmos
MAX_SLOPE = 0.41     # bot movedef max slope (vbot/kbot), a game fact
MAX_WADE = 22.0      # bot movedef max water depth (elmos), a game fact


def read_archive(path):
    import tempfile
    with py7zr.SevenZipFile(path, "r") as z:
        names = z.getnames()
    smf = next((n for n in names if n.lower().endswith(".smf")), None)
    info = next((n for n in names if n.lower() == "mapinfo.lua"), None) or next((n for n in names if n.lower().endswith("/mapinfo.lua")), None)
    want = [n for n in (smf, info) if n]
    out = {}
    with tempfile.TemporaryDirectory() as tmp:
        with py7zr.SevenZipFile(path, "r") as z:
            z.extract(path=tmp, targets=want)
        for n in want:
            with open(os.path.join(tmp, *n.split("/")), "rb") as f:
                out[n] = f.read()
    return out, smf, info


def parse_smf(raw, override=None):
    (magic, ver, mapid, mapx, mapy, sq, tex, tile, minh, maxh, hptr, typeptr, tilesptr, minimapptr,
     metalptr, featptr) = struct.unpack_from("<16siiiiiiiffiiiiii", raw, 0)
    w, h = mapx + 1, mapy + 1
    heights = struct.unpack_from("<%dH" % (w * h), raw, hptr)
    if override:  # mapinfo.lua smf = { minheight, maxheight } replaces the header values
        minh, maxh = override.get("min", minh), override.get("max", maxh)
    scale = (maxh - minh) / 65536.0
    hm = [minh + v * scale for v in heights]
    mw, mh = mapx // 2, mapy // 2
    metal = raw[metalptr:metalptr + mw * mh]
    return {"mapx": mapx, "mapy": mapy, "hm": hm, "hw": w, "hh": h, "metal": metal, "mw": mw, "mh": mh}


def parse_starts(info_text):
    starts = []
    for m in re.finditer(r"startpos\s*=\s*\{\s*x\s*=\s*([\d.]+)\s*,\s*z\s*=\s*([\d.]+)", info_text, re.I):
        starts.append((float(m.group(1)), float(m.group(2))))
    return starts


def mex_spots(smf):
    """Connected components of metal-map pixels -> spot centres (elmos) and richness."""
    mw, mh, metal = smf["mw"], smf["mh"], smf["metal"]
    seen = bytearray(mw * mh)
    spots = []
    for i in range(mw * mh):
        if metal[i] == 0 or seen[i]:
            continue
        stack, pix, tot = [i], [], 0
        seen[i] = 1
        while stack:
            j = stack.pop()
            pix.append(j)
            tot += metal[j]
            x, z = j % mw, j // mw
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, nz = x + dx, z + dz
                if 0 <= nx < mw and 0 <= nz < mh:
                    k = nz * mw + nx
                    if metal[k] and not seen[k]:
                        seen[k] = 1
                        stack.append(k)
        if len(pix) >= 3:
            cx = sum(p % mw for p in pix) / len(pix) * 16 + 8   # metal map pixel = 16 elmos
            cz = sum(p // mw for p in pix) / len(pix) * 16 + 8
            spots.append((cx, cz, tot))
    return spots


def passability(smf):
    """Cell grid: passable for bots (slope <= MAX_SLOPE and above water)."""
    hw, hh, hm = smf["hw"], smf["hh"], smf["hm"]
    gw, gh = (hw - 1) // CELL, (hh - 1) // CELL
    grid = bytearray(gw * gh)
    water = 0
    for gz in range(gh):
        for gx in range(gw):
            x0, z0 = gx * CELL, gz * CELL
            hs = [hm[(z0 + dz) * hw + (x0 + dx)] for dz in (0, CELL) for dx in (0, CELL)]
            # steepest step between adjacent height samples inside the cell (closer to the engine's slope)
            slope = 0.0
            for dz in range(CELL):
                for dx in range(CELL):
                    a = hm[(z0 + dz) * hw + (x0 + dx)]
                    slope = max(slope, abs(hm[(z0 + dz) * hw + (x0 + dx + 1)] - a), abs(hm[(z0 + dz + 1) * hw + (x0 + dx)] - a))
            slope /= SQUARE
            water += sum(1 for v in hs if v < 0) >= 3
            deep = sum(hs) / 4.0 < -MAX_WADE  # bots wade shallow water
            grid[gz * gw + gx] = 1 if (slope <= MAX_SLOPE and not deep) else 0
    return grid, gw, gh, water / float(gw * gh)


def path_and_choke(grid, gw, gh, a, b):
    """Shortest passable path a->b (cells) and the narrowest perpendicular width along it."""
    def cell(p):
        return (min(gw - 1, max(0, int(p[0] / (CELL * SQUARE)))), min(gh - 1, max(0, int(p[1] / (CELL * SQUARE)))))
    s, t = cell(a), cell(b)
    dist = {s: 0.0}
    prev = {}
    pq = [(0.0, s)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t:
            break
        if d > dist.get(u, 1e18):
            continue
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx == dz == 0:
                    continue
                v = (u[0] + dx, u[1] + dz)
                if not (0 <= v[0] < gw and 0 <= v[1] < gh) or not grid[v[1] * gw + v[0]]:
                    continue
                nd = d + math.hypot(dx, dz)
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
    if t not in dist:
        return None, None, None
    path, u = [], t
    while u != s:
        path.append(u)
        u = prev[u]
    path.reverse()
    # width across the path direction, sampled every few cells, ignoring the base areas themselves
    widths, wpos = [], []
    for i in range(4, len(path) - 4, 2):
        (x0, z0), (x1, z1) = path[i - 2], path[i + 2]
        dx, dz = x1 - x0, z1 - z0
        n = math.hypot(dx, dz) or 1.0
        px, pz = -dz / n, dx / n
        w = 1
        for sgn in (1, -1):
            k = 1
            while True:
                cx, cz = int(round(path[i][0] + sgn * px * k)), int(round(path[i][1] + sgn * pz * k))
                if not (0 <= cx < gw and 0 <= cz < gh) or not grid[cz * gw + cx] or k > 200:
                    break
                k += 1
                w += 1
        widths.append(w)
        wpos.append(i)
    # a choke is a narrow stretch, not a single bump: narrowest 5-sample moving median along the path
    if len(widths) >= 5:
        smooth = [sorted(widths[i - 2:i + 3])[2] for i in range(2, len(widths) - 2)]
        spos = wpos[2:len(widths) - 2]
    else:
        smooth, spos = widths, wpos
    choke = (min(smooth) * CELL * SQUARE) if smooth else None
    # per side: the narrowest point on that side's half of the path (skip the outer 15%: the bases)
    sides = []
    n = len(path)
    for lo, hi in ((0.15, 0.5), (0.5, 0.85)):
        best = None
        for w, i in zip(smooth, spos):
            if lo * n <= i < hi * n and (best is None or w < best[0]):
                best = (w, i)
        sides.append((path[best[1]], best[0] * CELL * SQUARE) if best else None)
    return dist[t] * CELL * SQUARE, choke, sides


def cell_height(hm, hw, gx, gz):
    x0, z0 = gx * CELL + CELL // 2, gz * CELL + CELL // 2
    return hm[z0 * hw + x0]


def high_ground(grid, gw, gh, hm, hw, choke_cell, own_start):
    """Highest passable cell overlooking the choke from our side: within ~500 elmos of the choke,
    no farther from our start than the choke itself. Returns (x, z, height gain) in elmos."""
    cx, cz = choke_cell
    base_h = cell_height(hm, hw, cx, cz)
    own = (own_start[0] / (CELL * SQUARE), own_start[1] / (CELL * SQUARE))
    dchoke = math.hypot(cx - own[0], cz - own[1])
    R = int(500 / (CELL * SQUARE))
    best = None
    for gz in range(max(0, cz - R), min(gh, cz + R + 1)):
        for gx in range(max(0, cx - R), min(gw, cx + R + 1)):
            if not grid[gz * gw + gx] or math.hypot(gx - cx, gz - cz) > R:
                continue
            if math.hypot(gx - own[0], gz - own[1]) > dchoke:
                continue  # stay on our side of the choke
            gain = cell_height(hm, hw, gx, gz) - base_h
            if best is None or gain > best[2]:
                best = (gx, gz, gain)
    if not best:
        return None
    return ((best[0] + 0.5) * CELL * SQUARE, (best[1] + 0.5) * CELL * SQUARE, best[2])

ENGINE_WIND = (5.0, 25.0)  # Spring MapInfo.cpp defaults when a map sets no wind (engine fact)

_SANDBOX = """
local src = ...
local env = {
  pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber,
  select = select, unpack = unpack, pcall = pcall, error = error, assert = assert, setmetatable = setmetatable,
  getmetatable = getmetatable, rawget = rawget, rawset = rawset,
  math = math, string = string, table = table,
  -- the engine tables a mapinfo may touch; no file, os or io access
  VFS = { Include = function() return {} end, FileExists = function() return false end, DirList = function() return {} end,
          LoadFile = function() return nil end, RAW_FIRST = 0, ZIP = 0, MAP = 0, GAME = 0, MOD = 0, BASE = 0 },
  Spring = { GetMapOptions = function() return {} end, GetModOptions = function() return {} end, Echo = function() end,
             Log = function() end },
  getfenv = function() return {} end, Game = {}, Script = {},
}
env._G = env
local f, err = loadstring(src, "mapinfo")
if not f then error(err) end
setfenv(f, env)
local ok, res = pcall(f)
if not ok then error(res) end
return res
"""
_lua = None


def eval_mapinfo(info):
    """Run mapinfo.lua in a sandboxed Lua runtime and return its table (the same table the engine reads)."""
    global _lua
    if _lua is None:
        import lupa.luajit21 as lupa  # LuaJIT, as the Spring engine runs (Lua 5.1: loadstring/setfenv)
        _lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        _lua.execute("io = nil; os = nil; require = nil; dofile = nil; loadfile = nil; package = nil; debug = nil")
    return _lua.eval("function(src) " + _SANDBOX.replace("local src = ...", "") + " end")(info)


def parse_wind(info):
    """The map's wind range: atmosphere.minWind/maxWind of the evaluated mapinfo.lua (keys are case-insensitive
    in the engine), the engine defaults when unset, None when the file can't be evaluated."""
    if not info:
        return list(ENGINE_WIND)
    try:
        t = eval_mapinfo(info)
    except Exception:
        return None
    if t is None:
        return None
    atm = None
    for k, v in t.items():
        if isinstance(k, str) and k.lower() == "atmosphere":
            atm = v
    lo, hi = ENGINE_WIND
    if atm is not None:
        for k, v in atm.items():
            if isinstance(k, str) and k.lower() == "minwind" and isinstance(v, (int, float)):
                lo = float(v)
            if isinstance(k, str) and k.lower() == "maxwind" and isinstance(v, (int, float)):
                hi = float(v)
    return [lo, hi]


def read_info(path):
    with py7zr.SevenZipFile(path, "r") as z:
        names = z.getnames()
    info = next((n for n in names if n.lower() == "mapinfo.lua"), None) or next((n for n in names if n.lower().endswith("/mapinfo.lua")), None)
    if not info:
        return ""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        with py7zr.SevenZipFile(path, "r") as z:
            z.extract(path=tmp, targets=[info])
        return open(os.path.join(tmp, *info.split("/")), "rb").read().decode("utf-8", "replace")


def fill_spots(maps_dir, report, names):
    """Add extractor spot coordinates [[x, z], ...] to an existing report for the named maps (all when none)."""
    reps = json.load(open(report))
    for r in reps:
        if names and r["name"] not in names:
            continue
        try:
            files, smf_name, info_name = read_archive(os.path.join(maps_dir, r["file"]))
            info = files.get(info_name, b"").decode("utf-8", "replace") if info_name else ""
            ov = {}
            blk = re.search(r"smf\s*=\s*\{(.*?)\}", info, re.S | re.I)
            if blk:
                for k, key in (("minheight", "min"), ("maxheight", "max")):
                    m = re.search(k + r"\s*=\s*(-?[\d.]+)", blk.group(1), re.I)
                    if m:
                        ov[key] = float(m.group(1))
            r["spots"] = [[round(sp[0]), round(sp[1])] for sp in mex_spots(parse_smf(files[smf_name], ov))]
            print(r["name"], len(r["spots"]), "spots")
        except Exception as e:
            print("FAIL", r["file"], e)
    json.dump(reps, open(report, "w"), indent=1)


def fill_wind(maps_dir, report):
    reps = json.load(open(report))
    for r in reps:
        try:
            r["wind"] = parse_wind(read_info(os.path.join(maps_dir, r["file"])))
        except Exception as e:
            print("FAIL", r["file"], e)
    json.dump(reps, open(report, "w"), indent=1)
    print(sum(1 for r in reps if r.get("wind")), "of", len(reps), "maps have a wind range")


def analyze(path):
    files, smf_name, info_name = read_archive(path)
    info = files.get(info_name, b"").decode("utf-8", "replace") if info_name else ""
    ov = {}
    smfblock = re.search(r"\bsmf\s*=\s*\{(.*?)\}", info, re.S | re.I)
    if smfblock:
        for k, key in (("minheight", "min"), ("maxheight", "max")):
            m = re.search(r"\b%s\s*=\s*(-?[\d.]+)" % k, smfblock.group(1), re.I)
            if m:
                ov[key] = float(m.group(1))
    smf = parse_smf(files[smf_name], ov)
    name = re.search(r'\bname\s*=\s*"([^"]+)"', info)
    version = re.search(r'\bversion\s*=\s*"([^"]*)"', info)
    mapname = (name.group(1) + ((" " + version.group(1)) if version and version.group(1) and version.group(1) not in name.group(1) else "")) if name else os.path.basename(path)
    starts = parse_starts(info)
    spots = mex_spots(smf)
    grid, gw, gh, water = passability(smf)
    size = (smf["mapx"] * SQUARE, smf["mapy"] * SQUARE)
    rep = {"file": os.path.basename(path), "name": mapname, "size": size, "starts": starts[:16],
           "mex": len(spots), "water": round(water, 3), "wind": parse_wind(info)}
    if len(starts) >= 2:
        # overall: start 0 vs the start farthest from it (on team maps start 1 is often a teammate)
        far0 = max(range(len(starts)), key=lambda j: math.dist(starts[0], starts[j]))
        d, choke, _ = path_and_choke(grid, gw, gh, starts[0], starts[far0])
        rep["base_path"] = round(d) if d else None
        rep["base_straight"] = round(math.dist(starts[0], starts[far0]))
        rep["choke_width"] = round(choke) if choke else None
        near = sum(1 for s in spots if math.dist(s[:2], starts[0]) < math.dist(s[:2], starts[far0]))
        rep["mex_per_side"] = [near, len(spots) - near]
        # per start (up to 8): our choke toward the farthest start, and the high ground over it
        rep["defence"] = []
        for i, st in enumerate(starts[:8]):
            far = max(range(len(starts)), key=lambda j: math.dist(st, starts[j]))
            _, _, sides = path_and_choke(grid, gw, gh, st, starts[far])
            sd = sides[0] if sides else None
            if not sd:
                continue
            (ccx, ccz), w = sd
            hg = high_ground(grid, gw, gh, smf["hm"], smf["hw"], (ccx, ccz), st)
            rep["defence"].append({"start": st, "choke": [(ccx + 0.5) * CELL * SQUARE, (ccz + 0.5) * CELL * SQUARE], "width": w,
                                   "high": [hg[0], hg[1]] if hg else None, "gain": round(hg[2]) if hg else 0})
    return rep


def main():
    if sys.argv[1:2] == ["--spots"]:
        fill_spots(sys.argv[2], sys.argv[3], set(sys.argv[4:]))
        return
    if sys.argv[1:2] == ["--wind"]:
        fill_wind(sys.argv[2], sys.argv[3])
        return
    maps_dir, out_json, out_as = sys.argv[1:4]
    wanted = sys.argv[4:]
    files = [os.path.join(maps_dir, f) for f in (wanted or sorted(os.listdir(maps_dir))) if f.endswith(".sd7")]
    reports = []
    for f in files:
        try:
            r = analyze(f)
            reports.append(r)
            print(f"{r['name'][:30]:30s} size={r['size']} mex={r['mex']} water={r['water']} "
                  f"path={r.get('base_path')} straight={r.get('base_straight')} choke={r.get('choke_width')} per_side={r.get('mex_per_side')}")
        except Exception as e:
            print("FAIL", os.path.basename(f), e)
    json.dump(reports, open(out_json, "w"), indent=1)
    lines = ["// GENERATED by tools/analyze_maps.py: pre-match map analysis. Do not edit.",
             "namespace MapFacts {", "",
             "class SMap { float basePath; float straight; float choke; int mex; float water;",
             "  array<float> sx, sz, cx, cz, hx, hz, gain; }  // per analysed start: start, choke point, high ground", "",
             "dictionary maps, bases;", "", "void Init()", "{"]
    for r in reports:
        d = [x for x in (r.get("defence") or []) if x and x.get("high")]
        def arr(vals):
            return "{" + ", ".join("%.0f" % v for v in vals) + "}"
        lines.append('\t{ SMap m; m.basePath = %s; m.straight = %s; m.choke = %s; m.mex = %d; m.water = %s;'
                     ' m.sx = %s; m.sz = %s; m.cx = %s; m.cz = %s; m.hx = %s; m.hz = %s; m.gain = %s; maps.set("%s", @m); }'
                     % (float(r.get("base_path") or -1), float(r.get("base_straight") or -1), float(r.get("choke_width") or -1),
                        r["mex"], r["water"],
                        arr(x["start"][0] for x in d), arr(x["start"][1] for x in d), arr(x["choke"][0] for x in d),
                        arr(x["choke"][1] for x in d), arr(x["high"][0] for x in d), arr(x["high"][1] for x in d),
                        arr(x["gain"] for x in d), r["name"].replace('"', "")))
    # maps get updated: also index by base name (version stripped), so a new version of a known map
    # falls back to the newest analysed version of it (layouts rarely change between versions)
    def base(n):
        n = n.rstrip()
        while n and n[-1] in "0123456789._ -vV":
            n = n[:-1]
        return n.lower()
    seen = set()
    for r in sorted(reports, key=lambda r: r["name"], reverse=True):
        b = base(r["name"])
        if b and b not in seen:
            seen.add(b)
            lines.append('\t{ SMap@ m; if (maps.get("%s", @m)) bases.set("%s", @m); }' % (r["name"].replace('"', ""), b.replace('"', "")))
    lines += ["}", "",
              "string Base(const string& in name)", "{", "\tint n = int(name.length());",
              "\twhile (n > 0 && \"0123456789._ -vV\".findFirst(name.substr(n - 1, 1)) >= 0)", "\t\t--n;",
              "\tstring b = name.substr(0, n);", "\tfor (uint i = 0; i < b.length(); ++i)",
              "\t\tif (b[i] >= 65 && b[i] <= 90) b[i] = b[i] + 32;", "\treturn b;", "}", "",
              "SMap@ Get(const string& in name)", "{", "\tSMap@ m;", "\tif (maps.get(name, @m))", "\t\treturn m;",
              "\tif (bases.get(Base(name), @m))  // another version of an analysed map", "\t\treturn m;",
              "\treturn null;", "}", "", "}  // namespace MapFacts"]
    open(out_as, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print(f"{len(reports)} maps -> {out_json}, {out_as}")


if __name__ == "__main__":
    main()
